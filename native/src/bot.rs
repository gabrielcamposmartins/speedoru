//! Piloto do computador (base nativa do BotDriver, scripts/race/bot_driver.gd): direção, velocidade,
//! tráfego (ultrapassar, seguir, dar passagem), boxes e sair do muro, a cada passo de física. O
//! comentário do topo do bot_driver.gd descreve o comportamento.
//!
//! O estado dos outros carros (RaceEntry, GDScript) é lido uma vez por passo de física numa foto
//! (`Snap`) compartilhada por todos os bots da corrida.

use std::cell::RefCell;
use std::f64::consts::TAU;
use std::rc::Rc;
use std::sync::atomic::{AtomicI64, Ordering};

use godot::builtin::AnyArray;
use godot::classes::{Engine, INode, RefCounted, Resource, Script, VehicleBody3D};
use godot::global::{randf, randf_range, randi};
use godot::prelude::*;

use crate::car::F1CarCore;
use crate::manager::RaceEntryCore;
use crate::path::{LineCore, PathCore};
use crate::util::{clamp, lerp, move_toward, signf, smoothstep};

const EASY: i64 = 0;
const HARD: i64 = 2;

const RACE: i64 = 0;
const PIT_IN: i64 = 1;
const PIT_STOP: i64 = 2;
const PIT_OUT: i64 = 3;

/// Reação na largada (min, max) e ruído lateral por dificuldade (os mesmos de BotDriver.PRESETS).
const REACTION: [(f64, f64); 3] = [(0.45, 0.8), (0.28, 0.5), (0.17, 0.3)];
const NOISE: [f64; 3] = [0.7, 0.35, 0.12];
const WHEELBASE: f64 = 3.6;
const PIT_SPEED: f64 = 21.5;
const FOLLOW_DECEL: f64 = 9.0;
const PASS_STRAIGHT: f64 = 90.0;
const PASS_MARGIN: [f64; 3] = [2.0, 0.4, 0.2];
const PASS_RANGE: f64 = 60.0;
const BOX_APPROACH: f64 = 18.0;
const STUCK_PROGRESS: f64 = 2.5;
const RECOVER_TIME: f64 = 1.6;
const RECOVER_TIME_STEP: f64 = 0.8;
const RECOVER_TRIES: i64 = 3;
const YIELD_RANGE: f64 = 25.0;
const YIELD_LIFT: [f64; 2] = [0.9, 0.95];
const TRAFFIC_EVERY: u64 = 2;

static REVERSALS: AtomicI64 = AtomicI64::new(0);
static PUT_BACKS: AtomicI64 = AtomicI64::new(0);

/// Um carro da corrida, como estava no começo do passo de física.
struct Snap {
    obj: Gd<RefCounted>,
    id: InstanceId,
    s: f64,
    lateral: f64,
    in_pit: bool,
    in_pit_stop: bool,
    retired: bool,
    person: bool,
    has_car: bool,
    vel: Vector3,
    speed: f64,
}

type Snapshot = Rc<Vec<Snap>>;

thread_local! {
    /// Foto dos carros: (RaceManager, quadro de física, foto).
    static CACHE: RefCell<Option<(InstanceId, u64, Snapshot)>> = const { RefCell::new(None) };
}

/// Solta a foto (antes de o Godot desligar: ela guarda referências a objetos dele).
pub fn clear_cache() {
    CACHE.with(|c| *c.borrow_mut() = None);
}

fn res_f(res: &Gd<Resource>, key: &str) -> f64 {
    res.get(key).try_to::<f64>().unwrap_or(0.0)
}

fn script_const(obj: &Gd<Object>, key: &str, fallback: f64) -> f64 {
    obj.get_script()
        .and_then(|s| s.try_cast::<Script>().ok())
        .and_then(|s| s.get_script_constant_map().get(&Variant::from(key)))
        .and_then(|v| v.try_to::<f64>().ok())
        .unwrap_or(fallback)
}

/// Estado do próprio carro neste passo.
struct Me {
    s: f64,
    lateral: f64,
    progress: f64,
    crossings: i64,
    pit_count: i64,
    in_pit: bool,
    race_time: f64,
    garage: i64,
    finished_and_parked: bool,
}

#[derive(GodotClass)]
#[class(init, base=Node)]
pub struct BotDriverCore {
    #[var]
    profile: PackedFloat32Array,
    /// BotDriver.Difficulty
    #[var]
    #[init(val = 1)]
    difficulty: i64,
    /// BotDriver.Mode
    #[var]
    mode: i64,
    /// Volta (contagem de cruzamentos da linha) em que vai parar nos boxes; -1 = não para.
    #[var]
    #[init(val = -1)]
    pit_lap: i64,
    /// CarConfig.TyreCompound (HARD)
    #[var]
    #[init(val = 2)]
    pit_compound: i64,
    #[var]
    released: bool,
    /// Faixa lateral do grid: mantida no começo da corrida para não fechar os vizinhos na largada.
    #[var]
    #[init(val = f64::INFINITY)]
    start_lateral: f64,
    #[var]
    _offset_target: f64,
    #[var]
    _passing: Option<Gd<RefCounted>>,
    #[var]
    #[init(val = 1.0)]
    _pass_side: f64,
    #[var]
    _stop_timer: f64,

    offset: f64,
    side_by_side: bool,
    rejoin: f64,
    stuck_timer: f64,
    noise_phase: f64,
    pit_lateral: f64,
    prog_ref: f64,
    prog_t: f64,
    recover: f64,
    recover_tries: i64,
    stuck_total: f64,
    #[init(val = (0.0, f64::INFINITY))]
    traffic_cache: (f64, f64),
    #[init(val = randi() as u64 % TRAFFIC_EVERY)]
    traffic_phase: u64,

    car: Option<Gd<F1CarCore>>,
    body: Option<Gd<VehicleBody3D>>,
    track: Option<Gd<Node>>,
    line: Option<Gd<LineCore>>,
    path: Option<Gd<PathCore>>,
    entry: Option<Gd<RefCounted>>,
    manager: Option<Gd<Node>>,
    // Pista (TrackLayout e RaceTrack), lidos uma vez
    pit_entry_s: f64,
    pit_exit_s: f64,
    pit_taper: f64,
    pit_side: i64,
    pit_lane_width: f64,
    garage_center_s: f64,
    garage_count: f64,
    garage_width: f64,
    pit_width: Vec<f32>,
    pit_wall_strip: f64,
    pit_stop_min: f64,
    pit_stop_max: f64,
    sc_speed: f64,

    base: Base<Node>,
}

#[godot_api]
impl INode for BotDriverCore {
    fn physics_process(&mut self, delta: f64) {
        self.tick(delta);
    }
}

#[godot_api]
impl BotDriverCore {
    /// Liga o piloto ao carro, à pista e à corrida (chamado pelo BotDriver.setup).
    #[func]
    fn _core_setup(&mut self, car: Gd<F1CarCore>, track: Gd<Node>, line: Gd<LineCore>, entry: Gd<RefCounted>, manager: Gd<Node>) {
        self.noise_phase = randf() * TAU;
        self.body = Some(car.clone().upcast());
        self.car = Some(car);
        self.path = line.bind().path.clone();
        self.line = Some(line);
        if let Ok(lay) = track.get("layout").try_to::<Gd<Resource>>() {
            self.pit_entry_s = res_f(&lay, "pit_entry_s");
            self.pit_exit_s = res_f(&lay, "pit_exit_s");
            self.pit_taper = res_f(&lay, "pit_taper");
            self.pit_side = lay.get("pit_side").try_to::<i64>().unwrap_or(-1);
            self.pit_lane_width = res_f(&lay, "pit_lane_width");
            self.garage_center_s = res_f(&lay, "garage_center_s");
            self.garage_count = res_f(&lay, "garage_count");
            self.garage_width = res_f(&lay, "garage_width");
        }
        self.pit_width = track.get("pit_width").try_to::<PackedFloat32Array>().map(|a| a.to_vec()).unwrap_or_default();
        self.pit_wall_strip = script_const(&track.clone().upcast(), "PIT_WALL_STRIP", 3.0);
        self.pit_stop_min = script_const(&manager.clone().upcast(), "PIT_STOP_MIN", 2.0);
        self.pit_stop_max = script_const(&manager.clone().upcast(), "PIT_STOP_MAX", 4.0);
        self.sc_speed = try_load::<Script>("res://scripts/race/safety_car.gd")
            .ok()
            .and_then(|s| s.get_script_constant_map().get(&Variant::from("SPEED")))
            .and_then(|v| v.try_to::<f64>().ok())
            .unwrap_or(50.0);
        self.track = Some(track);
        self.entry = Some(entry);
        self.manager = Some(manager);
    }

    /// Levado ao box depois de uma batida (RaceControl): parado na vaga, conserto de `seconds`.
    #[func]
    fn force_pit_stop(&mut self, seconds: f64) {
        let (Some(mut entry), Some(manager), Some(mut car)) = (self.entry.clone(), self.manager.clone(), self.car.clone())
        else {
            return;
        };
        self.mode = PIT_STOP;
        self._stop_timer = seconds + randf_range(self.pit_stop_min, self.pit_stop_max);
        entry.set("pit_stop_start", &manager.get("race_time"));
        self._passing = None;
        self.offset = 0.0;
        self.stuck_timer = 0.0;
        car.bind_mut().hold = true;
        self.call_manager("begin_pit_stop");
    }

    #[func]
    fn reaction_time(&self) -> f64 {
        let (lo, hi) = REACTION[self.difficulty.clamp(0, 2) as usize];
        randf_range(lo, hi)
    }

    /// Distância à frente (com sinal, entre -L/2 e L/2) de `target_s` a partir de `s`.
    #[func]
    fn _ahead(&self, target_s: f64, s: f64) -> f64 {
        self.path.as_ref().map(|p| p.bind().ahead(target_s, s)).unwrap_or(0.0)
    }

    /// Lógica de tráfego (para os testes): Vector2(deslocamento lateral, velocidade máxima).
    #[func(rename = _traffic)]
    fn traffic_func(&mut self, s: f64, v: f64, my_lateral: f64) -> Vector2 {
        let snap = self.snapshot(true);
        let me = self.me();
        let (x, y) = self.traffic(&snap, &me, s, v, my_lateral);
        Vector2::new(x as f32, y as f32)
    }

    #[func(rename = _straight_ahead)]
    fn straight_ahead_func(&self, s: f64, distance: f64) -> bool {
        self.straight_ahead(s, distance)
    }

    #[func(rename = _corner_inside)]
    fn corner_inside_func(&self, s: f64, distance: f64) -> f64 {
        self.corner_inside(s, distance)
    }

    #[func(rename = _pit_release_clear)]
    fn pit_release_clear_func(&mut self, s: f64) -> bool {
        let snap = self.snapshot(true);
        self.pit_release_clear(&snap, s)
    }

    /// Contadores (testes/diagnóstico): ré para sair do muro e volta à pista.
    #[func]
    fn reversal_count() -> i64 {
        REVERSALS.load(Ordering::Relaxed)
    }

    #[func]
    fn put_back_count() -> i64 {
        PUT_BACKS.load(Ordering::Relaxed)
    }
}

impl BotDriverCore {
    /// BotDriver.Mode atual (para o RaceManager).
    pub fn mode_value(&self) -> i64 {
        self.mode
    }

    fn entry_id(&self) -> Option<InstanceId> {
        self.entry.as_ref().map(|e| e.instance_id())
    }

    /// Chama um método do RaceManager com a própria entrada (begin_pit_stop, end_pit_stop…). O
    /// GDScript pode chamar este bot de volta (force_pit_stop): a chamada é reentrante.
    fn call_manager(&mut self, method: &str) {
        let (Some(mut manager), Some(entry)) = (self.manager.clone(), self.entry.clone()) else { return };
        let _guard = self.base_mut();
        manager.call(method, &[entry.to_variant()]);
        drop(_guard);
        // O estado dos carros mudou (boxes): a próxima leitura refaz a foto
        CACHE.with(|c| *c.borrow_mut() = None);
    }

    fn control(&self) -> Option<Gd<Object>> {
        self.manager.as_ref().and_then(|m| m.get("control").try_to::<Gd<Object>>().ok())
    }

    fn yellow(&self, control: &Option<Gd<Object>>) -> bool {
        control.as_ref().map(|c| c.get("yellow").try_to::<bool>().unwrap_or(false)).unwrap_or(false)
    }

    fn is_involved(&mut self, control: &Option<Gd<Object>>, e: &Gd<RefCounted>) -> bool {
        let Some(mut c) = control.clone() else { return false };
        let _guard = self.base_mut();
        c.call("is_involved", &[e.to_variant()]).try_to::<bool>().unwrap_or(false)
    }

    fn me(&self) -> Me {
        let e = self.entry.clone().expect("BotDriver sem entrada");
        let e = e.cast::<RaceEntryCore>();
        let e = e.bind();
        Me {
            s: e.s,
            lateral: e.lateral,
            progress: e.progress,
            crossings: e.crossings,
            pit_count: e.pit_count,
            in_pit: e.in_pit,
            race_time: e.race_time,
            garage: e.garage,
            finished_and_parked: e.finished_and_parked,
        }
    }

    /// Foto dos carros neste passo de física (refeita com `fresh`, ou a cada passo).
    fn snapshot(&self, fresh: bool) -> Snapshot {
        let manager = self.manager.as_ref().expect("BotDriver sem corrida");
        let key = manager.instance_id();
        let frame = Engine::singleton().get_physics_frames();
        if !fresh {
            let hit = CACHE.with(|c| {
                c.borrow().as_ref().and_then(|(k, f, snap)| (*k == key && *f == frame).then(|| snap.clone()))
            });
            if let Some(snap) = hit {
                return snap;
            }
        }
        let mut out = Vec::new();
        if let Ok(entries) = manager.get("entries").try_to::<AnyArray>() {
            for v in entries.iter_shared() {
                let Ok(entry) = v.try_to::<Gd<RaceEntryCore>>() else { continue };
                let e = entry.bind();
                let car = e.car.clone().filter(|c| c.is_instance_valid()).map(|c| c.upcast::<VehicleBody3D>());
                let vel = car.as_ref().map(|c| c.get_linear_velocity()).unwrap_or(Vector3::ZERO);
                out.push(Snap {
                    id: entry.instance_id(),
                    s: e.s,
                    lateral: e.lateral,
                    in_pit: e.in_pit,
                    in_pit_stop: e.in_pit_stop,
                    retired: e.retired,
                    person: e.is_player || e.is_human,
                    has_car: car.is_some(),
                    speed: vel.length() as f64,
                    vel,
                    obj: entry.clone().upcast(),
                });
            }
        }
        let snap = Rc::new(out);
        CACHE.with(|c| *c.borrow_mut() = Some((key, frame, snap.clone())));
        snap
    }

    fn path(&self) -> GdRef<'_, PathCore> {
        self.path.as_ref().expect("BotDriver sem pista").bind()
    }

    fn line_lateral(&self, s: f64) -> f64 {
        let line = self.line.as_ref().expect("BotDriver sem linha").bind();
        line.lateral_at_s(&self.path(), s)
    }

    fn garage_s(&self, index: i64) -> f64 {
        self.garage_center_s + (index as f64 - (self.garage_count - 1.0) * 0.5) * self.garage_width
    }

    fn pit_width_at(&self, i: usize) -> f64 {
        self.pit_width.get(i).copied().unwrap_or(0.0) as f64
    }

    fn sample_profile(&self, s: f64) -> f64 {
        self.path().sample_arr(self.profile.as_slice(), s)
    }

    fn tick(&mut self, delta: f64) {
        let (Some(car), Some(entry)) = (self.car.clone(), self.entry.clone()) else { return };
        if entry.clone().cast::<RaceEntryCore>().bind().retired {
            return;
        }
        let control = self.control();
        // Roda arrancada: batida forte (bandeira amarela; o RaceControl o leva ao box)
        if self.released && self.mode != PIT_STOP && control.is_some() {
            let broken = car.bind().wheel_broken.iter_shared().any(|v| v.try_to::<bool>().unwrap_or(false));
            if broken {
                let mut c = control.clone().unwrap();
                let _guard = self.base_mut();
                c.call("report_crash", &[entry.to_variant()]);
            }
        }
        let me = self.me();
        let mut car = car;
        if !self.released || me.finished_and_parked {
            let mut c = car.bind_mut();
            c.throttle_input = 0.0;
            c.steer_input = 0.0;
            c.brake_input = if me.finished_and_parked { 1.0 } else { 0.0 };
            return;
        }
        let s = me.s;
        let body = self.body.clone().unwrap();
        let v = body.get_linear_velocity().length() as f64;
        // --- Pit: decide e acompanha a máquina de estados
        if self.mode == RACE && self.pit_lap >= 0 && me.pit_count == 0 && me.crossings >= self.pit_lap {
            let to_entry = self._ahead(self.pit_entry_s, s);
            if to_entry > 30.0 && to_entry < 260.0 {
                self.mode = PIT_IN;
            }
        }
        if self.start_lateral == f64::INFINITY {
            self.start_lateral = me.lateral;
        }
        let yellow = self.yellow(&control);
        let crashed = self.is_involved(&control, &entry);
        // Limitador só nos boxes (sob amarela o bot acompanha o safety car pela velocidade)
        car.bind_mut().limiter_on = self.mode != RACE && self.mode != PIT_STOP;
        let mut target_lateral = self.planned_lateral(s, me.progress);
        let mut speed_target = self.sample_profile(s + 4.0 + v * 0.15);
        // Primeira volta até depois da 1ª chicane: freia antes (o pelotão se espalha sem batidas)
        if me.progress < 1100.0 && speed_target < 70.0 {
            speed_target *= 0.86;
        }
        if yellow && !crashed && self.mode == RACE {
            // Sob amarela: no máximo um pouco acima do safety car (o pelotão se junta atrás dele)
            speed_target = speed_target.min(self.sc_speed * 1.15);
            if let Some(sc) = control
                .as_ref()
                .and_then(|c| c.get("safety_car").try_to::<Gd<Object>>().ok())
            {
                let ds_sc = sc.get("progress").try_to::<f64>().unwrap_or(0.0) - me.progress;
                if ds_sc > -1.0 && ds_sc < 160.0 {
                    let sc_v = sc.get("speed").try_to::<f64>().unwrap_or(0.0);
                    speed_target = speed_target.min((sc_v + (ds_sc - 30.0) * 0.5).max(2.0));
                }
            }
        }
        match self.mode {
            PIT_IN | PIT_OUT => {
                let pit = self.pit_plan(&me, s, v);
                target_lateral = pit.0;
                speed_target = speed_target.min(pit.1);
                // Fila indiana só dentro da faixa dos boxes; antes da entrada desvia como na corrida
                if me.in_pit || self.mode == PIT_OUT {
                    let snap = self.snapshot(false);
                    speed_target = speed_target.min(self.pit_traffic(&snap, &me, s, me.lateral));
                }
                if self.mode == PIT_IN && self._ahead(self.garage_s(me.garage), s).abs() < 1.2 && v < 1.2 {
                    self.mode = PIT_STOP;
                    self._stop_timer = randf_range(self.pit_stop_min, self.pit_stop_max);
                    self.call_manager("begin_pit_stop");
                }
                let to_exit = self._ahead(self.pit_exit_s, s);
                if self.mode == PIT_OUT && to_exit < -5.0 && to_exit > -400.0 {
                    self.mode = RACE;
                    self.rejoin = 1.0;
                }
            }
            PIT_STOP => {
                {
                    let mut c = car.bind_mut();
                    c.hold = true;
                    c.throttle_input = 0.0;
                    c.brake_input = 1.0;
                    c.steer_input = 0.0;
                }
                self._stop_timer -= delta;
                // Liberação segura: não sai do box na frente de quem vem pela pista dos boxes
                if self._stop_timer <= 0.0 {
                    let snap = self.snapshot(false);
                    if self.pit_release_clear(&snap, s) {
                        car.bind_mut().hold = false;
                        let compound = self.pit_compound;
                        car.bind_mut().change_tyres(compound);
                        self.mode = PIT_OUT;
                        self.call_manager("end_pit_stop");
                    }
                }
                return;
            }
            _ => {}
        }
        // Volta à linha de corrida aos poucos depois dos boxes
        if self.mode == RACE && self.rejoin > 0.0 {
            self.rejoin = (self.rejoin - delta * 0.6).max(0.0);
            target_lateral = lerp(target_lateral, self.pit_lateral, self.rejoin);
        }
        // --- Tráfego: ultrapassar, seguir ou desviar (também indo para o box, antes da entrada)
        if self.mode == RACE || (self.mode == PIT_IN && !me.in_pit) {
            // Sob amarela, a cada passo (a regra de não ultrapassar é justa)
            let frame = Engine::singleton().get_physics_frames();
            if (frame + self.traffic_phase) % TRAFFIC_EVERY == 0 || self.traffic_cache.1 == f64::INFINITY || yellow {
                self._offset_target = 0.0;
                let snap = self.snapshot(false);
                self.traffic_cache = self.traffic(&snap, &me, s, v, me.lateral);
            }
            let traffic = self.traffic_cache;
            self._offset_target = traffic.0;
            speed_target = speed_target.min(traffic.1);
            // Desvia mais rápido com alguém lado a lado
            let rate = if self.side_by_side { 3.0 } else { 1.6 };
            self.offset = move_toward(self.offset, self._offset_target, delta * rate);
            target_lateral += self.offset;
            // Pilotos fáceis "passeiam" um pouco pela pista
            target_lateral += (me.race_time * 0.37 + self.noise_phase).sin() * NOISE[self.difficulty.clamp(0, 2) as usize];
        }
        let i = self.path().index_at_s(s);
        if self.mode == RACE {
            let p = self.path();
            target_lateral = clamp(target_lateral, -(p.width_right[i] as f64) + 1.1, p.width_left[i] as f64 - 1.1);
        }
        if self.recover > 0.0 {
            self.reverse_out(&mut car, &me, delta, s, v, target_lateral);
            return;
        }
        car.bind_mut().reverse_input = 0.0;
        self.steer(&mut car, s, v, target_lateral);
        Self::speed(&mut car, v, speed_target);
        self.check_stuck(&mut car, &me, delta, v, speed_target);
    }

    fn steer(&self, car: &mut Gd<F1CarCore>, s: f64, v: f64, target_lateral: f64) {
        let look = clamp(6.0 + v * 0.42, 8.0, 42.0);
        let mut lat_ahead = target_lateral;
        if self.mode == RACE {
            lat_ahead = self.line_lateral(s + look) + (target_lateral - self.line_lateral(s));
        }
        let target = self.path().position(s + look, lat_ahead);
        let body = self.body.as_ref().unwrap();
        let xf = body.get_global_transform();
        let local = xf.affine_inverse() * target;
        let alpha = (local.x as f64).atan2(local.z as f64);
        let mut delta_angle = (2.0 * WHEELBASE * alpha.sin() / look).atan();
        // Amortece a guinada (evita "serpentear" em alta)
        let yaw_rate = body.get_angular_velocity().dot(xf.basis.col_b()) as f64;
        let expected = v * alpha.sin() * 2.0 / look;
        delta_angle -= (yaw_rate - expected) * 0.02;
        let mut c = car.bind_mut();
        let t = clamp(c.forward_speed.abs() / c.steer_speed_reference, 0.0, 1.0);
        let limit = lerp(c.max_steer_angle, c.high_speed_steer_angle, t.sqrt());
        c.steer_input = clamp(delta_angle / limit.max(0.001), -1.0, 1.0);
    }

    fn speed(car: &mut Gd<F1CarCore>, v: f64, target: f64) {
        let err = target - v;
        let mut c = car.bind_mut();
        if err > 0.4 {
            c.throttle_input = clamp(0.45 + err * 0.25, 0.0, 1.0);
            c.brake_input = 0.0;
        } else if err > -1.2 {
            c.throttle_input = 0.3;
            c.brake_input = 0.0;
        } else {
            c.throttle_input = 0.0;
            c.brake_input = clamp(-err * 0.12, 0.1, 1.0);
        }
    }

    /// Retorna (deslocamento lateral desejado em relação à linha, velocidade máxima).
    /// Ultrapassagem com memória: escolhe um lado e mantém até ficar 10 m à frente; só começa em
    /// reta. Nas curvas segue o carro da frente com folga.
    fn traffic(&mut self, snap: &[Snap], me: &Me, s: f64, v: f64, my_lateral: f64) -> (f64, f64) {
        let mut max_speed = f64::INFINITY;
        let line_lat = self.line_lateral(s);
        self.side_by_side = false;
        let i = self.path().index_at_s(s);
        let straight = self.straight_ahead(s, PASS_STRAIGHT);
        let my_id = self.entry_id();
        let control = self.control();
        let yellow = self.yellow(&control);
        let find = |id: InstanceId| snap.iter().position(|o| o.id == id);
        // Continua (ou desiste de) uma ultrapassagem em andamento
        if let Some(p) = self._passing.clone() {
            let me_obj = self.entry.clone().unwrap();
            if yellow && !self.is_involved(&control, &p) && !self.is_involved(&control, &me_obj) {
                self._passing = None;
            }
        }
        if let Some(pk) = self._passing.as_ref().and_then(|p| find(p.instance_id())) {
            let ps = &snap[pk];
            let ds_pass = self._ahead(ps.s, s);
            // Desiste se ainda não chegou ao lado dele e a curva está perto, ou se está POR FORA da
            // curva que chega sem já estar à frente; por dentro, segue
            let corner_near = !self.straight_ahead(s, 40.0);
            if ds_pass < -10.0
                || ds_pass > PASS_RANGE + 10.0
                || ps.in_pit
                || (corner_near && ds_pass > 6.0)
                || (corner_near && ds_pass > -3.0 && self._pass_side != self.corner_inside(s, 60.0))
            {
                self._passing = None;
            }
        }
        let passing_id = self._passing.as_ref().map(|p| p.instance_id());
        let mut follow: Option<usize> = None;
        let mut follow_ds = f64::INFINITY;
        let yields = self.difficulty != HARD && !yellow && self.mode == RACE;
        // Sob amarela ninguém ultrapassa: qualquer carro à frente (fora dos boxes e da batida) vira
        // o carro a seguir, mesmo em outra linha da pista
        let no_pass = yellow && {
            let e = self.entry.clone().unwrap();
            !self.is_involved(&control, &e)
        };
        let mut attacker: Option<usize> = None;
        let mut attacker_ds = f64::NEG_INFINITY;
        for (k, other) in snap.iter().enumerate() {
            if Some(other.id) == my_id || !other.has_car || other.in_pit || other.retired {
                continue;
            }
            let ds = self._ahead(other.s, s);
            // Humano atacando por trás (mais rápido, ou já colado): o bot fácil/médio dá passagem
            if yields
                && other.person
                && ds < -1.0
                && ds > -YIELD_RANGE
                && ds > attacker_ds
                && (other.speed > v - 0.5 || ds > -8.0)
            {
                attacker = Some(k);
                attacker_ds = ds;
            }
            if !(-8.0..=90.0).contains(&ds) {
                continue;
            }
            // Onde eu vou estar quando chegar lá (inclui a faixa do grid no começo)
            let my_there = self.planned_lateral(other.s, me.progress + ds) + self.offset;
            let dlat = other.lateral - my_there;
            // Em volta de um humano a faixa "ocupada" é um pouco mais larga
            let width = if other.person { 2.9 } else { 2.5 };
            let mut in_my_way = dlat.abs() < width || (ds < 35.0 && (other.lateral - my_lateral).abs() < width - 0.2);
            if no_pass && !self.is_involved(&control, &other.obj) {
                in_my_way = true;
                // Lado a lado e ele um pouco à frente: fica atrás
                if ds > 0.0 && ds <= 4.5 {
                    max_speed = max_speed.min(other.speed - 1.0);
                }
            }
            let is_passing = Some(other.id) == passing_id;
            if ds > 4.5 && in_my_way && !is_passing {
                if ds < follow_ds {
                    follow = Some(k);
                    follow_ds = ds;
                }
            } else if ds.abs() <= 8.0 && (other.lateral - my_lateral).abs() < 3.2 && !is_passing {
                // Lado a lado: abre espaço (largura do carro + folga)
                self._offset_target = (my_lateral - line_lat)
                    - signf(other.lateral - my_lateral) * (3.2 - (other.lateral - my_lateral).abs());
                self.side_by_side = true;
                // Lado a lado com um humano: o fácil/médio não briga pela posição
                if yields && other.person {
                    max_speed = max_speed.min(self.yield_speed(s));
                }
                // Colado atrás e sobrepondo: tira o pé antes de tocar
                if ds > 0.5 && (other.lateral - my_lateral).abs() < 2.1 {
                    max_speed = max_speed.min(other.speed - 2.0);
                }
            }
        }
        if let Some(fk) = follow {
            let f = &snap[fk];
            let other_v = f.speed;
            let quicker = v > other_v + PASS_MARGIN[self.difficulty.clamp(0, 2) as usize];
            let mut side_choice = 0.0;
            let yellow_ok = control.is_none() || !yellow || {
                let e = self.entry.clone().unwrap();
                self.is_involved(&control, &f.obj) || self.is_involved(&control, &e)
            };
            if self._passing.is_none() && straight && quicker && follow_ds < PASS_RANGE && me.progress > 1100.0 && yellow_ok {
                let (room_left, room_right) = {
                    let p = self.path();
                    (p.width_left[i] as f64 - f.lateral, f.lateral + p.width_right[i] as f64)
                };
                // Prefere o lado de dentro da próxima curva; sem curva perto, o lado com mais espaço
                let inside = self.corner_inside(s, 160.0);
                let first = if inside != 0.0 { inside } else if room_left > room_right { 1.0 } else { -1.0 };
                for side in [first, -first] {
                    let room = if side > 0.0 { room_left } else { room_right };
                    if room > 4.2 && self.lane_clear(snap, s, f.lateral + side * 3.0) {
                        side_choice = side;
                        break;
                    }
                }
            }
            if side_choice != 0.0 {
                self._passing = Some(f.obj.clone());
                self._pass_side = side_choice;
            } else {
                // Distância de segurança proporcional à velocidade; de longe, a velocidade que ainda
                // dá para frear (FOLLOW_DECEL) até a distância de segurança atrás dele
                let gap = 6.0 + v * 0.17 + if f.person { 3.0 } else { 0.0 };
                if Some(f.id) != passing_id {
                    let room = follow_ds - gap;
                    let limit = if room < 0.0 {
                        other_v + room * 0.6
                    } else {
                        (other_v * other_v + 2.0 * FOLLOW_DECEL * room).sqrt()
                    };
                    max_speed = max_speed.min(limit);
                }
            }
        }
        // Dando passagem: abre para o lado oposto ao do atacante e tira um pouco o pé
        if let Some(ak) = attacker {
            if self._passing.is_none() && !self.side_by_side {
                let dl = snap[ak].lateral - my_lateral;
                let mut away = -signf(dl);
                if dl.abs() < 0.4 {
                    let p = self.path();
                    away = if p.width_left[i] as f64 - my_lateral > my_lateral + p.width_right[i] as f64 { 1.0 } else { -1.0 };
                }
                self._offset_target = (my_lateral - line_lat) + away * clamp(3.2 - dl.abs(), 0.0, 3.2);
                self.side_by_side = true;
                if attacker_ds > -15.0 {
                    max_speed = max_speed.min(self.yield_speed(s));
                }
            }
        }
        let mut offset = 0.0;
        if let Some(pk) = self._passing.as_ref().and_then(|p| find(p.instance_id())) {
            let ps = &snap[pk];
            offset = (ps.lateral + self._pass_side * 3.0) - line_lat;
            // Ainda colado atrás: não acelera para dentro dele
            let ds_pass = self._ahead(ps.s, s);
            if ds_pass > 0.0 && (ps.lateral - my_lateral).abs() < 2.2 {
                max_speed = max_speed.min(ps.speed + (ds_pass - 6.0) * 0.8);
            }
        } else if self._offset_target != 0.0 && self._offset_target.abs() > 0.01 {
            offset = self._offset_target;
        }
        (offset, max_speed.max(3.0))
    }

    /// Velocidade ao dar passagem: uma fração do ritmo normal daquele trecho.
    fn yield_speed(&self, s: f64) -> f64 {
        let lift = if self.difficulty <= EASY { YIELD_LIFT[0] } else { YIELD_LIFT[1] };
        self.sample_profile(s + 4.0) * lift
    }

    /// Lateral planejada (sem tráfego) num ponto: a linha de corrida; na largada, a linha deslocada
    /// pela faixa do grid até a frenagem da 1ª chicane.
    fn planned_lateral(&self, at_s: f64, at_progress: f64) -> f64 {
        let mut lat = self.line_lateral(at_s);
        if self.start_lateral != f64::INFINITY && at_progress < 520.0 {
            let keep = self.start_lateral - self.line_lateral(0.0);
            lat += keep * (1.0 - smoothstep(280.0, 520.0, at_progress));
        }
        lat
    }

    /// Ninguém perto (de 15 m atrás a 40 m à frente) na faixa `lateral`.
    fn lane_clear(&self, snap: &[Snap], s: f64, lateral: f64) -> bool {
        let my_id = self.entry_id();
        !snap.iter().any(|o| {
            if Some(o.id) == my_id || !o.has_car || o.retired {
                return false;
            }
            let ds = self._ahead(o.s, s);
            ds > -15.0 && ds < 40.0 && (o.lateral - lateral).abs() < 2.6
        })
    }

    /// Lado de dentro (+1 esquerda, -1 direita) da curva mais forte nos próximos `distance` m; 0 se
    /// não há curva.
    fn corner_inside(&self, s: f64, distance: f64) -> f64 {
        let line = self.line.as_ref().unwrap().bind();
        let p = self.path();
        let mut best = 0.0;
        let mut at = -1.0;
        for n in 0..(distance / 10.0) as i64 {
            let k = p.sample_arr(&line.curvature, s + n as f64 * 10.0).abs();
            if k > best {
                best = k;
                at = s + n as f64 * 10.0;
            }
        }
        if best < 1.0 / 450.0 {
            return 0.0;
        }
        let turn = p.tangent(at + 15.0).dot(p.lefts[p.index_at_s(at - 15.0)]);
        if turn > 0.0 {
            1.0
        } else {
            -1.0
        }
    }

    fn straight_ahead(&self, s: f64, distance: f64) -> bool {
        let line = self.line.as_ref().unwrap().bind();
        let p = self.path();
        let mut k: f64 = 0.0;
        for n in 0..(distance / 10.0) as i64 {
            k = k.max(p.sample_arr(&line.curvature, s + n as f64 * 10.0).abs());
        }
        k < 1.0 / 450.0
    }

    /// (lateral alvo, velocidade máxima) na entrada/saída dos boxes.
    fn pit_plan(&mut self, me: &Me, s: f64, v: f64) -> (f64, f64) {
        let lookahead = if self.mode == PIT_OUT { clamp(v * 0.6, 3.0, 25.0) } else { 0.0 };
        let lateral = self.pit_lane_lateral(me, s + lookahead, s);
        let to_box = self._ahead(self.garage_s(me.garage), s);
        self.pit_lateral = lateral - self.line_lateral(s);
        // Velocidade: 80 km/h entre as linhas, parando no box
        let mut max_speed;
        let to_line = self._ahead(self.pit_entry_s + self.pit_taper, s);
        if self.mode == PIT_IN {
            max_speed = if to_line > 0.0 {
                (PIT_SPEED * PIT_SPEED + 2.0 * 14.0 * (to_line - 6.0).max(0.0)).sqrt()
            } else {
                PIT_SPEED
            };
            if to_box > -2.0 && to_box < 120.0 {
                max_speed = max_speed.min((2.0 * 5.0 * (to_box - 0.3).max(0.0)).sqrt());
            }
        } else {
            let to_exit_line = self._ahead(self.pit_exit_s - self.pit_taper, s);
            max_speed = if to_exit_line > 0.0 { PIT_SPEED } else { f64::INFINITY };
        }
        (lateral, max_speed)
    }

    /// Lateral (com sinal) da faixa dos boxes que este carro segue no ponto `at_s`. `now_s`: onde o
    /// carro está (decide se ele ainda vai para a vaga ou já saiu dela).
    fn pit_lane_lateral(&self, me: &Me, at_s: f64, now_s: f64) -> f64 {
        let side = self.pit_side;
        let (i, hw) = {
            let p = self.path();
            let i = p.index_at_s(at_s);
            (i, p.half_width_at(i, side))
        };
        let w = self.pit_width_at(i);
        let lane_fast = self.pit_wall_strip + 3.4;
        let mut d = (w * 0.55).min(lane_fast);
        let box_d = self.pit_wall_strip + self.pit_lane_width * 0.72;
        let box_s = self.garage_s(me.garage);
        let to_box = self._ahead(box_s, at_s);
        let going_in = self.mode == PIT_IN && self._ahead(box_s, now_s) > -3.0;
        if going_in && to_box < BOX_APPROACH && to_box > -3.0 {
            d = lerp(d, box_d, smoothstep(BOX_APPROACH, 4.0, to_box));
        }
        if self.mode == PIT_OUT && to_box < 0.0 && to_box > -BOX_APPROACH {
            d = lerp(box_d, d, smoothstep(-1.0, -BOX_APPROACH + 2.0, to_box));
        }
        let side_f = side as f64;
        if w > 0.5 {
            side_f * (hw + d)
        } else {
            side_f * (hw - 1.6)
        }
    }

    /// Na pista dos boxes: fila indiana. Espera quem estiver no caminho que este carro vai fazer.
    fn pit_traffic(&self, snap: &[Snap], me: &Me, s: f64, my_lateral: f64) -> f64 {
        let my_id = self.entry_id();
        let mut max_speed = f64::INFINITY;
        for o in snap {
            if Some(o.id) == my_id || !o.has_car || o.retired {
                continue;
            }
            let ds = self._ahead(o.s, s);
            if !(0.5..=45.0).contains(&ds) {
                continue;
            }
            // No caminho: perto de onde eu vou passar quando chegar lá (ou de onde estou, se colado)
            let my_there = self.pit_lane_lateral(me, o.s, s);
            if (o.lateral - my_there).abs() > 2.4 && (ds > 6.0 || (o.lateral - my_lateral).abs() > 2.4) {
                continue;
            }
            // A velocidade que ainda dá para frear (6 m/s²) até 7 m atrás dele
            let room = ds - 7.0;
            let limit =
                if room < 0.0 { o.speed + room * 0.7 } else { (o.speed * o.speed + 2.0 * 6.0 * room).sqrt() };
            max_speed = max_speed.min(limit);
        }
        max_speed
    }

    /// Ninguém chegando pela faixa rápida dos boxes nos 35 m de trás (ou logo ao lado).
    fn pit_release_clear(&self, snap: &[Snap], s: f64) -> bool {
        let my_id = self.entry_id();
        for o in snap {
            if Some(o.id) == my_id || !o.has_car || o.retired || !o.in_pit || o.in_pit_stop {
                continue;
            }
            // Bot parado na faixa (fila ou enroscado) não segura a saída
            if !o.person && o.speed < 1.0 {
                continue;
            }
            // Quem não está avançando pela pista dos boxes também não
            if (o.vel.dot(self.path().tangent(o.s)) as f64) < 1.0 {
                continue;
            }
            let ds = self._ahead(o.s, s);
            // Quem vem mais rápido precisa de mais distância (2 s dele, no mínimo 35 m)
            let reach = (o.speed * 2.0).max(35.0);
            if ds > -reach && ds < 6.0 {
                return false;
            }
        }
        true
    }

    /// Ré para sair do muro: esterça ao contrário, apontando o bico de volta para a pista.
    fn reverse_out(&mut self, car: &mut Gd<F1CarCore>, me: &Me, delta: f64, s: f64, v: f64, target_lateral: f64) {
        self.recover -= delta;
        self.steer(car, s, v, target_lateral);
        let mut c = car.bind_mut();
        c.steer_input = -c.steer_input;
        c.throttle_input = 0.0;
        c.brake_input = 0.0;
        c.reverse_input = if self.recover > 0.15 { 1.0 } else { 0.0 };
        if self.recover <= 0.0 {
            c.reverse_input = 0.0;
            self.prog_ref = me.progress;
            self.prog_t = 0.0;
        }
    }

    /// Coloca o carro parado num ponto (volta à pista).
    fn place(&self, car: &mut Gd<F1CarCore>, xf: Transform3D) {
        let mut body = self.body.clone().unwrap();
        body.set_global_transform(xf);
        body.set_linear_velocity(Vector3::ZERO);
        body.set_angular_velocity(Vector3::ZERO);
        body.reset_physics_interpolation();
        car.bind_mut().reset_frame = Engine::singleton().get_physics_frames() as i64;
    }

    /// Leva o carro de volta à linha de corrida (na mesma posição da pista).
    fn put_back(&mut self, car: &mut Gd<F1CarCore>, s: f64) {
        PUT_BACKS.fetch_add(1, Ordering::Relaxed);
        self.stuck_timer = 0.0;
        self.stuck_total = 0.0;
        self.recover_tries = 0;
        let xf = self.path().frame(s, self.line_lateral(s), 0.3);
        self.place(car, xf);
    }

    /// Lateral (com sinal) da faixa rápida dos boxes no ponto `at_s`.
    fn fast_lane_lateral(&self, at_s: f64) -> f64 {
        let side = self.pit_side;
        let p = self.path();
        let i = p.index_at_s(at_s);
        let w = self.pit_width_at(i);
        let hw = p.half_width_at(i, side);
        if w > 0.5 {
            side as f64 * (hw + (w * 0.55).min(self.pit_wall_strip + 3.4))
        } else {
            side as f64 * (hw - 1.6)
        }
    }

    /// Ninguém de 2 m atrás a 25 m à frente do ponto, perto da lateral dada.
    fn spot_clear(&self, snap: &[Snap], at_s: f64, lateral: f64) -> bool {
        let my_id = self.entry_id();
        !snap.iter().any(|o| {
            if Some(o.id) == my_id || !o.has_car || o.retired {
                return false;
            }
            let ds = self._ahead(o.s, at_s);
            ds > -2.0 && ds < 25.0 && (o.lateral - lateral).abs() < 2.6
        })
    }

    /// Algum carro logo à frente (até 14 m) perto da minha faixa: parado por tráfego, não preso.
    fn blocked_ahead(&self, snap: &[Snap], me: &Me) -> bool {
        let my_id = self.entry_id();
        snap.iter().any(|o| {
            if Some(o.id) == my_id || !o.has_car || o.retired {
                return false;
            }
            let ds = self._ahead(o.s, me.s);
            ds > -2.0 && ds < 14.0 && (o.lateral - me.lateral).abs() < 3.5
        })
    }

    /// Ninguém chegando (de `behind` m atrás a 15 m à frente).
    fn gap_clear(&self, snap: &[Snap], s: f64, behind: f64) -> bool {
        let my_id = self.entry_id();
        !snap.iter().any(|o| {
            if Some(o.id) == my_id || !o.has_car || o.retired {
                return false;
            }
            let ds = self._ahead(o.s, s);
            ds > -behind && ds < 15.0
        })
    }

    /// Preso: querendo andar mas quase sem avançar ao longo da pista. Primeiro dá ré esterçando
    /// (RECOVER_TRIES vezes); se não sair, volta à pista num vão do tráfego.
    fn check_stuck(&mut self, car: &mut Gd<F1CarCore>, me: &Me, delta: f64, v: f64, speed_target: f64) {
        let hold = car.bind().hold;
        // Enroscado na entrada da vaga: depois de alguns segundos, vai direto para ela
        if self.mode == PIT_IN && v < 1.0 && self._ahead(self.garage_s(me.garage), me.s).abs() < 30.0 {
            self.stuck_timer += delta;
            if self.stuck_timer > 5.0 {
                self.stuck_timer = 0.0;
                let mut track = self.track.clone().unwrap();
                let xf = track
                    .call("get_pit_box_transform", &[me.garage.to_variant()])
                    .try_to::<Transform3D>()
                    .unwrap_or(Transform3D::IDENTITY);
                self.place(car, xf);
            }
            return;
        }
        // Enroscado saindo do box: vai para a faixa rápida logo à frente, se ela estiver livre
        if self.mode == PIT_OUT && speed_target > 3.0 && !hold {
            self.prog_t += delta;
            if self.prog_t >= 1.0 {
                self.stuck_timer = if me.progress - self.prog_ref < 1.0 { self.stuck_timer + 1.0 } else { 0.0 };
                self.prog_ref = me.progress;
                self.prog_t = 0.0;
            }
            if self.stuck_timer >= 4.0 {
                // Só a faixa à frente importa (quem está atrás espera por mim)
                let ahead_s = me.s + 8.0;
                let fast = self.fast_lane_lateral(ahead_s);
                let snap = self.snapshot(false);
                if self.spot_clear(&snap, ahead_s, fast) {
                    self.stuck_timer = 0.0;
                    PUT_BACKS.fetch_add(1, Ordering::Relaxed);
                    let xf = self.path().frame(ahead_s, fast, 0.3);
                    self.place(car, xf);
                }
            }
            return;
        }
        if self.mode != RACE || speed_target < 6.0 || hold {
            self.stuck_timer = 0.0;
            self.stuck_total = 0.0;
            self.prog_ref = me.progress;
            self.prog_t = 0.0;
            return;
        }
        self.prog_t += delta;
        if self.prog_t >= 1.0 {
            let gained = me.progress - self.prog_ref;
            self.prog_ref = me.progress;
            self.prog_t = 0.0;
            // Preso de verdade: quase parado e sem ninguém logo à frente
            let snap = self.snapshot(false);
            if gained < STUCK_PROGRESS && v < 3.0 && !self.blocked_ahead(&snap, me) {
                self.stuck_timer += 1.0;
            } else {
                self.stuck_timer = 0.0;
                self.stuck_total = 0.0;
                self.recover_tries = 0;
            }
        }
        if self.stuck_timer < 2.0 {
            return;
        }
        self.stuck_total += delta;
        let s = me.s;
        if self.recover_tries < RECOVER_TRIES {
            self.recover = RECOVER_TIME + RECOVER_TIME_STEP * self.recover_tries as f64;
            self.recover_tries += 1;
            REVERSALS.fetch_add(1, Ordering::Relaxed);
            self.stuck_timer = 0.0;
            return;
        }
        let snap = self.snapshot(false);
        if self.gap_clear(&snap, s, 60.0) || (self.stuck_total > 6.0 && self.gap_clear(&snap, s, 25.0)) {
            self.put_back(car, s);
        }
    }
}
