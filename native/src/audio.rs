//! Sons do carro a cada quadro (base nativa do CarAudio, scripts/car/car_audio.gd): mistura das
//! camadas do motor, turbo, engrenagens, vento, pneus e pisos, estouros do escapamento, batidas e
//! o passa-baixa do capacete. O GDScript cria os players e carrega os sons.

use std::cell::RefCell;
use std::collections::HashMap;
use std::f64::consts::{PI, TAU};

use godot::builtin::AnyArray;
use godot::classes::{AudioServer, AudioStream, AudioStreamPlayer3D, Engine, INode3D, VehicleBody3D};
use godot::global::{linear_to_db, randf, randf_range, randi_range};
use godot::prelude::*;

use crate::car::{F1CarCore, AIR, LOCK, SPIN};
use crate::fx::{camera_position, race_camera};
use crate::surface;
use crate::util::{clamp, lerp, move_toward, smoothstep};

const ENGINE_RPMS: [f64; 7] = [4000.0, 5500.0, 7000.0, 8500.0, 10000.0, 11500.0, 13000.0];
/// Ordem dos loops (a mesma de CarAudio.LOOPS).
const TURBO: usize = 0;
const GEAR_WHINE: usize = 1;
const WIND: usize = 2;
const TIRE_SQUEAL: usize = 3;
const TIRE_SCRUB: usize = 4;
const GRAVEL: usize = 5;
const GRASS: usize = 6;
const KERB: usize = 7;
const SCRAPE: usize = 8;
const BOOST: usize = 9;
const HELMET_EFFECT: i32 = 1;
/// RaceCamera.Mode.DRIVER
const CAMERA_DRIVER: i64 = 3;
const GEAR_REVERSE: i64 = -1;
const NEAR_BOOST_DB: f64 = 7.0;
const NEAR_CLOSE: f64 = 8.0;
const NEAR_FAR: f64 = 45.0;
const RIVAL_CULL: f64 = 260.0;
/// Só os rivais mais perto da câmera têm som (os outros ficam mudos: eram ~30 players 3D por carro
/// atualizados a cada quadro). Quem já está tocando leva vantagem de RIVAL_KEEP m na escolha (sem
/// ficar trocando entre dois carros quase à mesma distância) e entra/sai em RIVAL_FADE s.
const AUDIBLE_RIVALS: usize = 2;
const RIVAL_KEEP: f64 = 5.0;
const RIVAL_FADE: f64 = 0.25;

thread_local! {
    /// Rivais com som (CarAudioCore) e a escolha do quadro: (quadro, os mais perto).
    static RIVALS: RefCell<Vec<InstanceId>> = const { RefCell::new(Vec::new()) };
    static RANK: RefCell<(u64, Vec<InstanceId>)> = const { RefCell::new((u64::MAX, Vec::new())) };
    /// Passa-baixa do capacete: (quadro, bus) já conferidos neste quadro.
    static HELMET: RefCell<(u64, Vec<i32>)> = const { RefCell::new((u64::MAX, Vec::new())) };
}

#[derive(GodotClass)]
#[class(init, base=Node3D)]
pub struct CarAudioCore {
    #[export(range = (-30.0, 12.0))]
    #[init(val = 0.0)]
    engine_db: f64,
    #[export(range = (-30.0, 12.0))]
    #[init(val = -2.0)]
    effects_db: f64,
    #[export]
    #[init(val = true)]
    backfires: bool,
    /// Velocidade (m/s) em que as batidas da zebra soam no pitch original.
    #[export]
    #[init(val = 40.0)]
    kerb_reference_speed: f64,
    #[var]
    rival: bool,
    #[var]
    _near_db: f64,
    #[var]
    engine_load: f64,
    /// Raspando no muro/chão (0..1), escrito pelo CarDamage.
    #[var]
    pub scrape_level: f64,
    /// Bus de áudio (índice), para o passa-baixa do capacete.
    #[var]
    _bus_index: i64,

    car: Option<Gd<F1CarCore>>,
    on: Vec<Gd<AudioStreamPlayer3D>>,
    off: Vec<Gd<AudioStreamPlayer3D>>,
    loops: Vec<Gd<AudioStreamPlayer3D>>,
    pool: Vec<Gd<AudioStreamPlayer3D>>,
    shots: HashMap<String, Gd<AudioStream>>,
    boost_level: f64,
    time: f64,
    prev_throttle: f64,
    pops_left: i64,
    pop_timer: f64,
    /// Velocidade e posição do carro no passo anterior (para detectar batidas).
    #[var]
    _prev_velocity: Vector3,
    #[var]
    _prev_position: Vector3,
    impact_cooldown: f64,
    idle_detune: f64,
    idle_phase: f64,
    silent: bool,
    /// Rival entre os que têm som (0..1, com transição) e se já está na lista de rivais.
    audible: f64,
    registered: bool,
    /// Volume e pitch já aplicados em cada player (só escreve quando muda).
    on_last: Vec<(f32, f32)>,
    off_last: Vec<(f32, f32)>,
    loops_last: Vec<(f32, f32)>,
    base: Base<Node3D>,
}

fn players(arr: &AnyArray) -> Vec<Gd<AudioStreamPlayer3D>> {
    arr.iter_shared().filter_map(|v| v.try_to::<Gd<AudioStreamPlayer3D>>().ok()).collect()
}

/// Nível linear (0..1) e pitch de um loop; para os que estão em silêncio (e volta a tocar de um
/// ponto qualquer do loop: os carros não ficam em fase). `last` guarda o volume e o pitch aplicados
/// (NAN = parado): só chama o player quando algo muda de verdade.
fn set_loop(p: &mut Gd<AudioStreamPlayer3D>, last: &mut (f32, f32), level: f64, pitch: f64, offset_db: f64) {
    if level < 0.003 {
        if !last.0.is_nan() {
            if p.is_playing() {
                p.stop();
            }
            *last = (f32::NAN, f32::NAN);
        }
        return;
    }
    let db = (linear_to_db(level) + offset_db) as f32;
    let pitch = clamp(pitch, 0.3, 3.5) as f32;
    let starting = last.0.is_nan();
    if starting || (db - last.0).abs() > 0.05 {
        p.set_volume_db(db);
        last.0 = db;
    }
    if starting || (pitch - last.1).abs() > 0.0005 {
        p.set_pitch_scale(pitch);
        last.1 = pitch;
    }
    if starting && !p.is_playing() {
        let length = p.get_stream().map(|s| s.get_length()).unwrap_or(0.0);
        p.play_ex().from_position((randf() * length) as f32).done();
    }
}

/// Estado inicial do "último aplicado" de uma lista de players (todos parados).
fn stopped(n: usize) -> Vec<(f32, f32)> {
    vec![(f32::NAN, f32::NAN); n]
}

#[godot_api]
impl INode3D for CarAudioCore {
    fn process(&mut self, delta: f64) {
        let Some(car) = self.car.clone() else { return };
        self.time += delta;
        let body = car.clone().upcast::<VehicleBody3D>();
        let node: Gd<Node> = self.base().clone().upcast();
        let cam = race_camera(&node);
        let cam_pos = camera_position(&node);
        let car_pos = body.get_global_position();
        // Rival perto da câmera: reforço de volume
        if self.rival {
            let target = cam_pos
                .map(|p| NEAR_BOOST_DB * (1.0 - smoothstep(NEAR_CLOSE, NEAR_FAR, p.distance_to(car_pos) as f64)))
                .unwrap_or(0.0);
            self._near_db = move_toward(self._near_db, target, delta * 20.0);
            // Só os AUDIBLE_RIVALS rivais mais perto da câmera têm som
            let chosen = self.audible_rival(cam_pos, car_pos);
            self.audible = move_toward(self.audible, if chosen { 1.0 } else { 0.0 }, delta / RIVAL_FADE);
        }
        let far = cam_pos.is_some_and(|p| p.distance_squared_to(car_pos) as f64 > RIVAL_CULL * RIVAL_CULL);
        if self.rival && (far || self.audible <= 0.0) {
            if !self.silent {
                self.stop_all();
                self.silent = true;
            }
            return;
        }
        self.silent = false;
        let (rpm, reversing, pedal, shifting, tc) = {
            let c = car.bind();
            let reversing = c.gear == GEAR_REVERSE;
            (c.rpm, reversing, if reversing { c.reverse_input } else { c.throttle_input }, c.is_shifting(), c.tc_active)
        };
        let _ = reversing;
        let mut target = pedal;
        if shifting {
            target *= 0.3;
        }
        if tc {
            target *= 0.8;
        }
        self.engine_load = move_toward(self.engine_load, target, delta * if target > self.engine_load { 12.0 } else { 7.0 });
        self.update_engine(&car, rpm);
        self.update_effects(&car, &body, rpm, delta);
        self.update_backfire(rpm, pedal, delta);
        self.update_helmet(cam.map(|(_, mode, _)| mode == CAMERA_DRIVER).unwrap_or(false));
    }

    fn exit_tree(&mut self) {
        if self.registered {
            let id = self.base().instance_id();
            RIVALS.with(|r| r.borrow_mut().retain(|x| *x != id));
            self.registered = false;
        }
    }

    fn physics_process(&mut self, delta: f64) {
        let Some(car) = self.car.clone() else { return };
        // Rival sem som: nem as batidas
        if self.rival && self.silent {
            let body = car.clone().upcast::<VehicleBody3D>();
            self._prev_velocity = body.get_linear_velocity();
            self._prev_position = body.get_global_position();
            return;
        }
        let body = car.clone().upcast::<VehicleBody3D>();
        // Batida: mudança brusca de velocidade num único passo (> ~30 G), ignorando teleportes
        self.impact_cooldown -= delta;
        let v = body.get_linear_velocity();
        let pos = body.get_global_position();
        let jump = pos.distance_to(self._prev_position) as f64;
        let dv = (v - self._prev_velocity).length() as f64;
        let was_reset = Engine::singleton().get_physics_frames() as i64 - car.bind().reset_frame < 3;
        if self.impact_cooldown <= 0.0 && jump < 5.0 && dv > 2.5 && !was_reset {
            let strength = clamp((dv - 2.5) / 12.0, 0.0, 1.0);
            let shot = if strength > 0.5 { "impact_1" } else { "impact_2" };
            self.play_shot(shot.into(), Vector3::new(0.0, 0.4, 0.0), lerp(-10.0, 2.0, strength), randf_range(0.9, 1.1));
            self.impact_cooldown = 0.25;
        }
        self._prev_velocity = v;
        self._prev_position = pos;
    }
}

#[godot_api]
impl CarAudioCore {
    /// Liga os players criados pelo CarAudio._ready (loops na ordem de CarAudio.LOOPS).
    #[func]
    fn _core_setup(&mut self, car: Gd<F1CarCore>, on: AnyArray, off: AnyArray, loops: AnyArray, pool: AnyArray, shots: VarDictionary) {
        let body = car.clone().upcast::<VehicleBody3D>();
        self._prev_position = body.get_global_position();
        self.car = Some(car);
        self.on = players(&on);
        self.off = players(&off);
        self.loops = players(&loops);
        self.pool = players(&pool);
        self.shots = shots
            .iter_shared()
            .filter_map(|(k, v)| Some((k.to_string(), v.try_to::<Gd<AudioStream>>().ok()?)))
            .collect();
        self.idle_detune = randf_range(-0.05, 0.05);
        self.idle_phase = randf() * TAU;
        self.on_last = stopped(self.on.len());
        self.off_last = stopped(self.off.len());
        self.loops_last = stopped(self.loops.len());
    }

    /// Toca um som curto (posição local no carro).
    #[func]
    fn play_shot(&mut self, shot: GString, pos: Vector3, #[opt(default = 0.0)] db: f64, #[opt(default = 1.0)] pitch: f64) {
        let Some(stream) = self.shots.get(&shot.to_string()).cloned() else { return };
        if self.pool.is_empty() {
            return;
        }
        let mut player = match self.pool.iter().position(|p| !p.is_playing()) {
            Some(k) => self.pool[k].clone(),
            None => {
                let p = self.pool.remove(0);
                self.pool.push(p.clone());
                p
            }
        };
        player.set_stream(&stream);
        player.set_position(pos);
        player.set_volume_db((db + self.effects_db + self._near_db) as f32);
        player.set_pitch_scale(pitch as f32);
        player.play();
    }
}

impl CarAudioCore {
    fn stop_all(&mut self) {
        for (p, last) in self.on.iter_mut().zip(self.on_last.iter_mut()) {
            set_loop(p, last, 0.0, 1.0, 0.0);
        }
        for (p, last) in self.off.iter_mut().zip(self.off_last.iter_mut()) {
            set_loop(p, last, 0.0, 1.0, 0.0);
        }
        for (p, last) in self.loops.iter_mut().zip(self.loops_last.iter_mut()) {
            set_loop(p, last, 0.0, 1.0, 0.0);
        }
    }

    /// Este rival está entre os AUDIBLE_RIVALS mais perto da câmera? A escolha é feita uma vez por
    /// quadro (o primeiro rival a perguntar mede todos).
    fn audible_rival(&mut self, cam_pos: Option<Vector3>, car_pos: Vector3) -> bool {
        let me = self.base().instance_id();
        if !self.registered {
            RIVALS.with(|r| r.borrow_mut().push(me));
            self.registered = true;
        }
        let Some(cam) = cam_pos else { return true };
        let frame = Engine::singleton().get_process_frames();
        let fresh = RANK.with(|r| r.borrow().0 == frame);
        if !fresh {
            let ids = RIVALS.with(|r| r.borrow().clone());
            let mut dist: Vec<(f64, InstanceId)> = Vec::with_capacity(ids.len());
            let mut alive: Vec<InstanceId> = Vec::with_capacity(ids.len());
            for id in ids {
                let entry = if id == me {
                    // Este (já está em uso: não dá para ler pelo objeto)
                    Some((car_pos, self.audible))
                } else {
                    Gd::<CarAudioCore>::try_from_instance_id(id).ok().and_then(|other| {
                        let o = other.bind();
                        let car = o.car.as_ref().filter(|c| c.is_instance_valid())?;
                        if !o.rival {
                            return None;
                        }
                        Some((car.clone().upcast::<Node3D>().get_global_position(), o.audible))
                    })
                };
                if let Some((pos, audible)) = entry {
                    alive.push(id);
                    let keep = if audible > 0.0 { RIVAL_KEEP } else { 0.0 };
                    dist.push((cam.distance_to(pos) as f64 - keep, id));
                }
            }
            RIVALS.with(|r| *r.borrow_mut() = alive);
            dist.sort_by(|a, b| a.0.total_cmp(&b.0));
            let best: Vec<InstanceId> = dist.iter().take(AUDIBLE_RIVALS).map(|(_, id)| *id).collect();
            RANK.with(|r| *r.borrow_mut() = (frame, best));
        }
        RANK.with(|r| r.borrow().1.contains(&me))
    }

    fn update_engine(&mut self, car: &Gd<F1CarCore>, rpm: f64) {
        let n = ENGINE_RPMS.len();
        let r = clamp(rpm, ENGINE_RPMS[0], ENGINE_RPMS[n - 1] - 1.0);
        let mut lo = 0;
        while lo < n - 2 && r >= ENGINE_RPMS[lo + 1] {
            lo += 1;
        }
        let t = (r - ENGINE_RPMS[lo]) / (ENGINE_RPMS[lo + 1] - ENGINE_RPMS[lo]);
        let mut loudness = lerp(0.55, 1.0, clamp((rpm - 4000.0) / 9000.0, 0.0, 1.0));
        // Corte de ignição no limitador: o som "pipoca"
        let mut limiter = 1.0;
        if rpm > car.bind().max_rpm - 120.0 && self.engine_load > 0.5 {
            limiter = 0.5 + 0.5 * smoothstep(-0.4, 0.4, (self.time * TAU * 18.0).sin());
        }
        let on_gain = self.engine_load * limiter;
        let off_gain = (1.0 - self.engine_load) * 0.9;
        // Marcha lenta: giro irregular por carro e mais baixa (os rivais parados mais ainda)
        let idle = 1.0 - smoothstep(4200.0, 6000.0, rpm);
        let wobble = 1.0
            + idle
                * (self.idle_detune
                    + 0.015 * (self.time * TAU * 0.7 + self.idle_phase).sin()
                    + 0.008 * (self.time * TAU * 2.3).sin());
        loudness *= 1.0 - idle * if self.rival { 0.45 } else { 0.2 };
        let offset = self.engine_db + self._near_db + self.fade_db();
        for i in 0..n.min(self.on.len()).min(self.off.len()) {
            let w = if i == lo {
                (t * PI * 0.5).cos()
            } else if i == lo + 1 {
                (t * PI * 0.5).sin()
            } else {
                0.0
            };
            let pitch = rpm / ENGINE_RPMS[i] * wobble;
            set_loop(&mut self.on[i], &mut self.on_last[i], w * on_gain * loudness, pitch, offset);
            set_loop(&mut self.off[i], &mut self.off_last[i], w * off_gain * loudness, pitch, offset);
        }
    }

    fn update_effects(&mut self, car: &Gd<F1CarCore>, body: &Gd<VehicleBody3D>, rpm: f64, delta: f64) {
        if self.loops.len() <= BOOST {
            return;
        }
        let speed = body.get_linear_velocity().length() as f64;
        let kmh = speed * 3.6;
        let fx = self.effects_db + self._near_db + self.fade_db();
        let load = self.engine_load;
        // Turbo/MGU-H: assobio que sobe com o giro, com carga
        self.loop_at(TURBO, load * smoothstep(5000.0, 12000.0, rpm) * 0.32, 0.55 + 0.6 * rpm / 12000.0, fx);
        // Engrenagens retas: aparecem ao aliviar o acelerador em velocidade
        let whine = ((1.0 - load) * 0.3 + 0.05) * smoothstep(15.0, 120.0, kmh);
        self.loop_at(GEAR_WHINE, whine, 0.35 + kmh / 260.0, fx);
        // Vento
        self.loop_at(WIND, clamp(speed / 90.0, 0.0, 1.0).powf(2.0) * 0.45, 0.75 + kmh / 450.0, fx);

        // Pneus e pisos
        let mut squeal: f64 = 0.0;
        let mut scrub = 0.0;
        let (mut gravel, mut grass, mut kerb) = (0, 0, 0);
        let (wheels, boost_active) = {
            let c = car.bind();
            // Cópias no Rust do estado dos pneus (o carro de outro jogador online não roda o modelo)
            let states = &c.rs_state;
            let surfaces = &c.rs_surface;
            let usage = &c.rs_usage;
            for i in 0..states.len() {
                let state = states[i];
                if state == AIR {
                    continue;
                }
                let surf = surfaces.get(i).copied().unwrap_or(0);
                match surf {
                    surface::GRAVEL => gravel += 1,
                    surface::GRASS => grass += 1,
                    surface::KERB => kerb += 1,
                    _ => {}
                }
                if surf == surface::GRASS || surf == surface::GRAVEL {
                    continue; // piso solto não canta
                }
                if state == LOCK || state == SPIN {
                    scrub += 1.0;
                } else {
                    let u = usage.get(i).copied().unwrap_or(0.0) as f64;
                    squeal = squeal.max(clamp((u - 0.9) / 0.35, 0.0, 1.0));
                }
            }
            (states.len().max(1) as f64, c.boost_active)
        };
        let moving = clamp(speed / 8.0, 0.0, 1.0);
        self.loop_at(TIRE_SQUEAL, squeal * moving * 0.55, 0.9 + 0.25 * squeal + kmh / 1500.0, fx);
        self.loop_at(TIRE_SCRUB, clamp(scrub / 2.0, 0.0, 1.0) * moving * 0.6, 0.7 + kmh / 220.0, fx);
        let loose = clamp(speed / 15.0, 0.0, 1.0);
        self.loop_at(GRAVEL, gravel as f64 / wheels * loose * 0.8, 0.8 + kmh / 400.0, fx);
        self.loop_at(GRASS, grass as f64 / wheels * loose * 0.6, 0.8 + kmh / 400.0, fx);
        self.loop_at(SCRAPE, self.scrape_level * 0.9, 0.8 + kmh / 400.0, fx);
        self.boost_level = move_toward(self.boost_level, if boost_active { 1.0 } else { 0.0 }, delta * 5.0);
        self.loop_at(BOOST, self.boost_level * 0.55, 0.9 + kmh / 900.0, fx);
        self.loop_at(
            KERB,
            kerb as f64 / wheels * clamp(speed / 5.0, 0.0, 1.0) * 0.8,
            speed / self.kerb_reference_speed,
            fx,
        );
    }

    fn loop_at(&mut self, k: usize, level: f64, pitch: f64, offset_db: f64) {
        set_loop(&mut self.loops[k], &mut self.loops_last[k], level, pitch, offset_db);
    }

    /// Volume da transição de um rival que entra ou sai da lista dos que têm som (dB).
    fn fade_db(&self) -> f64 {
        if !self.rival || self.audible >= 1.0 {
            return 0.0;
        }
        linear_to_db(self.audible.max(0.001))
    }

    /// Ronco do escapamento ao aliviar em giro alto: um único "brap-brap" por alívio.
    fn update_backfire(&mut self, rpm: f64, pedal: f64, delta: f64) {
        if self.backfires && self.prev_throttle > 0.7 && pedal < 0.2 && rpm > 8500.0 && randf() < 0.75 {
            self.pops_left = 1;
            self.pop_timer = randf_range(0.03, 0.08);
        }
        self.prev_throttle = pedal;
        if self.pops_left > 0 {
            self.pop_timer -= delta;
            if self.pop_timer <= 0.0 {
                let variant = if rpm > 11000.0 { 3 } else { randi_range(1, 2) };
                let shot = GString::from(format!("backfire_{variant}").as_str());
                self.play_shot(shot, Vector3::new(0.0, 0.4, -2.6), randf_range(-6.0, -3.0), randf_range(0.95, 1.05));
                self.pops_left = 0;
            }
        }
    }

    /// Na câmera do piloto o som passa por um passa-baixa (capacete).
    fn update_helmet(&self, inside: bool) {
        let bus = self._bus_index as i32;
        // Uma conferência por bus e por quadro (os rivais dividem o mesmo bus)
        let frame = Engine::singleton().get_process_frames();
        let done = HELMET.with(|h| {
            let mut h = h.borrow_mut();
            if h.0 != frame {
                *h = (frame, Vec::new());
            }
            if h.1.contains(&bus) {
                true
            } else {
                h.1.push(bus);
                false
            }
        });
        if done {
            return;
        }
        let mut audio = AudioServer::singleton();
        if bus < 0 || audio.get_bus_effect_count(bus) <= HELMET_EFFECT {
            return;
        }
        if audio.is_bus_effect_enabled(bus, HELMET_EFFECT) != inside {
            audio.set_bus_effect_enabled(bus, HELMET_EFFECT, inside);
        }
    }
}
