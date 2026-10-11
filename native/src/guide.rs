//! Linha ideal no chão a cada quadro (base nativa do RacingLineGuide,
//! scripts/race/racing_line_guide.gd): posição e cor das setas pela velocidade ideal.

use std::collections::HashMap;

use godot::classes::{IMultiMeshInstance3D, MultiMeshInstance3D, PhysicsRayQueryParameters3D, RigidBody3D, VehicleBody3D};
use godot::prelude::*;

use crate::car::F1CarCore;
use crate::path::LineCore;
use crate::util::{clamp, fposmod};

const COUNT: i32 = 48;
const SPACING: f64 = 7.0;
const START: f64 = 9.0;
const LIFT: f32 = 0.025;
const GLOW: f32 = 2.4;

#[derive(GodotClass)]
#[class(init, base=MultiMeshInstance3D)]
pub struct RacingLineGuideCore {
    /// 0 desligada, 1 só nas frenagens e curvas, 2 completa.
    #[var]
    #[init(val = 2)]
    mode: i64,
    /// Escondida por fora (apresentação antes da largada).
    #[var]
    suppressed: bool,
    car: Option<Gd<F1CarCore>>,
    line: Option<Gd<LineCore>>,
    profile: Vec<f32>,
    /// Altura do asfalto em relação à linha (m), por metro de pista.
    ground_dy: HashMap<i64, f32>,
    base: Base<MultiMeshInstance3D>,
}

fn speed_color(v: f64, ideal: f64) -> Color {
    let diff = v - ideal;
    let green = Color::from_rgba(0.1, 1.0, 0.35, 0.92);
    let yellow = Color::from_rgba(1.0, 0.8, 0.0, 0.95);
    let red = Color::from_rgba(1.0, 0.08, 0.1, 0.95);
    if diff < -6.0 {
        green
    } else if diff < 0.0 {
        green.lerp(yellow, (diff + 6.0) / 6.0)
    } else if diff < 5.0 {
        yellow.lerp(red, diff / 5.0)
    } else {
        red
    }
}

#[godot_api]
impl IMultiMeshInstance3D for RacingLineGuideCore {
    fn process(&mut self, _delta: f64) {
        let (Some(car), Some(line)) = (self.car.clone(), self.line.clone()) else { return };
        let Some(mut mm) = self.base().get_multimesh() else { return };
        let visible = self.mode > 0 && !self.suppressed;
        self.base_mut().set_visible(visible);
        if !visible {
            return;
        }
        let body = car.clone().upcast::<VehicleBody3D>();
        let line = line.bind();
        let path_gd = line.path.clone().expect("linha sem pista");
        let path = path_gd.bind();
        // Posição do carro ao longo da pista; as setas começam alguns metros à frente
        let s0 = path.project_pos(body.get_global_position(), true, true).x as f64;
        let v = body.get_linear_velocity().length() as f64;
        for k in 0..COUNT {
            let s = s0 + START + k as f64 * SPACING;
            let ideal = path.sample_arr(&self.profile, s);
            let p0 = path.position(s, line.lateral_at_s(&path, s));
            let p1 = path.position(s + 1.0, line.lateral_at_s(&path, s + 1.0));
            let mut fwd = p1 - p0;
            fwd.y = 0.0;
            if fwd.length_squared() < 1e-6 {
                fwd = Vector3::FORWARD;
            }
            fwd = fwd.normalized();
            let basis = Basis::from_cols(Vector3::UP.cross(fwd).normalized(), Vector3::UP, fwd);
            let key = fposmod(s, path.length) as i64;
            let ground = self.ground_at(&body, key, p0);
            let xf = Transform3D::new(basis, ground + Vector3::UP * LIFT);
            let mut col = speed_color(v, ideal);
            // Some suave perto do carro e no fim da linha
            let mut fade = clamp(k as f64 / 3.0, 0.0, 1.0) * clamp((COUNT - k) as f64 / 12.0, 0.0, 1.0);
            if self.mode == 1 {
                // Só nas frenagens e curvas: onde a velocidade ideal cai ou a curvatura é alta
                let before = path.sample_arr(&self.profile, s - 60.0);
                let matters = before - ideal > 4.0 || path.sample_arr(&line.curvature, s).abs() > 1.0 / 450.0;
                if !matters {
                    fade = 0.0;
                }
            }
            col.a *= fade as f32;
            // Cor em HDR (acima de 1) para atravessar o tonemap sem ficar pálida
            let col = Color::from_rgba(col.r * GLOW, col.g * GLOW, col.b * GLOW, col.a);
            mm.set_instance_transform(k, xf);
            mm.set_instance_color(k, col);
        }
    }
}

#[godot_api]
impl RacingLineGuideCore {
    #[func]
    fn _core_setup(&mut self, car: Gd<F1CarCore>, line: Gd<LineCore>, profile: PackedFloat32Array) {
        self.car = Some(car);
        self.line = Some(line);
        self.profile = profile.to_vec();
    }
}

impl RacingLineGuideCore {
    /// Ponto no asfalto (a linha central do traçado não acompanha o relevo da pista), pelo cache por
    /// metro de pista; só guarda o que bateu no cenário (não em outro carro passando por ali).
    fn ground_at(&mut self, body: &Gd<VehicleBody3D>, key: i64, p: Vector3) -> Vector3 {
        if let Some(dy) = self.ground_dy.get(&key) {
            return p + Vector3::UP * *dy;
        }
        let Some(mut space) = body.get_world_3d().and_then(|w| w.get_direct_space_state()) else { return p };
        let Some(mut q) = PhysicsRayQueryParameters3D::create(p + Vector3::UP * 4.0, p + Vector3::DOWN * 4.0) else {
            return p;
        };
        let mut exclude = Array::<Rid>::new();
        exclude.push(body.get_rid());
        q.set_exclude(&exclude);
        let hit = space.intersect_ray(&q);
        let Some(pos) = hit.get(&Variant::from("position")).and_then(|v| v.try_to::<Vector3>().ok()) else {
            self.ground_dy.insert(key, 0.0);
            return p;
        };
        let moving = hit
            .get(&Variant::from("collider"))
            .and_then(|c| c.try_to::<Gd<Object>>().ok())
            .is_some_and(|c| c.try_cast::<RigidBody3D>().is_ok());
        if !moving {
            self.ground_dy.insert(key, pos.y - p.y);
        }
        pos
    }
}
