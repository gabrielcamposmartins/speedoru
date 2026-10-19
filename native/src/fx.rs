//! Efeitos que rodam a cada quadro: rastros (TrailRibbon), efeitos do carro (CarEffects) e o vácuo
//! visual (SlipstreamFx). Os scripts GDScript montam os nós e materiais uma vez e passam para cá.

use std::cell::{Cell, RefCell};
use std::collections::VecDeque;

use godot::builtin::AnyArray;
use godot::classes::mesh::{ArrayType, PrimitiveType};
use godot::classes::{
    ArrayMesh, Camera3D, Decal, Engine, GpuParticles3D, IMeshInstance3D, INode3D, ImmediateMesh, Material,
    MeshInstance3D, OmniLight3D, Script, ShaderMaterial, StandardMaterial3D, VehicleBody3D, VehicleWheel3D,
};
use godot::prelude::*;

use crate::car::{F1CarCore, LOCK, SLIDE, SPIN};
use crate::surface;
use crate::util::{clamp, lerp, move_toward, smoothstep};

thread_local! {
    /// Daylight.current_night (0 = dia, 1 = noite), escrito pelo Daylight.
    static NIGHT: Cell<f64> = const { Cell::new(0.0) };
    static RACE_CAMERA_SCRIPT: Cell<Option<InstanceId>> = const { Cell::new(None) };
    /// Câmera do quadro (por viewport), lida uma vez por quadro: efeitos, rastros e som de cada carro
    /// perguntavam de novo (14 carros × várias consultas por quadro).
    static FRAME_CAM: RefCell<Option<FrameCam>> = const { RefCell::new(None) };
}

pub fn night() -> f64 {
    NIGHT.with(|n| n.get())
}

type RaceCam = (Gd<Camera3D>, i64, Option<Gd<F1CarCore>>);

struct FrameCam {
    frame: u64,
    viewport: InstanceId,
    race: Option<RaceCam>,
    pos: Option<Vector3>,
    forward: Vector3,
}

/// Dados da câmera ativa da viewport do nó, guardados até o próximo quadro.
fn frame_cam<R>(node: &Gd<Node>, f: impl FnOnce(&FrameCam) -> R) -> Option<R> {
    let vp = node.get_viewport()?;
    let frame = Engine::singleton().get_process_frames();
    let vid = vp.instance_id();
    FRAME_CAM.with(|cell| {
        let mut slot = cell.borrow_mut();
        if slot.as_ref().is_none_or(|fc| fc.frame != frame || fc.viewport != vid) {
            let cam = vp.get_camera_3d();
            let pos = cam.as_ref().map(|c| c.get_global_position());
            let forward = cam.as_ref().map(|c| -c.get_global_basis().col_c()).unwrap_or(Vector3::FORWARD);
            let race = cam.and_then(race_camera_of);
            *slot = Some(FrameCam { frame, viewport: vid, race, pos, forward });
        }
        slot.as_ref().map(f)
    })
}

fn race_camera_of(cam: Gd<Camera3D>) -> Option<RaceCam> {
    let id = RACE_CAMERA_SCRIPT.with(|c| {
        if c.get().is_none() {
            c.set(try_load::<Script>("res://scripts/camera/race_camera.gd").ok().map(|s| s.instance_id()));
        }
        c.get()
    });
    let script = cam.get_script()?;
    if Some(script.instance_id()) != id {
        return None;
    }
    let mode = cam.get("mode").try_to::<i64>().unwrap_or(0);
    let target = cam.get("target").try_to::<Gd<F1CarCore>>().ok();
    Some((cam, mode, target))
}

/// Câmera ativa, se for a RaceCamera: (câmera, modo, carro seguido).
pub fn race_camera(node: &Gd<Node>) -> Option<RaceCam> {
    frame_cam(node, |fc| fc.race.clone()).flatten()
}

pub fn camera_position(node: &Gd<Node>) -> Option<Vector3> {
    frame_cam(node, |fc| fc.pos).flatten()
}

/// Efeitos de um carro em `pos` valem a pena: perto da câmera e não muito atrás dela.
pub fn near_camera(node: &Gd<Node>, pos: Vector3, range: f32) -> bool {
    frame_cam(node, |fc| match fc.pos {
        Some(cam) => {
            let to = pos - cam;
            let d = to.length();
            d < range && (d < 25.0 || to.dot(fc.forward) > -0.2 * d)
        }
        None => true,
    })
    .unwrap_or(true)
}

fn cast_all<T: GodotClass>(arr: &AnyArray) -> Vec<Gd<T>>
where
    T: Inherits<Object>,
{
    arr.iter_shared().filter_map(|v| v.try_to::<Gd<Object>>().ok().and_then(|o| o.try_cast::<T>().ok())).collect()
}

// ---------------------------------------------------------------------------
// TrailRibbon
// ---------------------------------------------------------------------------
const GROUND: i64 = 0;
const BILLBOARD: i64 = 1;
/// Marcas no chão: refaz para o desbotamento a cada tantos quadros.
const FADE_FRAMES: u64 = 45;
/// Vida (s) acima da qual pontos que saem não pedem uma refeita: quando saem já estão invisíveis (o
/// alfa chega a zero no fim da vida) e a próxima refeita do desbotamento os tira. Marcas de pneu (45
/// s) refaziam a fita inteira a cada quadro durante 45 s depois de cada derrapada só para isso.
const QUIET_EXPIRE: f64 = 10.0;

struct Pt {
    pos: Vector3,
    normal: Vector3,
    side: Vector3,
    time: f64,
    brk: bool,
}

/// Fita que segue um ponto (rastro): ver scripts/car/trail_ribbon.gd.
#[derive(GodotClass)]
#[class(init, base=MeshInstance3D)]
pub struct TrailRibbonCore {
    /// TrailRibbon.Mode
    #[var]
    mode: i64,
    #[var]
    #[init(val = 0.3)]
    width: f64,
    #[var]
    #[init(val = 20.0)]
    lifetime: f64,
    #[var]
    #[init(val = 500)]
    max_points: i64,
    #[var]
    #[init(val = 0.25)]
    min_spacing: f64,
    /// Cor; o alfa some ao longo da idade (fade_start = fração da vida em que começa a sumir).
    #[var]
    #[init(val = Color::from_rgba(0.05, 0.05, 0.06, 0.6))]
    color: Color,
    #[var]
    #[init(val = 0.6)]
    fade_start: f64,
    /// Alfa extra perto da ponta nova (BILLBOARD: a fita "nasce" brilhante e afina).
    #[var]
    taper: bool,
    points: VecDeque<Pt>,
    time: f64,
    dirty: bool,
    #[init(val = ArrayMesh::new_gd())]
    ribbon: Gd<ArrayMesh>,
    #[init(val = true)]
    brk: bool,
    /// Buffers reaproveitados entre as refeitas (antes: um PackedInt32Array novo por segmento).
    buf_v: Vec<Vector3>,
    buf_n: Vec<Vector3>,
    buf_c: Vec<Color>,
    buf_uv: Vec<Vector2>,
    buf_i: Vec<i32>,
    base: Base<MeshInstance3D>,
}

#[godot_api]
impl IMeshInstance3D for TrailRibbonCore {
    fn ready(&mut self) {
        let mesh = self.ribbon.clone();
        let mut b = self.base_mut();
        b.set_as_top_level(true);
        b.set_mesh(&mesh);
        b.set_cast_shadows_setting(godot::classes::geometry_instance_3d::ShadowCastingSetting::OFF);
        b.set_extra_cull_margin(16384.0);
    }

    fn process(&mut self, delta: f64) {
        self.time += delta;
        if self.points.is_empty() {
            if self.dirty {
                self.ribbon.clear_surfaces();
                self.dirty = false;
            }
            return;
        }
        let mut removed = false;
        while self.points.front().is_some_and(|p| self.time - p.time > self.lifetime) {
            self.points.pop_front();
            removed = self.lifetime < QUIET_EXPIRE;
        }
        if self.points.is_empty() {
            // Acabaram os pontos: limpa no próximo quadro
            self.dirty = true;
            return;
        }
        let frame = Engine::singleton().get_process_frames().wrapping_add(self.base().instance_id().to_i64() as u64);
        if self.mode == BILLBOARD || self.dirty || removed || frame % FADE_FRAMES == 0 {
            self.rebuild();
            self.dirty = false;
        }
    }
}

#[godot_api]
impl TrailRibbonCore {
    #[func]
    pub fn add_point(&mut self, pos: Vector3, normal: Vector3, forward: Vector3) {
        if !self.brk {
            if let Some(last) = self.points.back() {
                if (last.pos.distance_to(pos) as f64) < self.min_spacing {
                    return;
                }
            }
        }
        let side = normal.cross(forward).normalized();
        self.points.push_back(Pt { pos, normal, side, time: self.time, brk: self.brk });
        self.brk = false;
        while self.points.len() as i64 > self.max_points {
            self.points.pop_front();
        }
        self.dirty = true;
    }

    /// Encerra o traço atual; o próximo add_point começa outro (sem ligar os dois).
    #[func]
    pub fn stop(&mut self) {
        self.brk = true;
    }

    #[func]
    fn clear(&mut self) {
        self.points.clear();
        self.dirty = true;
    }
}

impl TrailRibbonCore {
    fn color_at(&self, born: f64, index: usize) -> Color {
        let age = (self.time - born) / self.lifetime;
        let mut alpha = 1.0 - smoothstep(self.fade_start, 1.0, age);
        // Pontas do traço suaves (não começa nem termina em degrau)
        if self.mode == GROUND {
            alpha *= smoothstep(0.0, 3.0, index as f64);
        }
        Color::from_rgba(self.color.r, self.color.g, self.color.b, self.color.a * alpha as f32)
    }

    fn rebuild(&mut self) {
        self.ribbon.clear_surfaces();
        let n = self.points.len();
        if n < 2 {
            return;
        }
        let cam_pos = camera_position(&self.base().clone().upcast()).unwrap_or(Vector3::ZERO);
        let (mut v, mut nm, mut c, mut uv, mut idx) = (
            std::mem::take(&mut self.buf_v),
            std::mem::take(&mut self.buf_n),
            std::mem::take(&mut self.buf_c),
            std::mem::take(&mut self.buf_uv),
            std::mem::take(&mut self.buf_i),
        );
        v.clear();
        nm.clear();
        c.clear();
        uv.clear();
        idx.clear();
        for k in 0..n {
            let p = &self.points[k];
            let mut side = p.side;
            if self.mode == BILLBOARD {
                // Fita virada para a câmera, na direção do traço naquele ponto
                let dir = (self.points[(k + 1).min(n - 1)].pos - self.points[k.saturating_sub(1)].pos).normalized();
                side = dir.cross(cam_pos - p.pos).normalized();
            }
            let w = self.width * if self.taper { 0.25 + 0.75 * k as f64 / n as f64 } else { 1.0 } * 0.5;
            let col = self.color_at(p.time, k);
            v.push(p.pos - side * w as f32);
            v.push(p.pos + side * w as f32);
            nm.push(p.normal);
            nm.push(p.normal);
            c.push(col);
            c.push(col);
            uv.push(Vector2::new(0.0, 0.0));
            uv.push(Vector2::new(1.0, 0.0));
            // Liga ao ponto anterior, a não ser no começo de um traço novo
            if k > 0 && !p.brk {
                let a = ((k - 1) * 2) as i32;
                idx.extend_from_slice(&[a, a + 2, a + 3, a, a + 3, a + 1]);
            }
        }
        let empty = idx.is_empty();
        let verts = PackedVector3Array::from(&v[..]);
        let normals = PackedVector3Array::from(&nm[..]);
        let colors = PackedColorArray::from(&c[..]);
        let uvs = PackedVector2Array::from(&uv[..]);
        let index = PackedInt32Array::from(&idx[..]);
        self.buf_v = v;
        self.buf_n = nm;
        self.buf_c = c;
        self.buf_uv = uv;
        self.buf_i = idx;
        if empty {
            return;
        }
        let mut arrays = VarArray::new();
        arrays.resize(ArrayType::MAX.ord() as usize, &Variant::nil());
        arrays.set(ArrayType::VERTEX.ord() as usize, &verts.to_variant());
        arrays.set(ArrayType::NORMAL.ord() as usize, &normals.to_variant());
        arrays.set(ArrayType::COLOR.ord() as usize, &colors.to_variant());
        arrays.set(ArrayType::TEX_UV.ord() as usize, &uvs.to_variant());
        arrays.set(ArrayType::INDEX.ord() as usize, &index.to_variant());
        self.ribbon.add_surface_from_arrays(PrimitiveType::TRIANGLES, &arrays);
    }
}

// ---------------------------------------------------------------------------
// CarEffects
// ---------------------------------------------------------------------------
/// Efeitos visuais do carro ligados à pilotagem: ver scripts/car/car_effects.gd.
#[derive(GodotClass)]
#[class(init, base=Node3D)]
pub struct CarEffectsCore {
    /// Marcas de pneu: velocidade mínima (m/s).
    #[export]
    #[init(val = 7.0)]
    skid_min_speed: f64,
    /// Brilho do boost (0..1).
    #[var]
    glow: f64,
    car: Option<Gd<F1CarCore>>,
    skids: Vec<Gd<TrailRibbonCore>>,
    trails: Vec<Gd<TrailRibbonCore>>,
    dust: Vec<Gd<GpuParticles3D>>,
    lights: Vec<Gd<OmniLight3D>>,
    dust_material: Option<Gd<StandardMaterial3D>>,
    #[init(val = Color::WHITE)]
    color: Color,
    time: f64,
    neon_decal: Option<Gd<Decal>>,
    neon_lights: Vec<Gd<OmniLight3D>>,
    neon_tubes: Option<Gd<MeshInstance3D>>,
    neon_material: Option<Gd<StandardMaterial3D>>,
    neon: f64,
    brake_material: Option<Gd<StandardMaterial3D>>,
    brake_light: Option<Gd<OmniLight3D>>,
    brake_glow: f64,
    brake_flares: Vec<Gd<MeshInstance3D>>,
    flare_material: Option<Gd<StandardMaterial3D>>,
    /// Materiais das rodas ainda com o brilho do boost (para apagá-lo uma vez quando ele acaba).
    #[init(val = true)]
    glow_shown: bool,
    /// Do CarConfig (lidos a cada CONFIG_POLL s, não a cada quadro): cor do boost, neon e cor dele;
    /// e se a asa traseira já caiu (lanternas).
    cfg_t: f64,
    #[init(val = Color::CYAN)]
    boost_color: Color,
    neon_enabled: bool,
    #[init(val = Color::WHITE)]
    neon_color: Color,
    wing_gone: bool,
    /// Rodas do carro (antes: um Array novo do get_wheels() por quadro).
    wheels: Vec<Gd<VehicleWheel3D>>,
    /// O que já está aplicado nos nós (só muda o que mudou): luzes do boost, neon, lanterna.
    lights_on: Option<bool>,
    neon_shown: Option<bool>,
    brake_applied: Option<[f32; 4]>,
    flares_mask: Option<u32>,
    base: Base<Node3D>,
}

/// A cada quanto (s) os efeitos releem o CarConfig e o dano.
const CONFIG_POLL: f64 = 0.25;
/// Até que distância da câmera (m) um carro faz marcas de pneu, pó e rastro do boost (B7).
const EFFECTS_RANGE: f32 = 150.0;

#[godot_api]
impl INode3D for CarEffectsCore {
    fn process(&mut self, delta: f64) {
        let Some(car) = self.car.clone() else { return };
        if !car.is_instance_valid() {
            return;
        }
        self.time += delta;
        let body = car.clone().upcast::<VehicleBody3D>();
        self.cfg_t -= delta;
        if self.cfg_t <= 0.0 {
            self.cfg_t = CONFIG_POLL;
            self.poll_config(&body);
        }
        let boost_active = car.bind().boost_active;
        let target = if boost_active { 1.0 } else { 0.0 };
        self.glow = move_toward(self.glow, target, delta * if target > self.glow { 6.0 } else { 2.5 });
        let c = self.boost_color;
        if c != self.color {
            if let Some(mut m) = self.dust_material.clone() {
                self.color = c;
                m.set_albedo(c);
            }
        }
        if self.glow > 0.0 || self.glow_shown {
            self.update_wheel_materials(&body, c);
            self.glow_shown = self.glow > 0.0;
        }
        self.update_neon(delta);
        self.update_brake_light(&car, &body, delta);
        if self.wheels.is_empty() || !self.wheels.iter().all(|w| w.is_instance_valid()) {
            self.wheels = car.bind().get_wheels().iter_shared().collect();
        }
        let wheels = self.wheels.clone();
        let speed = body.get_linear_velocity().length() as f64;
        let gt = body.get_global_transform();
        let forward = gt.basis.col_c();
        let up = gt.basis.col_b();
        // Longe da câmera (ou atrás dela): sem marcas de pneu, pó e rastro do boost (B7)
        let near = near_camera(&self.base().clone().upcast(), gt.origin, EFFECTS_RANGE);
        let lights_on = self.glow > 0.01;
        let lights_changed = self.lights_on != Some(lights_on);
        self.lights_on = Some(lights_on);
        for (i, wheel) in wheels.iter().enumerate() {
            if i >= self.lights.len() {
                break;
            }
            let hub = wheel.get_global_position();
            // Boost: luz, rastro e pó mágico (apagados não são mexidos)
            let mut light = self.lights[i].clone();
            if lights_changed {
                light.set_visible(lights_on);
            }
            if lights_on {
                light.set_global_position(hub);
                light.set_color(c);
                light.set_param(
                    godot::classes::light_3d::Param::ENERGY,
                    (self.glow * (1.6 + 0.4 * (self.time * 18.0 + i as f64).sin())) as f32,
                );
            }
            let dusting = near && boost_active && speed > 2.0;
            let mut dust = self.dust[i].clone();
            if dusting || dust.is_emitting() {
                dust.set_global_position(hub);
                dust.set_emitting(dusting);
            }
            let mut trail = self.trails[i].clone();
            if near && boost_active && speed > 1.0 {
                let mut t = trail.bind_mut();
                t.color = Color::from_rgba(c.r, c.g, c.b, 0.9);
                t.add_point(hub - up * 0.1, up, forward);
            } else {
                trail.bind_mut().stop();
            }
            // Marcas de pneu
            let mut skid = self.skids[i].clone();
            if near && self.skidding(&car, i, wheel, speed) {
                let n = wheel.get_contact_normal();
                skid.bind_mut().add_point(wheel.get_contact_point() + n * 0.012, n, forward);
            } else {
                skid.bind_mut().stop();
            }
        }
    }
}

#[godot_api]
impl CarEffectsCore {
    /// Liga os nós montados pelo CarEffects._setup.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn _core_setup(
        &mut self,
        car: Gd<F1CarCore>,
        skids: AnyArray,
        trails: AnyArray,
        dust: AnyArray,
        lights: AnyArray,
        dust_material: Option<Gd<StandardMaterial3D>>,
        neon_decal: Gd<Decal>,
        neon_lights: AnyArray,
        neon_tubes: Gd<MeshInstance3D>,
        neon_material: Gd<StandardMaterial3D>,
        brake_material: Gd<StandardMaterial3D>,
        brake_light: Gd<OmniLight3D>,
        brake_flares: AnyArray,
        flare_material: Gd<StandardMaterial3D>,
    ) {
        self.car = Some(car);
        self.skids = cast_all(&skids);
        self.trails = cast_all(&trails);
        self.dust = cast_all(&dust);
        self.lights = cast_all(&lights);
        self.dust_material = dust_material;
        self.neon_decal = Some(neon_decal);
        self.neon_lights = cast_all(&neon_lights);
        self.neon_tubes = Some(neon_tubes);
        self.neon_material = Some(neon_material);
        self.brake_material = Some(brake_material);
        self.brake_light = Some(brake_light);
        self.brake_flares = cast_all(&brake_flares);
        self.flare_material = Some(flare_material);
    }

    /// Daylight.current_night para os efeitos (o Daylight chama a cada mudança).
    #[func]
    fn set_night(night: f64) {
        NIGHT.with(|n| n.set(night));
    }
}

impl CarEffectsCore {
    /// Relê do CarConfig o que os efeitos usam e se a asa traseira já caiu.
    fn poll_config(&mut self, body: &Gd<VehicleBody3D>) {
        let config = body.get("config").try_to::<Gd<Object>>().ok();
        self.boost_color = config
            .as_ref()
            .and_then(|cfg| cfg.get("boost_color").try_to::<Color>().ok())
            .unwrap_or(Color::CYAN);
        self.neon_enabled = config.as_ref().map(|c| c.get("neon_enabled").try_to::<bool>().unwrap_or(false)).unwrap_or(false);
        self.neon_color =
            config.as_ref().and_then(|cfg| cfg.get("neon_color").try_to::<Color>().ok()).unwrap_or(Color::WHITE);
        self.wing_gone = body
            .get_node_or_null("Damage")
            .and_then(|d| d.get("detached").try_to::<VarDictionary>().ok())
            .is_some_and(|d| d.contains_key(&Variant::from("rear_wing")));
    }

    fn skidding(&self, car: &Gd<F1CarCore>, i: usize, wheel: &Gd<VehicleWheel3D>, speed: f64) -> bool {
        let c = car.bind();
        let broken = c.wheel_broken.get(i).and_then(|v| v.try_to::<bool>().ok()).unwrap_or(false);
        if !wheel.is_in_contact() || speed < self.skid_min_speed || broken {
            return false;
        }
        // Cópias no Rust do estado dos pneus (o carro só faz marcas rodando o próprio modelo de pneu)
        let surf = c.rs_surface.get(i).copied().unwrap_or(0);
        if surf != surface::ASPHALT && surf != surface::KERB {
            return false;
        }
        let state = c.rs_state.get(i).copied().unwrap_or(0);
        if state == LOCK || state == SPIN {
            return true;
        }
        let slip = c.rs_slip.get(i).copied().unwrap_or(0.0) as f64;
        if state == SLIDE && slip.abs() > c.peak_slip_angle_deg * 1.5 {
            return true;
        }
        c.brake_input > 0.6 && c.rs_usage.get(i).copied().unwrap_or(0.0) > 0.93
    }

    /// Brilho das rodas: emissão no pneu e no aro (materiais compartilhados do carro).
    fn update_wheel_materials(&self, body: &Gd<VehicleBody3D>, c: Color) {
        let Some(mats) = body
            .get("assembly")
            .try_to::<Gd<Object>>()
            .ok()
            .and_then(|a| a.get("livery").try_to::<Gd<Object>>().ok())
            .and_then(|l| l.get("materials").try_to::<VarDictionary>().ok())
        else {
            return;
        };
        let pulse = self.glow * (0.85 + 0.15 * (self.time * 14.0).sin());
        let mat = |name: &str| mats.get(&Variant::from(name)).and_then(|v| v.try_to::<Gd<Material>>().ok());
        for (name, energy) in [("Tire", 1.1), ("Tire_Stripe", 9.0)] {
            if let Some(mut m) = mat(name).and_then(|m| m.try_cast::<StandardMaterial3D>().ok()) {
                m.set_feature(godot::classes::base_material_3d::Feature::EMISSION, pulse > 0.001);
                m.set_emission(c);
                m.set_emission_energy_multiplier((pulse * energy) as f32);
            }
        }
        if let Some(mut rim) = mat("Rim").and_then(|m| m.try_cast::<ShaderMaterial>().ok()) {
            rim.set_shader_parameter("glow_color", &c.to_variant());
            rim.set_shader_parameter("glow", &(pulse * 4.0).to_variant());
        }
    }

    fn update_neon(&mut self, delta: f64) {
        let enabled = self.neon_enabled;
        self.neon = move_toward(self.neon, if enabled { 1.0 } else { 0.0 }, delta * 3.0);
        let on = self.neon > 0.001;
        let (Some(mut decal), Some(mut tubes), Some(mut mat)) =
            (self.neon_decal.clone(), self.neon_tubes.clone(), self.neon_material.clone())
        else {
            return;
        };
        if self.neon_shown != Some(on) {
            self.neon_shown = Some(on);
            decal.set_visible(on);
            tubes.set_visible(on);
            for l in self.neon_lights.iter_mut() {
                l.set_visible(on);
            }
        }
        if !on {
            return;
        }
        let c = self.neon_color;
        let night = night();
        let flicker = 0.95 + 0.05 * (self.time * 50.0).sin() * (self.time * 7.3).sin();
        let level = self.neon * flicker;
        decal.set_modulate(c);
        decal.set_emission_energy((level * lerp(0.9, 4.0, night)) as f32);
        for l in self.neon_lights.iter_mut() {
            l.set_color(c);
            l.set_param(godot::classes::light_3d::Param::ENERGY, (level * lerp(0.5, 2.6, night)) as f32);
        }
        mat.set_albedo(c);
        mat.set_emission(c);
        mat.set_emission_energy_multiplier((level * lerp(1.5, 4.0, night)) as f32);
    }

    fn update_brake_light(&mut self, car: &Gd<F1CarCore>, body: &Gd<VehicleBody3D>, delta: f64) {
        let (Some(mut mat), Some(mut light), Some(mut flare_mat)) =
            (self.brake_material.clone(), self.brake_light.clone(), self.flare_material.clone())
        else {
            return;
        };
        let night = night();
        let braking = car.bind().brake_input > 0.1 && body.get_linear_velocity().length() > 2.0;
        // Pisca como na F1 (recuperação de energia): ~4 Hz, pulsos curtos
        let mut target = 0.0;
        if braking {
            target = if (self.time * 4.0) % 1.0 < 0.55 { 1.0 } else { 0.08 };
        }
        self.brake_glow = if target > self.brake_glow { target } else { move_toward(self.brake_glow, target, delta * 25.0) };
        // Só escreve nos nós e materiais quando muda (parado, era tudo de novo a cada quadro)
        let emission = (0.15 + self.brake_glow * lerp(12.0, 16.0, night)) as f32;
        let visible = self.brake_glow > 0.05 && night > 0.05;
        let energy = (self.brake_glow * night * 2.0) as f32;
        let alpha = self.brake_glow as f32;
        let now = [emission, if visible { 1.0 } else { 0.0 }, energy, alpha];
        let changed = self.brake_applied.is_none_or(|old| old.iter().zip(now.iter()).any(|(a, b)| (a - b).abs() > 1e-4));
        if changed {
            self.brake_applied = Some(now);
            mat.set_emission_energy_multiplier(emission);
            light.set_visible(visible);
            light.set_param(godot::classes::light_3d::Param::ENERGY, energy);
            flare_mat.set_albedo(Color::from_rgba(1.0, 0.12, 0.08, alpha));
        }
        if self.brake_flares.is_empty() {
            return;
        }
        let shown = self.brake_glow > 0.02;
        // Sem a asa traseira, só a lanterna central
        let mut mask = 0u32;
        for k in 0..self.brake_flares.len() {
            if shown && (k == 0 || !self.wing_gone) {
                mask |= 1 << k.min(31);
            }
        }
        if self.flares_mask != Some(mask) {
            self.flares_mask = Some(mask);
            for (k, flare) in self.brake_flares.iter_mut().enumerate() {
                flare.set_visible(mask & (1 << k.min(31)) != 0);
            }
        }
        let _ = body;
    }
}

// ---------------------------------------------------------------------------
// SlipstreamFx
// ---------------------------------------------------------------------------
const STREAKS: usize = 14;
const SEGMENTS: usize = 10;
const STREAK_WIDTH: f32 = 0.09;

/// Pista visual do vácuo do carro seguido pela câmera: ver scripts/race/slipstream_fx.gd.
#[derive(GodotClass)]
#[class(init, base=MeshInstance3D)]
pub struct SlipstreamFxCore {
    #[var]
    car: Option<Gd<F1CarCore>>,
    imesh: Option<Gd<ImmediateMesh>>,
    mat: Option<Gd<ShaderMaterial>>,
    offsets: Vec<Vector2>,
    shown: f64,
    /// A malha tem algo desenhado e a força já passada ao material (para não refazer parado).
    drawn: bool,
    strength_set: f64,
    base: Base<MeshInstance3D>,
}

#[godot_api]
impl IMeshInstance3D for SlipstreamFxCore {
    fn process(&mut self, delta: f64) {
        let (Some(mut mesh), Some(mut mat)) = (self.imesh.clone(), self.mat.clone()) else { return };
        if self.drawn {
            mesh.clear_surfaces();
            self.drawn = false;
        }
        let node: Gd<Node> = self.base().clone().upcast();
        let cam = race_camera(&node);
        let mut target = self.car.clone();
        if let Some((_, _, Some(t))) = &cam {
            target = Some(t.clone());
        }
        let Some(target) = target.filter(|t| t.is_instance_valid()) else { return };
        let target_body = target.clone().upcast::<VehicleBody3D>();
        let src = target_body
            .get("slipstream_source")
            .try_to::<Gd<VehicleBody3D>>()
            .ok()
            .filter(|s| s.is_instance_valid());
        let want = if src.is_some() { clamp(target.bind().slipstream, 0.0, 1.0) } else { 0.0 };
        self.shown = move_toward(self.shown, want, delta * 3.0);
        if self.shown != self.strength_set {
            self.strength_set = self.shown;
            mat.set_shader_parameter("strength", &self.shown.to_variant());
        }
        let Some(src) = src else { return };
        if self.shown <= 0.01 {
            return;
        }
        let a_basis = src.get_global_basis();
        let b_basis = target_body.get_global_basis();
        let start = src.get_global_position() + a_basis.col_c() * 2.6;
        let end = target_body.get_global_position() + b_basis.col_c() * 2.4;
        let to_cam = match camera_position(&node) {
            Some(p) => (p - (start + end) * 0.5).normalized(),
            None => Vector3::UP,
        };
        let qa = a_basis.get_quaternion();
        let qb = b_basis.get_quaternion();
        self.drawn = true;
        mesh.surface_begin(PrimitiveType::TRIANGLES);
        let count = (STREAKS as f64 * clamp(self.shown * 1.3, 0.3, 1.0)).ceil() as usize;
        for k in 0..count.min(self.offsets.len()) {
            let o = self.offsets[k];
            let mut pts = [Vector3::ZERO; SEGMENTS + 1];
            for (i, pt) in pts.iter_mut().enumerate() {
                let t = i as f64 / SEGMENTS as f64;
                // Sai rente ao bico, abre em volta da carroceria do carro da frente e fecha no seu
                let bulge = (clamp(t * 1.6, 0.0, 1.0) * std::f64::consts::PI).sin() * 0.6 + 0.4;
                let basis = Basis::from_quaternion(qa.slerp(qb, t as f32));
                *pt = start.lerp(end, t as f32)
                    + basis.col_a() * (o.x as f64 * bulge) as f32
                    + basis.col_b() * (o.y as f64 * (0.6 + 0.4 * bulge)) as f32;
            }
            let c = Color::from_rgba(k as f32 / STREAKS as f32, 0.0, 0.0, 1.0);
            for i in 0..SEGMENTS {
                let p0 = pts[i];
                let p1 = pts[i + 1];
                let side = (p1 - p0).cross(to_cam).normalized() * STREAK_WIDTH;
                let u0 = i as f32 / SEGMENTS as f32;
                let u1 = (i + 1) as f32 / SEGMENTS as f32;
                for (p, uv) in [
                    (p0 - side, Vector2::new(u0, 0.0)),
                    (p1 - side, Vector2::new(u1, 0.0)),
                    (p1 + side, Vector2::new(u1, 1.0)),
                    (p0 - side, Vector2::new(u0, 0.0)),
                    (p1 + side, Vector2::new(u1, 1.0)),
                    (p0 + side, Vector2::new(u0, 1.0)),
                ] {
                    mesh.surface_set_color(c);
                    mesh.surface_set_uv(uv);
                    mesh.surface_add_vertex(p);
                }
            }
        }
        mesh.surface_end();
    }
}

#[godot_api]
impl SlipstreamFxCore {
    #[func]
    fn _core_setup(&mut self, mesh: Gd<ImmediateMesh>, mat: Gd<ShaderMaterial>, offsets: PackedVector2Array) {
        self.imesh = Some(mesh);
        self.mat = Some(mat);
        self.offsets = offsets.to_vec();
    }
}
