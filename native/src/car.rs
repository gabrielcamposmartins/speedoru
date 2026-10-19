//! Física do carro (base nativa do F1Car, scripts/car/f1_car.gd): modelo de pneu, motor, câmbio,
//! freios, aerodinâmica, direção, DRS, bateria e a marionete da rede. O GDScript continua com a
//! montagem das peças, os efeitos que se criam uma vez e o conserto; o comentário do topo do
//! f1_car.gd descreve o modelo.

use std::f64::consts::{PI, TAU};

use godot::classes::{
    Engine, GpuParticles3D, Gradient, GradientTexture1D, IVehicleBody3D, Input, Node3D, ParticleProcessMaterial,
    PhysicsDirectBodyState3D, Resource, VehicleBody3D, VehicleWheel3D,
};
use godot::prelude::*;

use crate::damage::CarDamageCore;
use crate::surface;
use crate::util::{clamp, fposmod, lerp, move_toward, signf};

pub const AIR: i32 = 0;
pub const GRIP: i32 = 1;
pub const SLIDE: i32 = 2;
pub const SPIN: i32 = 3;
pub const LOCK: i32 = 4;

const NEUTRAL: i64 = 0;
const UNDERSTEER: i64 = 1;
const OVERSTEER: i64 = 2;

const AIR_DENSITY: f64 = 1.225;
const GEAR_REVERSE: i64 = -1;
const GEAR_NEUTRAL: i64 = 0;
const LOW_SPEED_SLIP: f64 = 3.0;
const LIMITER_KMH: f64 = 80.0;
const COMPOUND_WEAR: [f64; 5] = [1.55, 1.0, 0.68, 1.2, 1.4];
/// A cada quantos passos as constantes das rodas são relidas mesmo sem aviso.
const WHEEL_REFRESH: i64 = 60;
/// Contato com outro carro abaixo disso (N·s) não interessa às penalidades (RaceManagerCore).
const CONTACT_SIGNAL_MIN: f64 = 2600.0;
/// Fumaça e pó das rodas só perto da câmera (m).
const FX_RANGE: f32 = 150.0;
const SIGNAL_BLINKS: f64 = 4.0;

/// Os 4 primeiros valores de um array exportado (o resto com `fill`), numa leitura só.
fn read4<T: godot::meta::PackedElement + Copy>(
    arr: &godot::builtin::PackedArray<T>,
    fill: T,
) -> [T; 4] {
    let mut out = [fill; 4];
    for (o, v) in out.iter_mut().zip(arr.as_slice().iter()) {
        *o = *v;
    }
    out
}

/// Escreve os `n` primeiros valores num array exportado de uma vez.
fn write4<T: godot::meta::PackedElement + Copy>(
    arr: &mut godot::builtin::PackedArray<T>,
    values: &[T; 4],
    n: usize,
) {
    let slice = arr.as_mut_slice();
    let m = n.min(slice.len());
    slice[..m].copy_from_slice(&values[..m]);
}
const SIGNAL_PERIOD: f64 = 0.5;

/// Nomes das ações do jogador (criados uma vez).
struct Actions {
    accelerate: StringName,
    brake: StringName,
    reverse: StringName,
    boost: StringName,
    steer_right: StringName,
    steer_left: StringName,
    drs: StringName,
    shift_up: StringName,
    shift_down: StringName,
    toggle_gearbox: StringName,
    pit_limiter: StringName,
    toggle_tc: StringName,
    bias_forward: StringName,
    bias_rearward: StringName,
    reset_car: StringName,
    repair_car: StringName,
    pass_signal: StringName,
}

impl Actions {
    fn new() -> Self {
        Self {
            accelerate: "accelerate".into(),
            brake: "brake".into(),
            reverse: "reverse".into(),
            boost: "boost".into(),
            steer_right: "steer_right".into(),
            steer_left: "steer_left".into(),
            drs: "drs".into(),
            shift_up: "shift_up".into(),
            shift_down: "shift_down".into(),
            toggle_gearbox: "toggle_gearbox".into(),
            pit_limiter: "pit_limiter".into(),
            toggle_tc: "toggle_tc".into(),
            bias_forward: "brake_bias_forward".into(),
            bias_rearward: "brake_bias_rearward".into(),
            reset_car: "reset_car".into(),
            repair_car: "repair_car".into(),
            pass_signal: "pass_signal".into(),
        }
    }
}

#[derive(GodotClass)]
#[class(init, tool, base=VehicleBody3D)]
pub struct F1CarCore {
    /// Lê as entradas do jogador (InputMap). Desligue para IA/replays.
    #[export]
    #[init(val = true)]
    pub player_controlled: bool,

    #[export_group(name = "Motor e câmbio")]
    #[export]
    #[init(val = 760.0)]
    pub max_power_kw: f64,
    #[export]
    #[init(val = 620.0)]
    pub peak_torque_nm: f64,
    #[export]
    #[init(val = 4000.0)]
    pub idle_rpm: f64,
    #[export]
    #[init(val = 9500.0)]
    pub launch_rpm: f64,
    #[export]
    #[init(val = 12500.0)]
    pub max_rpm: f64,
    /// Relação total (câmbio × diferencial) de cada marcha, da 1ª à 8ª.
    #[export]
    #[init(val = PackedFloat32Array::from(&[15.5, 12.4, 10.3, 8.8, 7.6, 6.6, 5.7, 4.85][..]))]
    pub gear_ratios: PackedFloat32Array,
    #[export]
    #[init(val = 14.0)]
    pub reverse_ratio: f64,
    #[export]
    #[init(val = 30.0)]
    pub max_reverse_kmh: f64,
    #[export]
    #[init(val = true)]
    pub automatic: bool,
    #[export]
    #[init(val = 11900.0)]
    pub upshift_rpm: f64,
    #[export]
    #[init(val = 7600.0)]
    pub downshift_rpm: f64,
    #[export]
    #[init(val = 0.06)]
    pub shift_time: f64,
    #[export]
    #[init(val = 2400.0)]
    pub engine_braking_force: f64,

    #[export_group(name = "Assistências")]
    /// Limita a força de tração ao que o pneu traseiro aguenta (sem patinar).
    #[export]
    #[init(val = true)]
    pub traction_control: bool,
    /// Limita a força de frenagem ao que cada pneu aguenta (sem travar). F1 real não tem ABS.
    #[export]
    #[init(val = true)]
    pub brake_assist: bool,
    /// Fração da aderência máxima usada pelas assistências.
    #[export(range = (0.5, 1.0))]
    #[init(val = 0.96)]
    pub assist_threshold: f64,

    #[export_group(name = "Pneus")]
    #[export]
    #[init(val = 1.75)]
    pub front_grip: f64,
    #[export]
    #[init(val = 1.8)]
    pub rear_grip: f64,
    #[export]
    #[init(val = 6.0)]
    pub peak_slip_angle_deg: f64,
    #[export(range = (1.05, 1.9))]
    #[init(val = 1.4)]
    pub tire_shape: f64,
    #[export(range = (0.0, 0.4))]
    #[init(val = 0.12)]
    pub load_sensitivity: f64,
    #[export]
    #[init(val = 3000.0)]
    pub nominal_load: f64,
    #[export(range = (0.3, 1.0))]
    #[init(val = 0.8)]
    pub sliding_grip: f64,
    #[export(range = (0.0, 1.0))]
    #[init(val = 0.15)]
    pub locked_lateral_grip: f64,
    #[export]
    #[init(val = 0.3)]
    pub relaxation_length: f64,

    #[export_group(name = "Freios e direção")]
    #[export]
    #[init(val = 14000.0)]
    pub brake_force_per_wheel: f64,
    #[export(range = (0.3, 0.8))]
    #[init(val = 0.57)]
    pub brake_bias_front: f64,
    #[export]
    #[init(val = 0.36)]
    pub max_steer_angle: f64,
    #[export]
    #[init(val = 0.12)]
    pub high_speed_steer_angle: f64,
    #[export]
    #[init(val = 60.0)]
    pub steer_speed_reference: f64,
    #[export]
    #[init(val = 2.4)]
    pub steer_rate: f64,
    #[export]
    #[init(val = 3.2)]
    pub steering_wheel_ratio: f64,

    #[export_group(name = "Desgaste dos pneus")]
    #[export(range = (0.0, 5.0))]
    #[init(val = 1.0)]
    pub tyre_wear_rate: f64,
    #[export(range = (0.0, 0.8))]
    #[init(val = 0.32)]
    pub worn_grip_loss: f64,

    #[export_group(name = "Bateria e boost")]
    #[export]
    #[init(val = 0.16)]
    pub battery_regen_rate: f64,
    #[export]
    #[init(val = 0.22)]
    pub boost_drain_rate: f64,
    #[export]
    #[init(val = 4200.0)]
    pub boost_force: f64,
    #[export(range = (0.0, 0.5))]
    #[init(val = 0.06)]
    pub boost_min_start: f64,

    #[export_group(name = "Aerodinâmica")]
    #[export]
    #[init(val = 4.2)]
    pub downforce_area: f64,
    #[export]
    #[init(val = 1.4)]
    pub drag_area: f64,
    #[export(range = (0.2, 0.7))]
    #[init(val = 0.42)]
    pub aero_balance: f64,
    #[export]
    #[init(val = 0.012)]
    pub rolling_resistance: f64,
    #[export(range = (0.0, 1.0))]
    #[init(val = 0.22)]
    pub drs_drag_reduction: f64,
    #[export(range = (0.0, 1.0))]
    #[init(val = 0.12)]
    pub drs_downforce_reduction: f64,
    #[export]
    #[init(val = 80.0)]
    pub drs_min_speed_kmh: f64,
    #[export]
    #[init(val = 28.0)]
    pub drs_flap_angle_deg: f64,

    // Entradas (0..1, direção -1..1 com + = esquerda)
    #[var]
    pub throttle_input: f64,
    #[var]
    pub brake_input: f64,
    #[var]
    pub reverse_input: f64,
    #[var]
    pub boost_input: bool,
    #[var]
    pub limiter_on: bool,
    #[var]
    #[init(val = 0.35)]
    pub battery: f64,
    #[var]
    pub boost_active: bool,
    #[var]
    pub steer_input: f64,
    #[var]
    pub drs_requested: bool,

    // Estado (somente leitura para HUD/câmeras/telemetria)
    #[var]
    #[init(val = 1)]
    pub gear: i64,
    #[var]
    #[init(val = 4000.0)]
    pub rpm: f64,
    #[var]
    pub forward_speed: f64,
    #[var]
    pub speed_kmh: f64,
    #[var]
    pub drs_open: bool,
    #[var]
    pub tc_active: bool,
    #[var]
    pub abs_active: bool,
    #[var]
    pub effective_downforce_area: f64,
    #[var]
    pub effective_drag_area: f64,
    #[var]
    pub slipstream: f64,
    #[var]
    #[init(val = 0.42)]
    pub effective_balance: f64,
    #[var]
    pub body_slip_angle: f64,
    #[var]
    pub handling: i64,
    #[var]
    #[init(val = PackedFloat32Array::from(&[0.0; 4][..]))]
    pub tire_load: PackedFloat32Array,
    #[var]
    #[init(val = PackedFloat32Array::from(&[0.0; 4][..]))]
    pub tire_usage: PackedFloat32Array,
    #[var]
    #[init(val = PackedFloat32Array::from(&[0.0; 4][..]))]
    pub tire_slip_deg: PackedFloat32Array,
    /// F1Car.TireState de cada roda.
    #[var]
    #[init(val = PackedInt32Array::from(&[AIR; 4][..]))]
    pub tire_state: PackedInt32Array,
    #[var]
    #[init(val = PackedInt32Array::from(&[0; 4][..]))]
    pub tire_surface: PackedInt32Array,
    #[var]
    #[init(val = PackedFloat32Array::from(&[0.0; 4][..]))]
    pub tire_wear: PackedFloat32Array,
    #[var]
    pub hold: bool,
    #[var]
    #[init(val = true)]
    pub drs_allowed: bool,
    #[var]
    pub drs_rule_active: bool,
    /// Rede (cliente): marionete (o F1Car.set_puppet troca o corpo; o setter tem outro nome para não
    /// cobrir aquele método).
    #[var(set = _set_puppet_flag)]
    pub puppet: bool,
    #[var]
    pub net_predicted: bool,
    #[var]
    #[init(val = PackedFloat32Array::from(&[0.04; 4][..]))]
    pub puppet_wheel_drop: PackedFloat32Array,
    #[var]
    #[init(val = true)]
    pub allow_quick_repair: bool,
    #[var]
    #[init(val = 1.0)]
    pub damage_front_downforce: f64,
    #[var]
    #[init(val = 1.0)]
    pub damage_rear_downforce: f64,
    #[var]
    pub damage_drag: f64,
    #[var]
    #[init(val = 1.0)]
    pub damage_power: f64,
    #[var]
    #[init(val = PackedFloat32Array::from(&[1.0; 4][..]))]
    pub wheel_grip: PackedFloat32Array,
    #[var]
    #[init(val = PackedFloat32Array::from(&[0.0; 4][..]))]
    pub wheel_toe: PackedFloat32Array,
    /// Roda arrancada (bool por roda).
    #[var]
    #[init(val = { let mut a = VarArray::new(); for _ in 0..4 { a.push(&false.to_variant()); } a })]
    pub wheel_broken: VarArray,
    #[var]
    #[init(val = -100)]
    pub reset_frame: i64,
    #[var]
    pub signal_time: f64,
    #[var]
    pub signal_on: bool,

    /// Pontos de fixação das rodas (posição local de cada uma no começo).
    #[var]
    pub _mounts: PackedVector3Array,
    #[var]
    #[init(val = PackedFloat32Array::from(&[0.0; 4][..]))]
    pub _puppet_spin: PackedFloat32Array,
    #[var]
    pub _downforce: f64,
    #[var]
    pub _vertical_accel: f64,

    wheels: Vec<Gd<VehicleWheel3D>>,
    steers: Vec<bool>,
    traction: Vec<bool>,
    alpha: [f64; 4],
    max_force: [f64; 4],
    lat_usage: [f64; 4],
    drive_request: [f64; 4],
    brake_request: [f64; 4],
    prev_up_speed: f64,
    smoke: Vec<Gd<GpuParticles3D>>,
    dust: Vec<Gd<GpuParticles3D>>,
    shift_timer: f64,
    reverse_timer: f64,
    drs_amount: f64,
    reset_pending: bool,
    drs_flap: Option<Gd<Node3D>>,
    drs_flap_rest: Transform3D,
    steering_wheel: Option<Gd<Node3D>>,
    steering_wheel_rest: Transform3D,
    damage: Option<Gd<CarDamageCore>>,
    config: Option<Gd<Resource>>,
    /// Aderência e desgaste do composto, lidos do CarConfig só quando ele muda (antes: uma chamada
    /// ao GDScript por carro a cada passo de física).
    compound_cache: Option<(f64, f64)>,
    /// Estado do corpo lido uma vez por passo (transform, velocidades) e o volante de agora: antes cada
    /// parte do passo pedia de novo ao motor (velocidade 4×, transform 4×, volante 3×).
    st_gt: Transform3D,
    st_lv: Vector3,
    st_av: Vector3,
    st_steer: f64,
    /// Constantes das rodas [raio, repouso, curso, rigidez], massa, centro de massa (local) e relações
    /// de marcha: relidas quando o CarConfig ou o dano mudam as rodas (_core_wheels_changed) e a cada
    /// WHEEL_REFRESH passos.
    wheel_consts: [[f64; 4]; 4],
    wheel_consts_ok: bool,
    wheel_consts_age: i64,
    st_mass: f64,
    st_com: Vector3,
    ratios: Vec<f32>,
    /// Forças do passo somadas (pneus + aerodinâmica): aplicadas de uma vez como força resultante e
    /// torque em torno do centro de massa — o mesmo que o motor faz em cada apply_force.
    acc_force: Vector3,
    acc_torque: Vector3,
    /// Piso de cada roda: o último corpo tocado e o piso dele (o metadado só é lido quando muda).
    surf_cache: [(Option<InstanceId>, i32); 4],
    /// Cópias no Rust do estado dos pneus (os arrays exportados custam 3 chamadas ao motor por leitura).
    pub(crate) rs_state: [i32; 4],
    pub(crate) rs_slip: [f32; 4],
    pub(crate) rs_surface: [i32; 4],
    pub(crate) rs_usage: [f32; 4],
    /// O que já está aplicado nas peças animadas [aba do DRS, volante] e nas partículas (bits).
    parts_applied: Option<(f64, f64)>,
    fx_mask: Option<u32>,
    /// Carro que dá o vácuo, como já escrito em slipstream_source (o RaceNative só escreve quando muda).
    pub(crate) slip_src: Option<InstanceId>,
    editor: Option<bool>,
    leds_shown: bool,
    #[init(val = Actions::new())]
    actions: Actions,
    base: Base<VehicleBody3D>,
}

#[godot_api]
impl IVehicleBody3D for F1CarCore {
    fn physics_process(&mut self, delta: f64) {
        if *self.editor.get_or_insert_with(|| Engine::singleton().is_editor_hint()) {
            return;
        }
        self.update_signal(delta);
        let gt = self.base().get_global_transform();
        let lv = self.base().get_linear_velocity();
        let bz = gt.basis.col_c();
        if self.puppet {
            self.forward_speed = lv.dot(bz) as f64;
            self.speed_kmh = self.forward_speed.abs() * 3.6;
            let target = if self.drs_open { 1.0 } else { 0.0 };
            self.drs_amount = move_toward(self.drs_amount, target, delta * 5.0);
            self.animate_puppet_wheels(delta);
            let steering = self.base().get_steering() as f64;
            self.animate_parts(steering);
            return;
        }
        self.st_gt = gt;
        self.st_lv = lv;
        self.st_av = self.base().get_angular_velocity();
        self.st_steer = self.base().get_steering() as f64;
        if !self.wheel_consts_ok || self.wheel_consts_age >= WHEEL_REFRESH {
            self.refresh_wheel_consts();
        }
        self.wheel_consts_age += 1;
        self.acc_force = Vector3::ZERO;
        self.acc_torque = Vector3::ZERO;
        if self.player_controlled {
            self.read_player_input();
        }
        self.forward_speed = lv.dot(bz) as f64;
        self.speed_kmh = self.forward_speed.abs() * 3.6;
        self.update_gearbox(delta);
        self.update_drive_and_brakes(delta);
        self.update_steering(delta);
        self.update_drs(delta);
        self.apply_aero();
        self.update_tires(delta);
        let (force, torque) = (self.acc_force, self.acc_torque);
        let mut b = self.base_mut();
        b.apply_central_force(force);
        b.apply_torque(torque);
        drop(b);
        self.update_handling();
        self.animate_parts(self.st_steer);
    }

    fn integrate_forces(&mut self, state: Option<Gd<PhysicsDirectBodyState3D>>) {
        let Some(mut state) = state else { return };
        // Contatos do corpo (batidas, raspadas) para o sistema de dano
        let count = state.get_contact_count();
        if count > 0 && !self.net_predicted {
            if let Some(mut damage) = self.damage.clone().filter(|d| d.is_instance_valid()) {
                let mass = self.base().get_mass() as f64;
                // Só o contato mais forte com cada carro, e só acima do que as penalidades consideram
                // (antes: um sinal por ponto de contato a cada passo, até 8, enquanto dois carros raspam)
                let mut strongest: Vec<(Gd<F1CarCore>, f64)> = Vec::new();
                let mut d = damage.bind_mut();
                for i in 0..count {
                    let pos = state.get_contact_local_position(i);
                    let rel = state.get_contact_local_velocity_at_position(i)
                        - state.get_contact_collider_velocity_at_position(i);
                    let normal = state.get_contact_local_normal(i);
                    let slide = (rel - normal * rel.dot(normal)).length();
                    let collider = state.get_contact_collider_object(i);
                    let impulse = state.get_contact_impulse(i);
                    d.add_contact(pos, impulse, normal, collider.clone(), slide as f64);
                    if let Some(other) = collider.and_then(|c| c.try_cast::<F1CarCore>().ok()) {
                        let closing = rel.dot(normal).abs() as f64;
                        let strength = (impulse.length() as f64).max(closing * mass * 0.5);
                        match strongest.iter_mut().find(|(o, _)| *o == other) {
                            Some(e) => e.1 = e.1.max(strength),
                            None => strongest.push((other, strength)),
                        }
                    }
                }
                drop(d);
                for (other, strength) in strongest {
                    if strength >= CONTACT_SIGNAL_MIN {
                        self.base_mut().emit_signal("car_contact", &[other.to_variant(), strength.to_variant()]);
                    }
                }
            }
        }
        if !self.reset_pending {
            return;
        }
        self.reset_pending = false;
        let forward = self.base().get_global_basis().col_c();
        let yaw = forward.x.atan2(forward.z);
        let origin = state.get_transform().origin;
        state.set_transform(Transform3D::new(Basis::from_axis_angle(Vector3::UP, yaw), origin + Vector3::UP * 0.6));
        state.set_linear_velocity(Vector3::ZERO);
        state.set_angular_velocity(Vector3::ZERO);
        self.reset_frame = Engine::singleton().get_physics_frames() as i64;
        self.alpha = [0.0; 4];
        self.change_gear(1);
        self.base_mut().reset_physics_interpolation();
    }
}

#[godot_api]
impl F1CarCore {
    #[signal]
    fn gear_changed(gear: i64);
    #[signal]
    fn drs_changed(open: bool);
    /// Encostou em outro carro (impulso estimado em N·s), para penalidades de colisão.
    #[signal]
    fn car_contact(other: Gd<VehicleBody3D>, impulse: f64);

    /// Chamado no começo do _ready do F1Car: acha as rodas e desliga o atrito do Godot (o modelo de
    /// pneu aplica as forças).
    #[func]
    fn _core_ready(&mut self) {
        // Sem a detecção contínua de colisão (CCD): ver o comentário em f1_car.gd
        self.base_mut().set_use_continuous_collision_detection(false);
        self.wheels.clear();
        self.steers.clear();
        self.traction.clear();
        let mut mounts = PackedVector3Array::new();
        let children = self.base().get_children();
        for child in children.iter_shared() {
            if let Ok(mut wheel) = child.try_cast::<VehicleWheel3D>() {
                mounts.push(wheel.get_position());
                wheel.set_friction_slip(0.0);
                wheel.set_engine_force(0.0);
                wheel.set_brake(0.0);
                self.steers.push(wheel.is_used_as_steering());
                self.traction.push(wheel.is_used_as_traction());
                self.wheels.push(wheel);
            }
        }
        self._mounts = mounts;
        self.damage = self.base().get_node_or_null("Damage").and_then(|d| d.try_cast::<CarDamageCore>().ok());
    }

    /// Partículas de fumaça e poeira de cada roda (criadas pelo GDScript).
    #[func]
    fn _core_set_fx(&mut self, smoke: Array<Gd<GpuParticles3D>>, dust: Array<Gd<GpuParticles3D>>) {
        self.smoke = smoke.iter_shared().collect();
        self.dust = dust.iter_shared().collect();
    }

    /// Peças animadas (aba do DRS e volante) e a pose de repouso delas.
    #[func]
    fn _core_set_parts(
        &mut self,
        flap: Option<Gd<Node3D>>,
        flap_rest: Transform3D,
        wheel: Option<Gd<Node3D>>,
        wheel_rest: Transform3D,
    ) {
        self.drs_flap = flap;
        self.drs_flap_rest = flap_rest;
        self.steering_wheel = wheel;
        self.steering_wheel_rest = wheel_rest;
    }

    #[func]
    fn _set_puppet_flag(&mut self, on: bool) {
        self.puppet = on;
    }

    #[func]
    fn _core_set_config(&mut self, config: Option<Gd<Resource>>) {
        self.config = config;
        self.compound_cache = None;
    }

    /// O CarConfig mudou (composto, peças…): relê o composto e as rodas no próximo passo.
    #[func]
    fn _core_config_changed(&mut self) {
        self.compound_cache = None;
        self.wheel_consts_ok = false;
    }

    /// Raio ou suspensão de alguma roda mudou (roda quebrada, reparo): relê no próximo passo.
    #[func]
    fn _core_wheels_changed(&mut self) {
        self.wheel_consts_ok = false;
    }

    /// Zera os efeitos do dano (o F1Car.repair remonta as peças).
    #[func]
    fn _reset_damage(&mut self) {
        self.damage_front_downforce = 1.0;
        self.damage_rear_downforce = 1.0;
        self.damage_drag = 0.0;
        self.damage_power = 1.0;
        self.wheel_grip.fill(1.0);
        self.wheel_toe.fill(0.0);
        let mut broken = VarArray::new();
        for _ in 0..4 {
            broken.push(&false.to_variant());
        }
        self.wheel_broken = broken;
    }

    /// Câmbio manual: R ↔ N ↔ 1 ↔ 2 … (a ré só engata com o carro quase parado). No automático a
    /// redução da 1ª vai direto para a ré e não há neutro.
    #[func]
    pub fn shift_up(&mut self) {
        if self.gear == GEAR_REVERSE {
            self.change_gear(if self.automatic { 1 } else { GEAR_NEUTRAL });
        } else if self.gear == GEAR_NEUTRAL {
            self.change_gear(1);
        } else if self.gear < self.gear_ratios.len() as i64 {
            self.change_gear(self.gear + 1);
        }
    }

    #[func]
    pub fn shift_down(&mut self) {
        if self.gear > 1 {
            self.change_gear(self.gear - 1);
        } else if self.gear == 1 {
            if !self.automatic {
                self.change_gear(GEAR_NEUTRAL);
            } else if self.forward_speed < 1.0 {
                self.change_gear(GEAR_REVERSE);
            }
        } else if self.gear == GEAR_NEUTRAL && self.forward_speed < 1.0 {
            self.change_gear(GEAR_REVERSE);
        }
    }

    /// Ajuste de balanço de freio (botões do volante): + = mais freio na dianteira.
    #[func]
    fn adjust_brake_bias(&mut self, delta_bias: f64) {
        let snapped = ((self.brake_bias_front + delta_bias) / 0.005 + 0.5).floor() * 0.005;
        self.brake_bias_front = clamp(snapped, 0.45, 0.70);
    }

    /// Recoloca o carro em pé, alguns centímetros acima do ponto atual, mantendo a direção.
    #[func]
    fn reset_car(&mut self) {
        self.reset_pending = true;
    }

    /// Pneus novos (pit stop); muda o composto se `compound` >= 0.
    #[func]
    pub fn change_tyres(&mut self, #[opt(default = -1)] compound: i64) {
        self.tire_wear.fill(0.0);
        if compound >= 0 {
            if let Some(mut cfg) = self.config.clone() {
                // O CarConfig avisa (changed) e o F1Car remonta e recalcula: chamada reentrante
                let _guard = self.base_mut();
                cfg.set("tyre_compound", &compound.to_variant());
            }
        }
    }

    /// Embreagem aberta durante a troca de marcha (sem torque).
    #[func]
    pub fn is_shifting(&self) -> bool {
        self.shift_timer > 0.0
    }

    #[func]
    pub fn get_wheels(&self) -> Array<Gd<VehicleWheel3D>> {
        self.wheels.iter().cloned().collect()
    }

    #[func]
    fn is_front_wheel(&self, index: i64) -> bool {
        self.steers.get(index as usize).copied().unwrap_or(false)
    }

    /// Pedir passagem: pisca a luz dos retrovisores.
    #[func]
    fn pass_signal(&mut self) {
        self.signal_time = SIGNAL_BLINKS * SIGNAL_PERIOD;
    }
}

impl F1CarCore {
    fn change_gear(&mut self, new_gear: i64) {
        if new_gear == self.gear {
            return;
        }
        self.gear = new_gear;
        self.shift_timer = self.shift_time;
        self.reverse_timer = 0.0;
        self.base_mut().emit_signal("gear_changed", &[new_gear.to_variant()]);
    }

    fn wheel_radius(&self) -> f64 {
        if self.wheel_consts_ok && !self.wheels.is_empty() {
            return self.wheel_consts[0][0];
        }
        self.wheels.first().map(|w| w.get_radius() as f64).unwrap_or(0.36)
    }

    /// Relê as constantes das rodas, a massa, o centro de massa e as relações de marcha.
    fn refresh_wheel_consts(&mut self) {
        for (i, w) in self.wheels.iter().enumerate().take(4) {
            self.wheel_consts[i] = [
                w.get_radius() as f64,
                w.get_suspension_rest_length() as f64,
                w.get_suspension_travel() as f64,
                w.get_suspension_stiffness() as f64,
            ];
        }
        self.st_mass = self.base().get_mass() as f64;
        self.st_com = self.base().get_center_of_mass();
        self.ratios = self.gear_ratios.to_vec();
        self.wheel_consts_ok = true;
        self.wheel_consts_age = 0;
    }

    fn ratio(&self, g: i64) -> f64 {
        if g == GEAR_REVERSE {
            return self.reverse_ratio;
        }
        if g < 1 {
            return 0.0;
        }
        let r = &self.ratios;
        if r.is_empty() {
            return 0.0;
        }
        r[((g - 1).clamp(0, r.len() as i64 - 1)) as usize] as f64
    }

    /// Piso sob a roda i (o metadado do corpo só é lido quando o corpo tocado muda).
    fn surface_of(&mut self, i: usize, contact: Option<Gd<Node3D>>) -> i32 {
        let id = contact.as_ref().map(|b| b.instance_id());
        if let Some(c) = self.surf_cache.get(i) {
            if c.0 == id && id.is_some() {
                return c.1;
            }
        }
        let surf = surface::of_body(contact);
        if i < 4 {
            self.surf_cache[i] = (id, surf);
        }
        surf
    }

    fn rpm_for_gear(&self, g: i64, radius: f64) -> f64 {
        let wheel_rpm = self.forward_speed.abs() / radius * 60.0 / TAU;
        self.idle_rpm.max(wheel_rpm * self.ratio(g))
    }

    /// Curva de torque simplificada (fração do pico) de um V6 turbo híbrido.
    fn torque_at(&self, engine_rpm: f64) -> f64 {
        let x = clamp((engine_rpm - self.idle_rpm) / (self.max_rpm - self.idle_rpm), 0.0, 1.0);
        self.peak_torque_nm * (0.72 + 0.28 * (x * PI * 0.85).sin())
    }

    fn state_at(&self, i: usize) -> i32 {
        self.rs_state.get(i).copied().unwrap_or(AIR)
    }

    fn rear_spinning(&self) -> bool {
        (0..self.wheels.len()).any(|i| !self.steers[i] && self.state_at(i) == SPIN)
    }

    fn broken(&self, i: usize) -> bool {
        self.wheel_broken.get(i).and_then(|v| v.try_to::<bool>().ok()).unwrap_or(false)
    }

    fn update_signal(&mut self, delta: f64) {
        if !self.puppet {
            self.signal_time = (self.signal_time - delta).max(0.0);
            self.signal_on = self.signal_time > 0.0 && self.signal_time % SIGNAL_PERIOD > SIGNAL_PERIOD * 0.45;
        }
        if self.signal_on != self.leds_shown {
            self.leds_shown = self.signal_on;
            let on = self.signal_on;
            // Os LEDs são montados no GDScript (presos ao vidro dos retrovisores)
            self.base_mut().call("_show_signal_leds", &[on.to_variant()]);
        }
    }

    fn animate_puppet_wheels(&mut self, delta: f64) {
        let steering = self.base().get_steering();
        let mounts = self._mounts.clone();
        for i in 0..self.wheels.len() {
            let mut w = self.wheels[i].clone();
            let radius = (w.get_radius() as f64).max(0.1);
            let spin = {
                let s = self._puppet_spin.as_mut_slice();
                if i >= s.len() {
                    continue;
                }
                s[i] = fposmod(s[i] as f64 + self.forward_speed * delta / radius, TAU) as f32;
                s[i]
            };
            let steer = if self.steers[i] { steering } else { 0.0 };
            let drop = self.puppet_wheel_drop.as_slice().get(i).copied().unwrap_or(0.04);
            let basis = Basis::from_axis_angle(Vector3::UP, steer) * Basis::from_axis_angle(Vector3::RIGHT, spin);
            let mount = mounts.as_slice().get(i).copied().unwrap_or(Vector3::ZERO);
            w.set_transform(Transform3D::new(basis, mount + Vector3::DOWN * drop));
        }
    }

    fn read_player_input(&mut self) {
        let input = Input::singleton();
        let a = &self.actions;
        self.throttle_input = input.get_action_strength(&a.accelerate) as f64;
        self.brake_input = input.get_action_strength(&a.brake) as f64;
        // No manual a ré é uma marcha (engata com Q e acelera com W): a tecla de ré não faz nada
        self.reverse_input = if self.automatic { input.get_action_strength(&a.reverse) as f64 } else { 0.0 };
        self.boost_input = input.is_action_pressed(&a.boost);
        self.steer_input = input.get_axis(&a.steer_right, &a.steer_left) as f64;
        self.drs_requested = input.is_action_pressed(&a.drs);
        let up = input.is_action_just_pressed(&a.shift_up);
        let down = input.is_action_just_pressed(&a.shift_down);
        let gearbox = input.is_action_just_pressed(&a.toggle_gearbox);
        let limiter = input.is_action_just_pressed(&a.pit_limiter);
        let tc = input.is_action_just_pressed(&a.toggle_tc);
        let bias_f = input.is_action_just_pressed(&a.bias_forward);
        let bias_r = input.is_action_just_pressed(&a.bias_rearward);
        let reset = input.is_action_just_pressed(&a.reset_car);
        let repair = input.is_action_just_pressed(&a.repair_car);
        let signal = input.is_action_just_pressed(&a.pass_signal);
        if up {
            self.shift_up();
        }
        if down {
            self.shift_down();
        }
        if gearbox {
            self.automatic = !self.automatic;
        }
        if limiter {
            self.limiter_on = !self.limiter_on;
        }
        if tc {
            self.traction_control = !self.traction_control;
        }
        if bias_f {
            self.adjust_brake_bias(0.005);
        }
        if bias_r {
            self.adjust_brake_bias(-0.005);
        }
        if reset {
            self.reset_car();
        }
        if repair && self.allow_quick_repair {
            // Remonta as peças: fica no GDScript (CarAssembly)
            self.base_mut().call("repair", &[]);
        }
        if signal {
            self.pass_signal();
        }
    }

    fn update_gearbox(&mut self, delta: f64) {
        self.shift_timer = (self.shift_timer - delta).max(0.0);
        // Automático: segurar a ré com o carro (quase) parado engata a ré; acelerar volta para a 1ª
        if self.automatic {
            if self.gear >= 1 && self.forward_speed < 0.5 && self.reverse_input > 0.3 && self.throttle_input < 0.05 {
                self.reverse_timer += delta;
                if self.reverse_timer > 0.2 {
                    self.change_gear(GEAR_REVERSE);
                }
            } else if (self.gear == GEAR_REVERSE && self.forward_speed > -0.5 && self.throttle_input > 0.05)
                || (self.gear == GEAR_NEUTRAL && self.throttle_input > 0.05)
            {
                self.change_gear(1);
            } else {
                self.reverse_timer = 0.0;
            }
        }
        let radius = self.wheel_radius();
        let mut target_rpm = self.rpm_for_gear(self.gear, radius);
        // Embreagem patinando na largada: o giro sobe com o acelerador.
        if self.gear == 1 || self.gear == GEAR_REVERSE {
            let pedal = if self.gear == GEAR_REVERSE && self.automatic { self.reverse_input } else { self.throttle_input };
            target_rpm = target_rpm.max(lerp(self.idle_rpm, self.launch_rpm, pedal));
        }
        // Neutro: o motor gira solto com o acelerador
        if self.gear == GEAR_NEUTRAL {
            target_rpm = lerp(self.idle_rpm, self.max_rpm * 0.97, self.throttle_input);
        }
        // Roda traseira patinando: o motor "solta" o giro.
        if self.rear_spinning() {
            target_rpm = target_rpm.max(lerp(target_rpm, self.max_rpm, 0.6));
        }
        self.rpm = lerp(self.rpm, target_rpm.min(self.max_rpm + 150.0), 1.0 - (-18.0 * delta).exp());

        if self.automatic && self.gear >= 1 && self.shift_timer <= 0.0 {
            let n = self.gear_ratios.len() as i64;
            if self.rpm_for_gear(self.gear, radius) > self.upshift_rpm && self.gear < n {
                self.shift_up();
            } else if self.gear > 1
                && self.rpm_for_gear(self.gear, radius) < self.downshift_rpm
                && self.rpm_for_gear(self.gear - 1, radius) < self.upshift_rpm - 600.0
            {
                self.shift_down();
            }
        }
    }

    /// Calcula, por roda, a força de tração pedida ao pneu e a força de frenagem.
    fn update_drive_and_brakes(&mut self, dt: f64) {
        let reversing = self.gear == GEAR_REVERSE;
        // Automático: a ré anda com a tecla de ré e o acelerador freia; manual: o acelerador anda para trás
        let drive_pedal = if reversing && self.automatic { self.reverse_input } else { self.throttle_input };
        let brake_pedal =
            if reversing && self.automatic { self.brake_input.max(self.throttle_input) } else { self.brake_input };
        let speed = self.forward_speed.abs();
        let radius = self.wheel_radius();

        let mut drive_force = 0.0;
        if self.gear != GEAR_NEUTRAL && self.shift_timer <= 0.0 && drive_pedal > 0.0 && brake_pedal < 0.05 {
            let torque_force = self.torque_at(self.rpm) * self.ratio(self.gear) / radius;
            let power_force = self.max_power_kw * 1000.0 / speed.max(1.0);
            drive_force = torque_force.min(power_force) * drive_pedal * self.damage_power;
            if self.rpm_for_gear(self.gear, radius) >= self.max_rpm {
                drive_force = 0.0;
            }
            if reversing {
                drive_force = drive_force.min(6000.0) * clamp((self.max_reverse_kmh - self.speed_kmh) / 5.0, 0.0, 1.0);
            }
            // Limitador: some a tração perto do limite
            if self.limiter_on && !reversing {
                drive_force *= clamp((LIMITER_KMH - 0.5 - self.speed_kmh) / 2.0, 0.0, 1.0);
            }
        }

        // Bateria: frear regenera; o boost gasta e empurra com o motor elétrico
        if brake_pedal > 0.05 && speed > 3.0 {
            self.battery =
                (self.battery + self.battery_regen_rate * brake_pedal * clamp(speed / 30.0, 0.0, 1.0) * dt).min(1.0);
        }
        let wants_boost = self.boost_input && !reversing && self.gear != GEAR_NEUTRAL && !self.limiter_on;
        if wants_boost && (self.boost_active || self.battery > self.boost_min_start) && self.battery > 0.0 {
            self.boost_active = true;
            self.battery = (self.battery - self.boost_drain_rate * dt).max(0.0);
            drive_force += self.boost_force * self.damage_power;
        } else {
            self.boost_active = false;
        }

        // Diferencial: mesmo torque nas duas rodas traseiras (a roda aliviada patina primeiro).
        let rear_count = self.traction.iter().filter(|&&t| t).count();
        let mut per_wheel = drive_force / (rear_count.max(1) as f64);
        self.tc_active = false;
        if self.traction_control && per_wheel > 0.0 {
            let mut limit = f64::INFINITY;
            for i in 0..self.wheels.len() {
                if self.traction[i] && self.max_force[i] > 0.0 {
                    let lat = clamp(self.lat_usage[i], 0.0, 0.95);
                    limit = limit.min(self.max_force[i] * self.assist_threshold * (1.0 - lat * lat).sqrt().max(0.3));
                }
            }
            if per_wheel > limit {
                per_wheel = limit;
                self.tc_active = true;
            }
        }
        if reversing {
            per_wheel = -per_wheel;
        }

        let mut engine_brake = 0.0;
        if drive_pedal < 0.02 && self.gear != GEAR_NEUTRAL {
            engine_brake = self.engine_braking_force * clamp(speed / 25.0, 0.0, 1.0);
        }
        let holding = speed < 0.5 && drive_pedal < 0.02;

        self.abs_active = false;
        for i in 0..self.wheels.len().min(4) {
            let front = self.steers[i];
            let mut brake = self.brake_force_per_wheel * brake_pedal;
            brake *= 2.0 * if front { self.brake_bias_front } else { 1.0 - self.brake_bias_front };
            if !front {
                brake += engine_brake * 0.5;
            }
            if self.brake_assist && speed > 2.0 && self.max_force[i] > 0.0 {
                // Reserva aderência para a curva: usa só o que sobra da elipse de atrito.
                let lat = clamp(self.lat_usage[i], 0.0, 0.95);
                let cap = self.max_force[i] * self.assist_threshold * (1.0 - lat * lat).sqrt().max(0.35);
                if brake > cap {
                    brake = cap;
                    self.abs_active = brake_pedal > 0.05;
                }
            }
            if holding {
                brake = brake.max(3000.0);
            }
            if self.hold {
                brake = brake.max(20000.0);
            }
            self.brake_request[i] = brake;
            self.drive_request[i] = if self.traction[i] && !self.hold { per_wheel } else { 0.0 };
        }
    }

    /// Modelo de pneu: calcula as forças de contato de cada roda (somadas no total do passo).
    fn update_tires(&mut self, delta: f64) {
        let gt = self.st_gt;
        let body = gt.basis;
        let up = body.col_b();
        let com = gt * self.st_com;
        let lv = self.st_lv;
        let av = self.st_av;
        let mass = self.st_mass;
        let steering = self.st_steer;
        let (compound, compound_wear) = match self.compound_cache {
            Some(c) => c,
            None => {
                let c = match self.config.as_mut() {
                    Some(cfg) => {
                        let grip = cfg.call("compound_grip", &[]).try_to::<f64>().unwrap_or(1.0);
                        let tc = cfg.get("tyre_compound").try_to::<i64>().unwrap_or(1);
                        (grip, COMPOUND_WEAR.get(tc as usize).copied().unwrap_or(1.0))
                    }
                    None => (1.0, 1.0),
                };
                if self.config.is_some() {
                    self.compound_cache = Some(c);
                }
                c
            }
        };
        let peak = self.peak_slip_angle_deg.to_radians();
        // B da Magic Formula escolhido para o pico cair exatamente em peak_slip_angle.
        let stiffness_b = (PI / (2.0 * self.tire_shape)).tan() / peak;
        let tables = surface::tables();

        // Força vertical total que os pneus precisam suportar (peso + downforce + aceleração vertical).
        let up_speed = lv.dot(up) as f64;
        self._vertical_accel = lerp(self._vertical_accel, (up_speed - self.prev_up_speed) / delta, 0.2);
        self.prev_up_speed = up_speed;
        let support =
            (mass * (9.8 * (up.y as f64).max(0.0) + clamp(self._vertical_accel, -20.0, 20.0)) + self._downforce).max(0.0);
        // Arrays por roda lidos uma vez e escritos uma vez no fim (cada leitura de um array exportado
        // são 3 chamadas ao motor; eram ~120 por passo)
        let n = self.wheels.len().min(4);
        let wheels = std::mem::take(&mut self.wheels);
        let mounts = read4(&self._mounts, Vector3::ZERO);
        let toe = read4(&self.wheel_toe, 0.0f32);
        let wgrip = read4(&self.wheel_grip, 1.0f32);
        let mut wear = read4(&self.tire_wear, 0.0f32);
        let mut surfs = read4(&self.tire_surface, 0i32);
        let mut broken = [false; 4];
        for (i, b) in broken.iter_mut().enumerate().take(n) {
            *b = self.broken(i);
        }
        let mut load = [0.0f32; 4];
        let mut usage_a = [0.0f32; 4];
        let mut slip_a = [0.0f32; 4];
        let mut state_a = [AIR; 4];
        // A compressão de cada mola define como essa força se divide entre as rodas.
        let mut contact = [false; 4];
        let mut cpoint = [Vector3::ZERO; 4];
        let mut springs = [0.0f64; 4];
        let mut spring_sum = 0.0;
        for i in 0..n {
            let wheel = &wheels[i];
            contact[i] = wheel.is_in_contact();
            if contact[i] {
                cpoint[i] = wheel.get_contact_point();
                let [radius, rest, travel, stiffness] = self.wheel_consts[i];
                let mount = gt * mounts[i];
                let length = (mount - cpoint[i]).dot(up) as f64 - radius;
                let compression = clamp(rest - length, 0.0, travel);
                springs[i] = stiffness * compression;
                spring_sum += springs[i];
            }
        }

        let origin = gt.origin;
        let body_z = body.col_c();
        for i in 0..n {
            let wheel = &wheels[i];
            if !contact[i] || broken[i] {
                self.max_force[i] = 0.0;
                self.alpha[i] = 0.0;
                continue;
            }
            let contact_point = cpoint[i];
            let normal = wheel.get_contact_normal();
            let fz = if spring_sum > 0.0 { support * springs[i] / spring_sum } else { 0.0 };

            // Referencial do pneu sobre o chão
            let mut heading = body_z;
            let wheel_angle = toe[i] as f64 + if self.steers[i] { steering } else { 0.0 };
            if wheel_angle != 0.0 {
                heading = body * Vector3::new(wheel_angle.sin() as f32, 0.0, wheel_angle.cos() as f32);
            }
            let fwd = (heading - normal * heading.dot(normal)).normalized();
            let side = normal.cross(fwd); // esquerda do pneu

            let vel = lv + av.cross(contact_point - com);
            let vx = vel.dot(fwd) as f64;
            let vy = vel.dot(side) as f64;

            // Ângulo de deriva com relaxação (o pneu precisa rolar um pouco para gerar força).
            let target_alpha = vy.atan2(vx.abs().max(LOW_SPEED_SLIP));
            let relax = clamp((vx.abs() + 1.0) * delta / self.relaxation_length, 0.0, 1.0);
            self.alpha[i] = lerp(self.alpha[i], target_alpha, relax);

            // Piso: grama e brita têm menos aderência e freiam o carro
            let surf = self.surface_of(i, wheel.get_contact_body());
            surfs[i] = surf;
            let base_mu = if self.steers[i] { self.front_grip } else { self.rear_grip };
            let wear_grip = 1.0 - self.worn_grip_loss * (wear[i] as f64).powf(1.6);
            let mu = base_mu
                * compound
                * surface::at(&tables.grip, surf)
                * wgrip[i] as f64
                * wear_grip
                * (1.0 - self.load_sensitivity * (fz / self.nominal_load - 1.0)).max(0.5);
            let max_force = mu * fz;
            self.max_force[i] = max_force;

            // Força lateral pura (Magic Formula, E = 0)
            let mut fy = -max_force
                * (self.tire_shape * (stiffness_b * self.alpha[i]).atan()).sin()
                * surface::at(&tables.side_grip, surf);
            self.lat_usage[i] = fy.abs() / max_force.max(1.0);

            // Força longitudinal pedida (motor + freio)
            let mut fx = self.drive_request[i];
            let braking = self.brake_request[i] > 0.0 && fx.abs() < 1.0;
            if braking {
                fx = -signf(vx) * self.brake_request[i] * clamp(vx.abs() / 0.3, 0.0, 1.0);
            }

            // Elipse de atrito
            let mut state = GRIP;
            let long_usage = fx.abs() / max_force.max(1.0);
            if long_usage > 1.0 {
                state = if braking { LOCK } else { SPIN };
                fx = signf(fx) * max_force * self.sliding_grip;
                fy *= self.locked_lateral_grip;
            } else {
                fy *= (1.0 - long_usage * long_usage).sqrt().max(self.locked_lateral_grip);
                if self.alpha[i].abs() > peak * 1.2 {
                    state = SLIDE;
                }
            }

            // Desgaste: potência dissipada no contato (força × velocidade de deslizamento)
            let slide_speed = vy.abs() + if state == LOCK || state == SPIN { vx.abs() } else { 0.0 };
            let effort = Vector2::new(fx as f32, fy as f32).length() as f64 / max_force.max(1.0);
            let wear_power = (slide_speed * 0.6 + effort * effort * vx.abs() * 0.012) * fz / self.nominal_load;
            wear[i] = (wear[i] as f64 + wear_power * compound_wear * self.tyre_wear_rate * 0.0009 * delta).min(1.0) as f32;
            let mut force = fwd * fx as f32 + side * fy as f32;
            let drag = surface::at(&tables.drag, surf) * fz;
            if drag > 0.0 {
                // Resistência do piso solto (afunda o pneu): contra o movimento nos dois eixos
                force -= fwd * (signf(vx) * drag * clamp(vx.abs() / 2.0, 0.0, 1.0)) as f32;
                force -= side * (signf(vy) * drag * 0.5 * clamp(vy.abs() / 2.0, 0.0, 1.0)) as f32;
            }
            let rumble = surface::at(&tables.rumble, surf);
            if rumble > 0.0 && vx.abs() > 4.0 {
                let r = godot::global::randf_range(-1.0, 1.0);
                force += normal * (r * rumble * mass * 0.25 * (vx.abs() / 30.0).min(1.0)) as f32;
            }
            self.add_force(force, contact_point - origin);
            let mut usage = Vector2::new(fx as f32, fy as f32).length() as f64 / max_force.max(1.0);
            if state != GRIP {
                usage = usage.max(1.05);
            }
            load[i] = fz as f32;
            usage_a[i] = usage as f32;
            slip_a[i] = self.alpha[i].to_degrees() as f32;
            state_a[i] = state;
        }
        self.wheels = wheels;
        write4(&mut self.tire_load, &load, n);
        write4(&mut self.tire_usage, &usage_a, n);
        write4(&mut self.tire_slip_deg, &slip_a, n);
        write4(&mut self.tire_state, &state_a, n);
        write4(&mut self.tire_surface, &surfs, n);
        write4(&mut self.tire_wear, &wear, n);
        self.rs_state[..n].copy_from_slice(&state_a[..n]);
        self.rs_slip[..n].copy_from_slice(&slip_a[..n]);
        self.rs_surface[..n].copy_from_slice(&surfs[..n]);
        self.rs_usage[..n].copy_from_slice(&usage_a[..n]);
        self.update_smoke(lv.length() as f64);
    }

    fn update_steering(&mut self, delta: f64) {
        let vel = self.st_lv;
        let basis = self.st_gt.basis;
        let speed = vel.length();
        self.body_slip_angle = 0.0;
        if speed > 5.0 {
            self.body_slip_angle = (vel.dot(basis.col_a()) as f64).atan2((vel.dot(basis.col_c()) as f64).abs());
        }
        let t = clamp(self.forward_speed.abs() / self.steer_speed_reference, 0.0, 1.0);
        let mut limit = lerp(self.max_steer_angle, self.high_speed_steer_angle, t.sqrt());
        // Permite contraesterçar quando a traseira escapa, mesmo em alta velocidade.
        limit = clamp(limit.max(self.body_slip_angle.abs() + 0.05), 0.0, self.max_steer_angle);
        let target = self.steer_input * limit;
        let steering = self.st_steer;
        let rate = self.steer_rate * if target.abs() < steering.abs() { 1.6 } else { 1.0 };
        let new_steering = move_toward(steering, target, rate * delta);
        self.base_mut().set_steering(new_steering as f32);
        // O que o motor guarda é f32: o resto do passo usa o mesmo valor
        self.st_steer = new_steering as f32 as f64;
    }

    fn update_handling(&mut self) {
        self.handling = NEUTRAL;
        if self.speed_kmh < 30.0 {
            return;
        }
        let mut front: f64 = 0.0;
        let mut rear: f64 = 0.0;
        let mut rear_spin = false;
        for i in 0..self.wheels.len().min(4) {
            let slip = (self.rs_slip[i] as f64).abs();
            if self.steers[i] {
                front = front.max(slip);
            } else {
                rear = rear.max(slip);
                rear_spin = rear_spin || self.state_at(i) == SPIN;
            }
        }
        let limit = self.peak_slip_angle_deg;
        if (rear > limit && rear - front > 1.5) || (rear_spin && self.body_slip_angle.abs() > 0.06) {
            self.handling = OVERSTEER;
        } else if front > limit && front - rear > 1.5 {
            self.handling = UNDERSTEER;
        }
    }

    fn update_drs(&mut self, delta: f64) {
        let allowed = self.drs_requested
            && self.drs_allowed
            && self.speed_kmh >= self.drs_min_speed_kmh
            && self.brake_input < 0.05;
        if allowed != self.drs_open {
            self.drs_open = allowed;
            self.base_mut().emit_signal("drs_changed", &[allowed.to_variant()]);
        }
        let target = if self.drs_open { 1.0 } else { 0.0 };
        self.drs_amount = move_toward(self.drs_amount, target, delta * 5.0);
    }

    fn apply_aero(&mut self) {
        let v2 = self.forward_speed * self.forward_speed;
        let df_area = self.effective_downforce_area * (1.0 - self.drs_downforce_reduction * self.drs_amount);
        let drag_a =
            (self.effective_drag_area * (1.0 - self.drs_drag_reduction * self.drs_amount) + self.damage_drag).max(0.3);
        let downforce = 0.5 * AIR_DENSITY * df_area * v2;
        let basis = self.st_gt.basis;
        let down = -basis.col_b();
        let front_point = basis * Vector3::new(0.0, 0.25, 1.8);
        let rear_point = basis * Vector3::new(0.0, 0.25, -1.8);
        let front_df = downforce * self.effective_balance * self.damage_front_downforce;
        let rear_df = downforce * (1.0 - self.effective_balance) * self.damage_rear_downforce;
        self._downforce = front_df + rear_df;
        self.add_force(down * front_df as f32, front_point);
        self.add_force(down * rear_df as f32, rear_point);

        let vel = self.st_lv;
        let speed = vel.length() as f64;
        if speed > 0.1 {
            let mass = self.st_mass;
            let drag = 0.5 * AIR_DENSITY * drag_a * speed * speed * (1.0 - clamp(self.slipstream, 0.0, 1.0))
                + self.rolling_resistance * mass * 9.8;
            self.acc_force += -vel / speed as f32 * drag as f32;
        }
    }

    /// Soma uma força aplicada em `position` (relativa à origem do corpo, em coordenadas globais) no
    /// total do passo: força + torque em torno do centro de massa, como o apply_force do motor.
    fn add_force(&mut self, force: Vector3, position: Vector3) {
        let com = self.st_gt.basis * self.st_com;
        self.acc_force += force;
        self.acc_torque += (position - com).cross(force);
    }

    fn animate_parts(&mut self, steering: f64) {
        let now = (self.drs_amount, steering);
        if self.parts_applied.is_some_and(|(d, s)| (d - now.0).abs() < 1e-5 && (s - now.1).abs() < 1e-5) {
            return;
        }
        self.parts_applied = Some(now);
        if let Some(mut flap) = self.drs_flap.clone().filter(|f| f.is_instance_valid()) {
            let open = Basis::from_axis_angle(
                Vector3::RIGHT,
                (-self.drs_flap_angle_deg.to_radians() * self.drs_amount) as f32,
            );
            flap.set_transform(Transform3D::new(self.drs_flap_rest.basis * open, self.drs_flap_rest.origin));
        }
        if let Some(mut wheel) = self.steering_wheel.clone().filter(|w| w.is_instance_valid()) {
            let turn = Basis::from_axis_angle(Vector3::BACK, (-steering * self.steering_wheel_ratio) as f32);
            wheel.set_transform(Transform3D::new(
                self.steering_wheel_rest.basis * turn,
                self.steering_wheel_rest.origin,
            ));
        }
    }

    fn update_smoke(&mut self, speed: f64) {
        // Longe da câmera: nem fumaça nem pó (partículas na CPU, 8 por carro)
        let near = crate::fx::near_camera(&self.base().clone().upcast(), self.st_gt.origin, FX_RANGE);
        let mut mask = 0u32;
        let mut tints = [None; 4];
        for i in 0..self.dust.len().min(4) {
            let surf = self.rs_surface[i];
            let loose = surf == surface::GRAVEL || surf == surface::GRASS;
            if near && loose && self.state_at(i) != AIR && speed > 4.0 {
                mask |= 1 << i;
                tints[i] = Some(if surf == surface::GRAVEL {
                    Color::from_rgba(0.85, 0.74, 0.55, 0.55)
                } else {
                    Color::from_rgba(0.45, 0.62, 0.3, 0.35)
                });
            }
        }
        for i in 0..self.smoke.len().min(4) {
            let state = self.state_at(i);
            let slip = self.rs_slip[i] as f64;
            let sliding = state == SPIN
                || state == LOCK
                || (state == SLIDE && slip.abs() > self.peak_slip_angle_deg * 1.8);
            if near && ((sliding && speed > 3.0) || (state == SPIN && self.throttle_input > 0.5)) {
                mask |= 1 << (4 + i);
            }
        }
        let changed = self.fx_mask != Some(mask);
        self.fx_mask = Some(mask);
        for i in 0..self.dust.len().min(4) {
            let mut dust = self.dust[i].clone();
            if !dust.is_instance_valid() {
                continue;
            }
            let emitting = mask & (1 << i) != 0;
            if changed {
                dust.set_emitting(emitting);
            }
            if let Some(tint) = tints[i] {
                // Cor do piso no material das partículas (cor × rampa, como nas da CPU)
                if let Some(mut pm) = dust.get_process_material().and_then(|m| m.try_cast::<ParticleProcessMaterial>().ok()) {
                    if pm.get_color() != tint {
                        let mut fade = Gradient::new_gd();
                        fade.set_color(0, tint);
                        fade.set_color(1, Color::from_rgba(tint.r, tint.g, tint.b, 0.0));
                        let mut ramp = GradientTexture1D::new_gd();
                        ramp.set_gradient(&fade);
                        pm.set_color(tint);
                        pm.set_color_ramp(&ramp);
                    }
                }
            }
        }
        if changed {
            for i in 0..self.smoke.len().min(4) {
                let mut smoke = self.smoke[i].clone();
                if smoke.is_instance_valid() {
                    smoke.set_emitting(mask & (1 << (4 + i)) != 0);
                }
            }
        }
    }
}
