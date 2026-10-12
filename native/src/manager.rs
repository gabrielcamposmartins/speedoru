//! Corrida a cada passo de física: base nativa do RaceEntry (os campos que mudam a cada passo) e
//! do RaceManager (scripts/race/race_manager.gd): posição de cada carro na pista, voltas, marcas
//! de progresso, boxes, limites de pista, contramão, carros-fantasma, posições, regra do DRS e
//! colisões punidas. O GDScript continua com as regras que só acontecem às vezes (cruzar a linha,
//! penalidades, avisos, pit stop do jogador), chamadas daqui.

use std::collections::HashMap;

use godot::builtin::AnyArray;
use godot::classes::{Node3D, RefCounted, Resource, VehicleBody3D};
use godot::prelude::*;

use crate::bot::BotDriverCore;
use crate::car::{F1CarCore, AIR};
use crate::path::PathCore;
use crate::surface;

/// Estados do RaceManager (RaceManager.State).
const PRACTICE: i64 = 1;
const RACING: i64 = 3;
const FINISHED: i64 = 4;
const QUALIFYING: i64 = 5;
const CHECKPOINT: f64 = 25.0;
const PIT_LIMIT: f64 = 80.0 / 3.6;
const GHOST_UNTIL: f64 = 950.0;
const DRS_GAP: f64 = 1.0;
/// BotDriver.Mode.RACE
const BOT_RACE: i64 = 0;

/// Estado de um piloto na corrida (base do RaceEntry): os campos lidos e escritos a cada passo.
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct RaceEntryCore {
    /// Posição na pista (atualizada a cada passo de física)
    #[var]
    pub s: f64,
    #[var]
    pub lateral: f64,
    #[var]
    pub race_time: f64,
    /// Vezes que cruzou a linha de chegada para frente (1 = começou a volta 1).
    #[var]
    pub crossings: i64,
    /// Progresso total em metros: (crossings - 1) · comprimento + s.
    #[var]
    pub progress: f64,
    #[var]
    pub position: i64,
    #[var]
    pub retired: bool,
    #[var]
    pub finished: bool,
    #[var]
    pub finished_and_parked: bool,
    #[var]
    pub finish_time: f64,
    /// Voltas completadas ao receber a bandeirada (o carro segue andando e cruzando a linha depois,
    /// mas isso não conta mais).
    #[var]
    pub finish_laps: i64,
    #[var]
    pub is_player: bool,
    #[var]
    pub is_human: bool,
    #[var]
    pub in_pit: bool,
    #[var]
    pub in_pit_stop: bool,
    #[var]
    pub pit_served: bool,
    #[var]
    pub pit_speeding_flagged: bool,
    #[var]
    pub pit_timer: f64,
    #[var]
    pub pit_count: i64,
    #[var]
    pub garage: i64,
    /// Limites de pista: tempo fora, distância percorrida fora e progresso ao sair
    #[var]
    pub off_time: f64,
    #[var]
    pub off_distance: f64,
    #[var]
    pub off_start_progress: f64,
    #[var]
    pub track_limit_warnings: i64,
    #[var]
    pub wrong_way_time: f64,
    /// Tempo de corrida em que passou por cada marca de progresso (para os intervalos).
    #[var]
    pub checkpoint_times: PackedFloat32Array,
    pub car: Option<Gd<F1CarCore>>,
    pub bot: Option<Gd<BotDriverCore>>,
    /// Carros logo à frente quando saiu da pista (para saber quem passou por fora).
    off_ahead: Vec<Gd<RaceEntryCore>>,
    base: Base<RefCounted>,
}

#[godot_api]
impl RaceEntryCore {
    /// O carro e o bot (o RaceEntry chama nos setters de car/bot).
    #[func]
    fn _core_car(&mut self, car: Option<Gd<F1CarCore>>) {
        self.car = car;
    }

    #[func]
    fn _core_bot(&mut self, bot: Option<Gd<BotDriverCore>>) {
        self.bot = bot;
    }
}

fn body(e: &Gd<RaceEntryCore>) -> Option<Gd<VehicleBody3D>> {
    e.bind().car.clone().filter(|c| c.is_instance_valid()).map(|c| c.upcast())
}

/// Dados da pista lidos uma vez (TrackLayout e RaceTrack).
#[derive(Default)]
struct TrackInfo {
    path_id: Option<InstanceId>,
    has_pit: bool,
    pit_side: i64,
    pit_entry_s: f64,
    pit_exit_s: f64,
    pit_taper: f64,
    pit_lane_width: f64,
    pit_width: Vec<f32>,
    pit_wall_strip: f64,
}

#[derive(GodotClass)]
#[class(init, base=Node)]
pub struct RaceManagerCore {
    #[var]
    _wrong_way_cooldown: f64,
    /// Colisões já punidas entre dois carros (par de ids → segundos até poder punir de novo).
    contact_cooldown: HashMap<(i64, i64), f64>,
    /// Pares de bots sem colisão entre si na largada (até a saída da 1ª chicane).
    ghost_pairs: Vec<(Gd<RaceEntryCore>, Gd<RaceEntryCore>)>,
    /// Pares de bots sem colisão entre si nos boxes (na ordem em que entraram).
    pit_ghosts: Vec<((i64, i64), Gd<RaceEntryCore>, Gd<RaceEntryCore>)>,
    track: TrackInfo,
    base: Base<Node>,
}

fn entries_of(v: &Variant) -> Vec<Gd<RaceEntryCore>> {
    v.try_to::<AnyArray>()
        .map(|a| a.iter_shared().filter_map(|e| e.try_to::<Gd<RaceEntryCore>>().ok()).collect())
        .unwrap_or_default()
}

#[godot_api]
impl RaceManagerCore {
    /// Pares de bots que se atravessam na largada.
    #[func]
    fn _add_ghost_pair(&mut self, a: Gd<RaceEntryCore>, b: Gd<RaceEntryCore>) {
        self.ghost_pairs.push((a, b));
    }

    #[func]
    fn _is_start_ghost(&self, a: Gd<RaceEntryCore>, b: Gd<RaceEntryCore>) -> bool {
        self.ghost_pairs.iter().any(|(x, y)| (*x == a && *y == b) || (*x == b && *y == a))
    }

    #[func]
    fn _in_pit_area(&self, e: Gd<RaceEntryCore>) -> bool {
        in_pit_area(&e)
    }

    /// A cada passo: posição de cada carro na pista, voltas, boxes, limites de pista e contramão.
    #[func]
    fn _native_update_entries(&mut self, delta: f64, racing: bool) {
        self._wrong_way_cooldown -= delta;
        self.contact_cooldown.retain(|_, t| {
            *t -= delta;
            *t > 0.0
        });
        let Some(path) = self.path() else { return };
        for e in self.entries() {
            self.update_entry(&path, &e, delta, racing);
        }
    }

    /// Fantasmas: os da largada saem quando os dois passaram da 1ª chicane e se afastaram; os dos
    /// boxes entram e saem pela distância.
    #[func]
    fn _native_update_ghosts(&mut self) {
        self.update_pit_ghosts();
        if self.ghost_pairs.is_empty() {
            return;
        }
        let pairs = std::mem::take(&mut self.ghost_pairs);
        for (a, b) in pairs {
            let done = |e: &Gd<RaceEntryCore>| {
                let e = e.bind();
                e.progress > GHOST_UNTIL || e.retired
            };
            let (ba, bb) = (body(&a), body(&b));
            let apart = match (&ba, &bb) {
                (Some(x), Some(y)) => x.get_global_position().distance_to(y.get_global_position()) > 6.0,
                _ => false,
            };
            if done(&a) && done(&b) && apart {
                let (mut x, y) = (ba.unwrap(), bb.unwrap());
                x.remove_collision_exception_with(&y.upcast::<Node>());
            } else {
                self.ghost_pairs.push((a, b));
            }
        }
    }

    /// Posições pela distância percorrida (abandonos no fim). Quem já recebeu a bandeirada conta
    /// pelas voltas que tinha ao cruzar a linha (logo antes de quem ainda corre com as mesmas voltas:
    /// esse está na volta seguinte); entre eles, quem chegou primeiro. Um carro que levou volta e
    /// recebeu a bandeirada não passa à frente de quem completou mais voltas e ainda não cruzou.
    #[func]
    fn _native_update_positions(&mut self) {
        let entries_var = self.base().get("entries");
        let entries = entries_of(&entries_var);
        let Some(path) = self.path() else { return };
        let length = path.bind().length;
        let key = |e: &Gd<RaceEntryCore>| {
            let e = e.bind();
            if e.retired {
                -1e9 + e.progress
            } else if e.finished {
                e.finish_laps as f64 * length - 1e-3 - e.finish_time * 1e-7
            } else {
                e.progress
            }
        };
        let mut sorted: Vec<(f64, Gd<RaceEntryCore>)> = entries.iter().map(|e| (key(e), e.clone())).collect();
        sorted.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
        let mut changed = false;
        for (k, (_, e)) in sorted.iter().enumerate() {
            e.clone().bind_mut().position = k as i64 + 1;
            changed |= entries[k] != *e;
        }
        if changed {
            let mut arr = VarArray::new();
            for (_, e) in &sorted {
                arr.push(&e.to_variant());
            }
            entries_var.call("assign", &[arr.to_variant()]);
        }
    }

    /// DRS por regra: a até DRS_GAP s do carro da frente (tempo nas marcas de progresso); o líder e
    /// quem está nos boxes não têm. Livre / treino: sempre permitido.
    #[func]
    fn _native_update_drs_rule(&mut self) {
        let state = self.state();
        let rule = self.base().get("drs_rule").try_to::<i64>().unwrap_or(0);
        let active = rule == 1 && state != PRACTICE && state != QUALIFYING;
        let entries = self.entries();
        for e in &entries {
            let allowed = !active || drs_gap_ok(&entries, e);
            let car = e.bind().car.clone();
            if let Some(mut car) = car {
                let mut c = car.bind_mut();
                c.drs_rule_active = active;
                c.drs_allowed = allowed;
            }
        }
    }

    /// Batida entre dois carros: pune quem está atrás e chegou mais rápido.
    #[func]
    fn _on_car_contact(&mut self, other: Gd<VehicleBody3D>, impulse: f64, e: Gd<RaceEntryCore>) {
        if self.state() != RACING {
            return;
        }
        let entries = self.entries();
        let Some(o) = entries.iter().find(|x| body(x).is_some_and(|c| c == other)).cloned() else { return };
        if o.bind().retired || e.bind().retired {
            return;
        }
        let (ia, ib) = (e.instance_id().to_i64(), o.instance_id().to_i64());
        let key = (ia.min(ib), ia.max(ib));
        if self.contact_cooldown.contains_key(&key) || impulse < 2600.0 {
            return;
        }
        self.contact_cooldown.insert(key, 4.0);
        // Culpado: quem está atrás e chegou mais rápido
        let (behind, front) = if e.bind().progress < o.bind().progress { (e, o) } else { (o, e) };
        let (Some(bb), Some(fb)) = (body(&behind), body(&front)) else { return };
        let dir = (fb.get_global_position() - bb.get_global_position()).normalized();
        let closing = (bb.get_linear_velocity().dot(dir) - fb.get_linear_velocity().dot(dir)) as f64;
        if closing > 2.5 && front.bind().progress - behind.bind().progress > 0.8 {
            let seconds = if impulse > 7000.0 { 10.0 } else { 5.0 };
            let code = front.get("code").to_string();
            self.call_gd("_penalize", &[behind.to_variant(), seconds.to_variant(), "COLISÃO".to_variant(),
                format!("Causou um acidente com {code}").to_variant()]);
        }
    }
}

fn in_pit_area(e: &Gd<RaceEntryCore>) -> bool {
    let e = e.bind();
    e.in_pit || e.in_pit_stop || e.bot.as_ref().is_some_and(|b| b.is_instance_valid() && b.bind().mode_value() != BOT_RACE)
}

fn drs_gap_ok(entries: &[Gd<RaceEntryCore>], e: &Gd<RaceEntryCore>) -> bool {
    let me = e.bind();
    if me.position <= 1 || me.in_pit || me.retired || me.position - 2 >= entries.len() as i64 {
        return false;
    }
    let ahead_gd = &entries[(me.position - 2) as usize];
    if ahead_gd == e {
        return false;
    }
    let ahead = ahead_gd.bind();
    if ahead.retired {
        return false;
    }
    let n = me.checkpoint_times.len().min(ahead.checkpoint_times.len());
    if n == 0 {
        return false;
    }
    let gap = (me.checkpoint_times.as_slice()[n - 1] - ahead.checkpoint_times.as_slice()[n - 1]) as f64;
    (0.0..=DRS_GAP).contains(&gap)
}

impl RaceManagerCore {
    fn state(&self) -> i64 {
        self.base().get("state").try_to::<i64>().unwrap_or(0)
    }

    fn entries(&self) -> Vec<Gd<RaceEntryCore>> {
        entries_of(&self.base().get("entries"))
    }

    /// Chama uma regra do RaceManager (GDScript); ela pode ler e chamar este objeto de volta.
    fn call_gd(&mut self, method: &str, args: &[Variant]) {
        self.base_mut().call(method, args);
    }

    /// A pista nativa (e, na primeira vez, os dados dos boxes).
    fn path(&mut self) -> Option<Gd<PathCore>> {
        let track = self.base().get("track").try_to::<Gd<Node3D>>().ok()?;
        let path = track.get("path").try_to::<Gd<RefCounted>>().ok()?.get("native").try_to::<Gd<PathCore>>().ok()?;
        if self.track.path_id != Some(path.instance_id()) {
            let mut info = TrackInfo { path_id: Some(path.instance_id()), ..Default::default() };
            if let Ok(lay) = track.get("layout").try_to::<Gd<Resource>>() {
                let f = |k: &str| lay.get(k).try_to::<f64>().unwrap_or(0.0);
                info.has_pit = lay.get("has_pit").try_to::<bool>().unwrap_or(false);
                info.pit_side = lay.get("pit_side").try_to::<i64>().unwrap_or(-1);
                info.pit_entry_s = f("pit_entry_s");
                info.pit_exit_s = f("pit_exit_s");
                info.pit_taper = f("pit_taper");
                info.pit_lane_width = f("pit_lane_width");
            }
            info.pit_width = track.get("pit_width").try_to::<PackedFloat32Array>().map(|a| a.to_vec()).unwrap_or_default();
            info.pit_wall_strip = track
                .get_script()
                .and_then(|s| s.try_cast::<godot::classes::Script>().ok())
                .and_then(|s| s.get_script_constant_map().get(&Variant::from("PIT_WALL_STRIP")))
                .and_then(|v| v.try_to::<f64>().ok())
                .unwrap_or(3.0);
            self.track = info;
        }
        Some(path)
    }

    fn update_entry(&mut self, path: &Gd<PathCore>, e: &Gd<RaceEntryCore>, delta: f64, racing: bool) {
        if e.bind().retired {
            return;
        }
        let Some(car) = body(e) else { return };
        let race_time = self.base().get("race_time").try_to::<f64>().unwrap_or(0.0);
        let (length, pr) = {
            let p = path.bind();
            (p.length, p.project_pos(car.get_global_position(), true, true))
        };
        let mut crossed = false;
        {
            let mut m = e.clone();
            let mut m = m.bind_mut();
            let prev_s = m.s;
            m.s = pr.x as f64;
            m.lateral = pr.y as f64;
            m.race_time = race_time;
            // Linha de chegada
            if prev_s > length * 0.75 && m.s < length * 0.25 {
                m.crossings += 1;
                crossed = racing;
            } else if prev_s < length * 0.25 && m.s > length * 0.75 {
                m.crossings -= 1;
            }
        }
        if crossed {
            self.call_gd("_on_line_crossed", &[e.to_variant()]);
        }
        {
            let mut m = e.clone();
            let mut m = m.bind_mut();
            m.progress = (m.crossings - 1) as f64 * length + m.s;
            if racing && !m.finished {
                let index = ((m.progress + length) / CHECKPOINT).floor() as i64;
                while (m.checkpoint_times.len() as i64) <= index {
                    m.checkpoint_times.push(race_time as f32);
                }
            }
        }
        if !racing {
            return;
        }
        self.update_pit(path, e, &car, delta);
        if self.state() != FINISHED || !e.bind().finished {
            self.update_track_limits(e, &car, delta);
        }
        if e.bind().is_player {
            self.update_wrong_way(path, e, &car, delta);
        }
    }

    fn box_marker(&self) -> Option<Gd<Node3D>> {
        self.base().get("_box_marker").try_to::<Gd<Node3D>>().ok()
    }

    fn update_pit(&mut self, path: &Gd<PathCore>, e: &Gd<RaceEntryCore>, car: &Gd<VehicleBody3D>, delta: f64) {
        // Pit stop do jogador em andamento (conta mesmo se a vaga ficar fora da detecção dos boxes)
        let (is_player, in_stop) = (e.bind().is_player, e.bind().in_pit_stop);
        if is_player && in_stop {
            let timer = {
                let mut m = e.clone();
                let mut m = m.bind_mut();
                m.pit_timer -= delta;
                m.pit_timer
            };
            self.base_mut().set("player_pit_timer", &timer.to_variant());
            if timer <= 0.0 {
                self.call_gd("_end_player_pit", &[e.to_variant()]);
            }
        }
        let t = &self.track;
        let (i, half) = {
            let p = path.bind();
            let s = e.bind().s;
            let i = p.index_at_s(s);
            (i, p.half_width_at(i, t.pit_side))
        };
        let width = t.pit_width.get(i).copied().unwrap_or(0.0) as f64;
        let beyond = e.bind().lateral * t.pit_side as f64 - half;
        let was_in = e.bind().in_pit;
        let now_in = t.has_pit && width > 2.0 && beyond > (2.2f64).min(width * 0.3);
        let (entry_line, exit_line, full_width) =
            (t.pit_entry_s + t.pit_taper, t.pit_exit_s - t.pit_taper, (t.pit_wall_strip + t.pit_lane_width) * 0.95);
        {
            let mut m = e.clone();
            let mut m = m.bind_mut();
            m.in_pit = now_in;
            if !now_in && was_in {
                m.pit_speeding_flagged = false;
                m.pit_served = false;
            }
        }
        if !now_in {
            if is_player {
                if let Some(mut marker) = self.box_marker() {
                    marker.set_visible(false);
                }
            }
            return;
        }
        // Limite de velocidade entre as linhas pintadas
        let (s, flagged) = (e.bind().s, e.bind().pit_speeding_flagged);
        let (after_entry, before_exit) = {
            let p = path.bind();
            (p.ahead(entry_line, s) < 0.0, p.ahead(exit_line, s) > 0.0)
        };
        let speed = car.get_linear_velocity().length() as f64;
        let full = width >= full_width;
        if after_entry && before_exit && full && speed > PIT_LIMIT + 0.8 && !flagged {
            e.clone().bind_mut().pit_speeding_flagged = true;
            let detail = format!("{} km/h no limite de 80 km/h", (speed * 3.6).round() as i64);
            self.call_gd("_penalize", &[e.to_variant(), 5.0.to_variant(), "VELOCIDADE NOS BOXES".to_variant(), detail.to_variant()]);
        }
        let (in_stop, served, garage) = (e.bind().in_pit_stop, e.bind().pit_served, e.bind().garage);
        // Pit stop do jogador: parar no box da equipe
        if is_player {
            if let Some(mut marker) = self.box_marker() {
                marker.set_visible(!in_stop);
            }
        }
        // Uma parada por passagem: parado na vaga depois do pit stop não começa outro
        if is_player && !in_stop && !served {
            let Ok(mut track) = self.base().get("track").try_to::<Gd<Node3D>>() else { return };
            let xf = track
                .call("get_pit_box_transform", &[garage.to_variant()])
                .try_to::<Transform3D>()
                .unwrap_or(Transform3D::IDENTITY);
            if car.get_global_position().distance_to(xf.origin) < 3.0 && speed < 1.5 {
                self.call_gd("_begin_player_pit", &[e.to_variant()]);
            }
        }
    }

    fn update_track_limits(&mut self, e: &Gd<RaceEntryCore>, car: &Gd<VehicleBody3D>, delta: f64) {
        let car_core = e.bind().car.clone().unwrap();
        if e.bind().in_pit || car_core.bind().hold {
            e.clone().bind_mut().off_time = 0.0;
            return;
        }
        if e.bind().off_time <= 0.0 {
            e.clone().bind_mut().off_ahead.clear();
        }
        let (mut on_track, mut in_contact) = (0, 0);
        {
            let c = car_core.bind();
            let states = c.tire_state.as_slice();
            for (k, &surf) in c.tire_surface.as_slice().iter().enumerate() {
                if states.get(k).copied().unwrap_or(AIR) == AIR {
                    continue;
                }
                in_contact += 1;
                if surf == surface::ASPHALT || surf == surface::KERB {
                    on_track += 1;
                }
            }
        }
        let speed = car.get_linear_velocity().length() as f64;
        if in_contact >= 2 && on_track == 0 {
            if e.bind().off_time <= 0.0 {
                let progress = e.bind().progress;
                // Quem estava logo à frente ao sair da pista (para saber quem ele passou por fora)
                let ahead: Vec<Gd<RaceEntryCore>> = self
                    .entries()
                    .into_iter()
                    .filter(|o| {
                        if o == e {
                            return false;
                        }
                        let o = o.bind();
                        !o.retired && o.progress > progress && o.progress - progress < 80.0
                    })
                    .collect();
                let mut m = e.clone();
                let mut m = m.bind_mut();
                m.off_start_progress = progress;
                m.off_distance = 0.0;
                m.off_ahead = ahead;
            }
            let mut m = e.clone();
            let mut m = m.bind_mut();
            m.off_time += delta;
            m.off_distance += speed * delta;
        } else if on_track >= 2 && e.bind().off_time > 0.0 {
            let (gained, off_time, progress, person, ahead) = {
                let m = e.bind();
                (
                    (m.progress - m.off_start_progress) - m.off_distance,
                    m.off_time,
                    m.progress,
                    m.is_player || m.is_human,
                    m.off_ahead.clone(),
                )
            };
            if off_time > 0.25 && speed > 5.0 {
                let mut passed = None;
                for o in &ahead {
                    let ob = o.bind();
                    if ob.progress < progress && !ob.in_pit && !ob.retired {
                        passed = Some(o.clone());
                    }
                }
                if let (Some(p), true) = (&passed, person && self.state() == RACING) {
                    // Passou alguém por fora da pista: dá para devolver a posição antes da penalidade
                    let detail = format!("Passou {} por fora da pista", p.get("code"));
                    self.call_gd("request_give_back", &[e.to_variant(), p.to_variant(), 5.0.to_variant(),
                        "VANTAGEM INDEVIDA".to_variant(), detail.to_variant()]);
                } else if gained > 10.0 {
                    let detail = format!("Cortou a pista e ganhou {gained:.0} m");
                    self.call_gd("_penalize", &[e.to_variant(), 5.0.to_variant(), "VANTAGEM INDEVIDA".to_variant(), detail.to_variant()]);
                } else {
                    let warnings = {
                        let mut m = e.clone();
                        let mut m = m.bind_mut();
                        m.track_limit_warnings += 1;
                        m.track_limit_warnings
                    };
                    if warnings > 3 {
                        let detail = format!("Infração {warnings} — penalidade");
                        self.call_gd("_penalize", &[e.to_variant(), 5.0.to_variant(), "LIMITES DE PISTA".to_variant(), detail.to_variant()]);
                    } else {
                        let detail = format!("Aviso {warnings}/3");
                        self.call_gd("_notify", &[e.to_variant(), "LIMITES DE PISTA".to_variant(), detail.to_variant(), false.to_variant()]);
                    }
                }
            }
            e.clone().bind_mut().off_time = 0.0;
        }
    }

    fn update_wrong_way(&mut self, path: &Gd<PathCore>, e: &Gd<RaceEntryCore>, car: &Gd<VehicleBody3D>, delta: f64) {
        let tangent = path.bind().tangent(e.bind().s);
        let v = car.get_linear_velocity();
        if v.length() > 5.0 && v.normalized().dot(tangent) < -0.4 && !e.bind().in_pit {
            let t = {
                let mut m = e.clone();
                let mut m = m.bind_mut();
                m.wrong_way_time += delta;
                m.wrong_way_time
            };
            if t > 1.5 && self._wrong_way_cooldown <= 0.0 {
                self._wrong_way_cooldown = 5.0;
                self.call_gd("_notify", &[e.to_variant(), "CONTRAMÃO".to_variant(),
                    "Vire o carro no sentido da pista".to_variant(), false.to_variant()]);
            }
        } else {
            e.clone().bind_mut().wrong_way_time = 0.0;
        }
    }

    /// Pista dos boxes: bots não colidem entre si enquanto um deles está nos boxes (seguem fazendo
    /// fila e liberação segura); o jogador colide com todos normalmente.
    fn update_pit_ghosts(&mut self) {
        // Saem os pares que já deixaram os boxes e se afastaram
        let pairs = std::mem::take(&mut self.pit_ghosts);
        for (key, a, b) in pairs {
            let (ba, bb) = (body(&a), body(&b));
            let (Some(mut x), Some(y)) = (ba, bb) else {
                self.pit_ghosts.push((key, a, b));
                continue;
            };
            if in_pit_area(&a) || in_pit_area(&b) || x.get_global_position().distance_to(y.get_global_position()) <= 8.0 {
                self.pit_ghosts.push((key, a, b));
                continue;
            }
            if !self._is_start_ghost(a.clone(), b.clone()) {
                x.remove_collision_exception_with(&y.upcast::<Node>());
            }
        }
        // Entram os pares de bots com um deles nos boxes, a menos de 40 m
        let bots: Vec<(Gd<RaceEntryCore>, Gd<VehicleBody3D>, bool)> = self
            .entries()
            .into_iter()
            .filter(|e| {
                let m = e.bind();
                !m.is_player && !m.is_human
            })
            .filter_map(|e| {
                let b = body(&e)?;
                let pit = in_pit_area(&e);
                Some((e, b, pit))
            })
            .collect();
        for i in 0..bots.len() {
            for j in i + 1..bots.len() {
                let (a, ba, pa) = &bots[i];
                let (b, bb, pb) = &bots[j];
                if !(*pa || *pb) {
                    continue;
                }
                if ba.get_global_position().distance_squared_to(bb.get_global_position()) >= 1600.0 {
                    continue;
                }
                // Chave na mesma ordem sempre (a lista de entradas é reordenada pela posição)
                let (ia, ib) = (a.instance_id().to_i64(), b.instance_id().to_i64());
                let key = (ia.min(ib), ia.max(ib));
                if !self.pit_ghosts.iter().any(|(k, _, _)| *k == key) {
                    let mut x = ba.clone();
                    x.add_collision_exception_with(&bb.clone().upcast::<Node>());
                    self.pit_ghosts.push((key, a.clone(), b.clone()));
                }
            }
        }
    }
}
