//! Dano do carro a cada passo (base nativa do CarDamage, scripts/car/car_damage.gd): junta os
//! contatos do passo em golpes, faíscas e raspadas, e balança as peças soltas a cada quadro. O
//! amassado, a resistência das peças e os destroços (só nas batidas) continuam no GDScript (_hit).

use godot::builtin::AnyArray;
use godot::classes::gpu_particles_3d::EmitFlags;
use godot::classes::{Engine, GpuParticles3D, INode, MeshInstance3D, Node3D, VehicleBody3D};
use godot::global::{randf, randf_range};
use godot::prelude::*;

use crate::audio::CarAudioCore;
use crate::car::F1CarCore;
use crate::util::{clamp, move_toward};

/// TrackSurface.Type.BARRIER
const BARRIER: i64 = 4;

struct Contact {
    pos: Vector3,
    impulse: Vector3,
    normal: Vector3,
    collider: Option<Gd<Object>>,
    slide: f64,
}

/// Peça amassada a ponto de ficar solta (balança com o vento).
struct Loose {
    pivot: Vector3,
    axis: Vector3,
    phase: f64,
    /// 0..1 (quanto está solta)
    amount: f64,
    copies: Vec<(Gd<MeshInstance3D>, Transform3D)>,
}

#[derive(GodotClass)]
#[class(init, base=Node)]
pub struct CarDamageCore {
    /// Impulso (N·s) abaixo do qual o contato não causa dano (toques, raspadas leves).
    #[export]
    #[init(val = 550.0)]
    impulse_threshold: f64,
    /// Impulso que tira 100% de uma peça de fragilidade 1 no ponto de impacto.
    #[export]
    #[init(val = 7500.0)]
    impulse_full_damage: f64,
    /// Multiplicador geral (0 = indestrutível).
    #[export(range = (0.0, 3.0))]
    #[init(val = 1.0)]
    damage_scale: f64,
    #[var]
    scrape_level: f64,
    car: Option<Gd<F1CarCore>>,
    audio: Option<Gd<CarAudioCore>>,
    sparks: Option<Gd<GpuParticles3D>>,
    contacts: Vec<Contact>,
    prev_velocity: Vector3,
    prev_position: Vector3,
    time: f64,
    loose: Vec<Loose>,
    base: Base<Node>,
}

fn surface_of(obj: &Option<Gd<Object>>) -> i64 {
    match obj {
        Some(o) if o.has_meta("surface") => o.get_meta("surface").try_to::<i64>().unwrap_or(0),
        _ => 0,
    }
}

#[godot_api]
impl INode for CarDamageCore {
    fn physics_process(&mut self, delta: f64) {
        let Some(car) = self.car.clone() else { return };
        let body = car.clone().upcast::<VehicleBody3D>();
        let mut scrape: f64 = 0.0;
        let xf = body.get_global_transform();
        let inv = xf.affine_inverse();
        // O impulso reportado pela física às vezes vem zerado no passo da batida: estima também pela
        // variação de velocidade do carro na direção da normal do contato (Δv · n × massa).
        let v = body.get_linear_velocity();
        let dv = v - self.prev_velocity;
        let teleported = xf.origin.distance_to(self.prev_position) > 5.0
            || Engine::singleton().get_physics_frames() as i64 - car.bind().reset_frame < 3;
        self.prev_velocity = v;
        self.prev_position = xf.origin;
        let mass = body.get_mass() as f64;
        // Agrupa contatos próximos (uma batida = um golpe), na ordem em que aparecem
        let mut hits: Vec<(Vector3i, Vector3, Vector3, f64, f64)> = Vec::new();
        let contacts = std::mem::take(&mut self.contacts);
        for c in &contacts {
            let ground = c.normal.y > 0.6 && surface_of(&c.collider) != BARRIER;
            // Raspando (barreira ou assoalho no chão) em velocidade: faíscas e som
            if c.slide > 4.0 {
                scrape = scrape.max(clamp(c.slide / 30.0, 0.15, 1.0) * if ground { 0.5 } else { 1.0 });
                if randf() < 0.5 {
                    self._spark_burst(c.pos, c.normal, if ground { 2 } else { 4 }, c.slide);
                }
            }
            if teleported {
                continue;
            }
            let j = (c.impulse.length() as f64).max(mass * (dv.dot(c.normal) as f64).max(0.0));
            let threshold = self.impulse_threshold * if ground { 5.0 } else { 1.0 };
            if j > threshold && self.damage_scale > 0.0 {
                let l = inv * c.pos / 0.5;
                let key = Vector3i::new(l.x.round() as i32, l.y.round() as i32, l.z.round() as i32);
                match hits.iter_mut().find(|h| h.0 == key) {
                    Some(h) if h.3 < j => *h = (key, c.pos, c.normal, j, threshold),
                    Some(_) => {}
                    None => hits.push((key, c.pos, c.normal, j, threshold)),
                }
            }
        }
        // Contatos do mesmo golpe dividem o impulso
        let count = hits.len() as f64;
        for (_, pos, normal, j, threshold) in hits {
            let severity = (j - threshold) / self.impulse_full_damage * self.damage_scale / count.sqrt();
            let local = inv * pos;
            let dir = inv.basis * -normal;
            // A resistência, o amassado e os destroços ficam no GDScript
            self.base_mut().call(
                "_hit",
                &[local.to_variant(), dir.to_variant(), severity.to_variant(), pos.to_variant(), normal.to_variant()],
            );
        }
        self.scrape_level = move_toward(self.scrape_level, scrape, delta * 6.0);
        if self.audio.is_none() {
            self.audio = body.get_node_or_null("Audio").and_then(|a| a.try_cast::<CarAudioCore>().ok());
        }
        if let Some(mut audio) = self.audio.clone() {
            audio.bind_mut().scrape_level = self.scrape_level;
        }
    }

    fn process(&mut self, delta: f64) {
        let Some(car) = self.car.clone() else { return };
        self.time += delta;
        if self.loose.is_empty() {
            return;
        }
        let body = car.upcast::<VehicleBody3D>();
        let speed = body.get_linear_velocity().length() as f64;
        let car_inv = body.get_global_transform().affine_inverse();
        // Peças soltas caem e balançam com o vento
        for p in &self.loose {
            let droop = p.amount * 0.18
                + (self.time * (18.0 + p.phase) + p.phase).sin() * p.amount * (speed / 60.0).min(1.0) * 0.04;
            let rot = Transform3D::new(Basis::from_axis_angle(p.axis, droop as f32), Vector3::ZERO);
            // Gira em volta do ponto de fixação (espaço do carro) e volta para o espaço do pai
            let around = Transform3D::new(Basis::IDENTITY, p.pivot) * rot * Transform3D::new(Basis::IDENTITY, -p.pivot);
            for (mi, rest) in &p.copies {
                if !mi.is_instance_valid() {
                    continue;
                }
                let Some(parent) = mi.get_parent().and_then(|n| n.try_cast::<Node3D>().ok()) else { continue };
                let parent_inv = (car_inv * parent.get_global_transform()).affine_inverse();
                let mut mi = mi.clone();
                mi.set_transform(parent_inv * around * parent_inv.affine_inverse() * *rest);
            }
        }
    }
}

#[godot_api]
impl CarDamageCore {
    #[func]
    fn _core_setup(&mut self, car: Gd<F1CarCore>, sparks: Gd<GpuParticles3D>) {
        let body = car.clone().upcast::<VehicleBody3D>();
        self.prev_velocity = body.get_linear_velocity();
        self.prev_position = body.get_global_position();
        self.car = Some(car);
        self.sparks = Some(sparks);
    }

    /// Peças soltas: [ponto de fixação, eixo, fase, quanto está solta, [[cópia, pose de repouso]…]]…
    #[func]
    fn _core_set_loose(&mut self, list: AnyArray) {
        self.loose = list
            .iter_shared()
            .filter_map(|v| {
                let a = v.try_to::<VarArray>().ok()?;
                let copies = a
                    .get(4)?
                    .try_to::<VarArray>()
                    .ok()?
                    .iter_shared()
                    .filter_map(|c| {
                        let c = c.try_to::<VarArray>().ok()?;
                        Some((c.get(0)?.try_to::<Gd<MeshInstance3D>>().ok()?, c.get(1)?.try_to::<Transform3D>().ok()?))
                    })
                    .collect();
                Some(Loose {
                    pivot: a.get(0)?.try_to().ok()?,
                    axis: a.get(1)?.try_to().ok()?,
                    phase: a.get(2)?.try_to().ok()?,
                    amount: a.get(3)?.try_to().ok()?,
                    copies,
                })
            })
            .collect();
    }

    /// Chamado pelo F1Car a cada contato do corpo do carro (no passo de física).
    #[func]
    pub fn add_contact(&mut self, world_pos: Vector3, impulse: Vector3, normal: Vector3, collider: Option<Gd<Object>>, rel_speed: f64) {
        self.contacts.push(Contact { pos: world_pos, impulse, normal, collider, slide: rel_speed });
    }

    /// Faíscas (emitidas uma a uma, com velocidade espalhada em volta da normal + arrasto do carro).
    #[func]
    fn _spark_burst(&mut self, pos: Vector3, normal: Vector3, count: i64, speed: f64) {
        let (Some(car), Some(mut sparks)) = (self.car.clone(), self.sparks.clone()) else { return };
        let base = car.upcast::<VehicleBody3D>().get_linear_velocity() * 0.6;
        for _ in 0..count {
            let dir = (normal
                + Vector3::new(
                    randf_range(-1.0, 1.0) as f32,
                    randf_range(-0.2, 1.0) as f32,
                    randf_range(-1.0, 1.0) as f32,
                ))
            .normalized();
            let v = base + dir * randf_range(2.0, 4.0 + speed * 0.25) as f32;
            sparks.emit_particle(
                Transform3D::new(Basis::IDENTITY, pos),
                v,
                Color::WHITE,
                Color::WHITE,
                EmitFlags::POSITION | EmitFlags::VELOCITY,
            );
        }
    }
}
