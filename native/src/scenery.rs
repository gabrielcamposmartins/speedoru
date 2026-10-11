//! Cenário em movimento a cada quadro: SceneryAnimator (turbinas, balões, dirigíveis, pássaros e
//! nuvens; scripts/track/scenery_animator.gd) e TrackOffshore (navios, balões e dirigíveis ao largo
//! de Mônaco; scripts/track/track_offshore.gd). O GDScript monta os objetos e registra aqui.

use std::collections::HashMap;
use std::f64::consts::TAU;

use godot::builtin::AnyArray;
use godot::classes::{INode3D, MultiMesh};
use godot::global::randf;
use godot::prelude::*;

use crate::util::{fposmod, looking_at, move_toward, signf};

struct Blimp {
    node: Gd<Node3D>,
    center: Vector3,
    radii: Vector2,
    speed: f64,
    angle: f64,
}

struct Flock {
    node: Gd<Node3D>,
    center: Vector3,
    radii: Vector2,
    speed: f64,
    phase: f64,
}

struct Pass {
    node: Gd<Node3D>,
    a: Vector3,
    b: Vector3,
    speed: f64,
    t: f64,
}

struct Clouds {
    mm: Gd<MultiMesh>,
    list: Vec<Transform3D>,
    center: Vector2,
    radius: f64,
}

#[derive(GodotClass)]
#[class(init, base=Node3D)]
pub struct SceneryAnimatorCore {
    /// Vento das nuvens (m/s, no plano XZ).
    #[export]
    #[init(val = Vector2::new(7.0, 4.5))]
    cloud_wind: Vector2,
    rotors: Vec<(Gd<Node3D>, f64)>,
    balloons: Vec<(Gd<Node3D>, Vector3, f64)>,
    blimps: Vec<Blimp>,
    clouds: Vec<Clouds>,
    flocks: Vec<Flock>,
    passes: Vec<Pass>,
    time: f64,
    /// TrackTerrain (opcional): dirigíveis e pássaros mantêm altura mínima sobre o relevo.
    terrain: Option<Gd<Object>>,
    /// Subida extra atual (m) de cada nó, suavizada.
    lift: HashMap<InstanceId, f64>,
    base: Base<Node3D>,
}

fn flock_pos(center: Vector3, radii: Vector2, a: f64) -> Vector3 {
    center
        + Vector3::new(
            (a.cos() * radii.x as f64) as f32,
            ((a * 2.0).sin() * 6.0) as f32,
            ((a * 0.8 + 1.3).sin() * radii.y as f64) as f32,
        )
}

#[godot_api]
impl INode3D for SceneryAnimatorCore {
    fn process(&mut self, delta: f64) {
        self.time += delta;
        let time = self.time;
        for (node, speed) in self.rotors.iter_mut() {
            node.rotate_object_local(Vector3::BACK, (*speed * delta) as f32);
        }
        for (node, base, ph) in self.balloons.iter_mut() {
            node.set_position(
                *base
                    + Vector3::new(
                        ((time * 0.05 + *ph).sin() * 60.0) as f32,
                        ((time * 0.3 + *ph).sin() * 4.0) as f32,
                        ((time * 0.04 + *ph).cos() * 60.0) as f32,
                    ),
            );
            let mut rot = node.get_rotation();
            rot.y = (time * 0.05 + *ph) as f32;
            node.set_rotation(rot);
        }
        for k in 0..self.blimps.len() {
            self.update_blimp(k, delta);
        }
        for k in 0..self.flocks.len() {
            let f = &self.flocks[k];
            let (node, center, radii, speed, ph) = (f.node.clone(), f.center, f.radii, f.speed, f.phase);
            let w = speed / ((radii.x + radii.y) as f64 * 0.5);
            let mut pos = flock_pos(center, radii, time * w + ph);
            let ahead = flock_pos(center, radii, time * w + ph + 0.02);
            let vel = ahead - pos;
            let bank = vel.normalized().cross(Vector3::UP).dot((ahead - pos).normalized()).clamp(-0.4, 0.4);
            pos.y += self.clearance(&node, pos, vel.normalized(), 14.0, delta) as f32;
            let basis = looking_at(-vel.normalized()) * Basis::from_axis_angle(Vector3::BACK, bank);
            let mut node = node;
            node.set_global_transform(Transform3D::new(basis, pos));
        }
        for k in 0..self.passes.len() {
            let pa = &mut self.passes[k];
            let length = pa.a.distance_to(pa.b) as f64;
            pa.t = fposmod(pa.t + delta * pa.speed / length, 2.0);
            let t = pa.t;
            let forward = t < 1.0;
            let u = if forward { t } else { 2.0 - t };
            let dir = (pa.b - pa.a).normalized() * if forward { 1.0 } else { -1.0 };
            let mut pos = pa.a.lerp(pa.b, u as f32) + Vector3::UP * ((time * 0.15 + length).sin() * 4.0) as f32;
            let node = pa.node.clone();
            pos.y += self.clearance(&node, pos, dir, 40.0, delta) as f32;
            let mut node = node;
            node.set_global_transform(Transform3D::new(looking_at(-dir), pos));
        }
        let drift = Vector3::new(self.cloud_wind.x, 0.0, self.cloud_wind.y) * delta as f32;
        for c in self.clouds.iter_mut() {
            for (i, t) in c.list.iter_mut().enumerate() {
                t.origin += drift;
                let mut rel = Vector2::new(t.origin.x - c.center.x, t.origin.z - c.center.y);
                if rel.length() as f64 > c.radius {
                    // Reaparece do lado de onde o vento vem
                    rel = -rel.normalized() * (c.radius * 0.98) as f32;
                    t.origin = Vector3::new(c.center.x + rel.x, t.origin.y, c.center.y + rel.y);
                }
                c.mm.set_instance_transform(i as i32, *t);
            }
        }
    }
}

#[godot_api]
impl SceneryAnimatorCore {
    #[func]
    fn add_rotor(&mut self, node: Gd<Node3D>, speed: f64) {
        self.rotors.push((node, speed));
    }

    #[func]
    fn add_balloon(&mut self, node: Gd<Node3D>, base: Vector3, phase: f64) {
        self.balloons.push((node, base, phase));
    }

    #[func]
    fn add_blimp(&mut self, node: Gd<Node3D>, center: Vector3, radii: Vector2, speed: f64) {
        self.blimps.push(Blimp { node, center, radii, speed, angle: randf() * TAU });
        let k = self.blimps.len() - 1;
        self.update_blimp(k, 0.0);
    }

    /// Bando de pássaros dando voltas (curva de Lissajous) em volta de `center`.
    #[func]
    fn add_flock(&mut self, node: Gd<Node3D>, center: Vector3, radii: Vector2, speed: f64, phase: f64) {
        self.flocks.push(Flock { node, center, radii, speed, phase });
    }

    /// Dirigível passando em linha reta de `a` até `b` e voltando (vira longe da pista).
    #[func]
    fn add_blimp_pass(&mut self, node: Gd<Node3D>, a: Vector3, b: Vector3, speed: f64, start: f64) {
        self.passes.push(Pass { node, a, b, speed, t: start });
    }

    #[func]
    fn remove_blimp(&mut self, node: Gd<Node3D>) {
        self.blimps.retain(|b| b.node != node);
    }

    #[func]
    fn add_clouds(&mut self, mm: Gd<MultiMesh>, transforms: Array<Transform3D>, center: Vector2, radius: f64) {
        self.clouds.push(Clouds { mm, list: transforms.iter_shared().collect(), center, radius });
    }

    #[func]
    fn _core_set_terrain(&mut self, terrain: Option<Gd<Object>>) {
        self.terrain = terrain;
    }
}

impl SceneryAnimatorCore {
    /// Quanto subir para ficar `margin` m acima do terreno (olhando 80 m à frente), suavizado.
    fn clearance(&mut self, node: &Gd<Node3D>, pos: Vector3, dir: Vector3, margin: f64, delta: f64) -> f64 {
        let Some(mut terrain) = self.terrain.clone() else { return 0.0 };
        let mut h = |x: f32, z: f32| terrain.call("height_at", &[x.to_variant(), z.to_variant()]).try_to::<f64>().unwrap_or(0.0);
        let ground = h(pos.x, pos.z).max(h(pos.x + dir.x * 80.0, pos.z + dir.z * 80.0));
        let need = (ground + margin - pos.y as f64).max(0.0);
        let id = node.instance_id();
        let current = self.lift.get(&id).copied().unwrap_or(need);
        let current = move_toward(current, need, delta * if need > current { 6.0 } else { 2.0 });
        self.lift.insert(id, current);
        current
    }

    fn update_blimp(&mut self, k: usize, delta: f64) {
        let time = self.time;
        let b = &mut self.blimps[k];
        // Velocidade aproximadamente constante ao longo da elipse (raio médio)
        b.angle += delta * b.speed / ((b.radii.x + b.radii.y) as f64 * 0.5);
        let ang = b.angle;
        let (rx, ry) = (b.radii.x as f64, b.radii.y as f64);
        let mut p = b.center
            + Vector3::new((ang.cos() * rx) as f32, ((time * 0.2 + ang).sin() * 6.0) as f32, (ang.sin() * ry) as f32);
        let d = signf(b.speed) * 0.01;
        let ahead = b.center + Vector3::new(((ang + d).cos() * rx) as f32, 0.0, ((ang + d).sin() * ry) as f32);
        let dir = Vector3::new(ahead.x - p.x, 0.0, ahead.z - p.z);
        if dir.length_squared() < 1e-8 {
            return;
        }
        let node = b.node.clone();
        p.y += self.clearance(&node, p, dir.normalized(), 40.0, delta) as f32;
        let mut node = node;
        node.set_global_transform(Transform3D::new(looking_at(-dir.normalized()), p));
    }
}

// ---------------------------------------------------------------------------
// TrackOffshore
// ---------------------------------------------------------------------------
/// Meia-extensão das rotas ao longo da costa (m): depois disso o navio volta para o outro lado.
const ROUTE_HALF: f64 = 7000.0;
/// Faixa que os balões percorrem ao longo da costa antes de recomeçar do outro lado (m).
const BALLOON_HALF: f64 = 1500.0;

struct Ship {
    node: Gd<Node3D>,
    wake: Gd<Node3D>,
    wake_scale: Vector3,
    base: Vector2,
    dir: Vector2,
    t: f64,
    speed: f64,
    phase: f64,
}

struct SeaBalloon {
    node: Gd<Node3D>,
    base: Vector2,
    wind: Vector2,
    t: f64,
    speed: f64,
    height: f64,
    phase: f64,
}

struct SeaBlimp {
    node: Gd<Node3D>,
    center: Vector2,
    u: Vector2,
    v: Vector2,
    radii: Vector2,
    speed: f64,
    angle: f64,
    height: f64,
}

/// TrackCity.to_world: (x, y) do mapa e altura → Godot.
fn to_world(x: f64, y: f64, h: f64) -> Vector3 {
    Vector3::new(x as f32, h as f32, -y as f32)
}

#[derive(GodotClass)]
#[class(init, base=Node3D)]
pub struct TrackOffshoreCore {
    ships: Vec<Ship>,
    balloons: Vec<SeaBalloon>,
    blimps: Vec<SeaBlimp>,
    t: f64,
    base: Base<Node3D>,
}

#[godot_api]
impl INode3D for TrackOffshoreCore {
    fn process(&mut self, delta: f64) {
        self._update(delta);
    }
}

fn item(a: &VarArray, k: usize) -> Variant {
    a.get(k).unwrap_or_default()
}

#[godot_api]
impl TrackOffshoreCore {
    /// Recebe as listas montadas pelo TrackOffshore (formato descrito lá).
    #[func]
    fn _core_setup(&mut self, ships: AnyArray, balloons: AnyArray, blimps: AnyArray) {
        let rows = |arr: &AnyArray| -> Vec<VarArray> { arr.iter_shared().filter_map(|v| v.try_to::<VarArray>().ok()).collect() };
        self.ships = rows(&ships)
            .iter()
            .filter_map(|a| {
                let wake = item(a, 1).try_to::<Gd<Node3D>>().ok()?;
                Some(Ship {
                    node: item(a, 0).try_to().ok()?,
                    wake_scale: wake.get_meta("scale").try_to().unwrap_or(Vector3::ONE),
                    wake,
                    base: item(a, 2).try_to().ok()?,
                    dir: item(a, 3).try_to().ok()?,
                    t: item(a, 4).try_to().ok()?,
                    speed: item(a, 5).try_to().ok()?,
                    phase: item(a, 6).try_to().ok()?,
                })
            })
            .collect();
        self.balloons = rows(&balloons)
            .iter()
            .filter_map(|a| {
                Some(SeaBalloon {
                    node: item(a, 0).try_to().ok()?,
                    base: item(a, 1).try_to().ok()?,
                    wind: item(a, 2).try_to().ok()?,
                    t: item(a, 3).try_to().ok()?,
                    speed: item(a, 4).try_to().ok()?,
                    height: item(a, 5).try_to().ok()?,
                    phase: item(a, 6).try_to().ok()?,
                })
            })
            .collect();
        self.blimps = rows(&blimps)
            .iter()
            .filter_map(|a| {
                Some(SeaBlimp {
                    node: item(a, 0).try_to().ok()?,
                    center: item(a, 1).try_to().ok()?,
                    u: item(a, 2).try_to().ok()?,
                    v: item(a, 3).try_to().ok()?,
                    radii: item(a, 4).try_to().ok()?,
                    speed: item(a, 5).try_to().ok()?,
                    angle: item(a, 6).try_to().ok()?,
                    height: item(a, 7).try_to().ok()?,
                })
            })
            .collect();
    }

    #[func]
    fn _update(&mut self, delta: f64) {
        self.t += delta;
        let t = self.t;
        for sh in self.ships.iter_mut() {
            sh.t += sh.speed * delta;
            if sh.t > ROUTE_HALF {
                sh.t = -ROUTE_HALF;
            }
            let p = sh.base + sh.dir * sh.t as f32;
            let heading = (sh.dir.y as f64).atan2(sh.dir.x as f64) as f32;
            // Balanço leve no mar
            let basis = Basis::from_axis_angle(Vector3::UP, heading)
                * Basis::from_axis_angle(Vector3::RIGHT, ((t * 0.35 + sh.phase).sin() * 0.012) as f32);
            let pos = to_world(p.x as f64, p.y as f64, (t * 0.5 + sh.phase).sin() * 0.25);
            sh.node.set_transform(Transform3D::new(basis, pos));
            sh.wake.set_transform(Transform3D::new(
                Basis::from_axis_angle(Vector3::UP, heading).scaled(sh.wake_scale),
                to_world(p.x as f64, p.y as f64, 0.12),
            ));
        }
        for b in self.balloons.iter_mut() {
            b.t += b.speed * delta;
            if b.t > BALLOON_HALF {
                b.t = -BALLOON_HALF;
            }
            let p = b.base + b.wind * b.t as f32 + Vector2::new(-b.wind.y, b.wind.x) * ((t * 0.02 + b.phase).sin() * 60.0) as f32;
            b.node.set_position(to_world(p.x as f64, p.y as f64, b.height + (t * 0.25 + b.phase).sin() * 6.0));
            let mut rot = b.node.get_rotation();
            rot.y = (t * 0.03 + b.phase) as f32;
            b.node.set_rotation(rot);
        }
        for bl in self.blimps.iter_mut() {
            // Velocidade ~constante ao longo da elipse (raio médio)
            bl.angle += delta * bl.speed / ((bl.radii.x + bl.radii.y) as f64 * 0.5);
            let ang = bl.angle;
            let (c, s) = (ang.cos() as f32, ang.sin() as f32);
            let p = bl.center + bl.u * c * bl.radii.x + bl.v * s * bl.radii.y;
            let tangent = (-bl.u * s * bl.radii.x + bl.v * c * bl.radii.y) * signf(bl.speed) as f32;
            let pos = to_world(p.x as f64, p.y as f64, bl.height + (t * 0.2 + ang).sin() * 5.0);
            let dir = to_world(tangent.x as f64, tangent.y as f64, 0.0).normalized();
            bl.node.set_global_transform(Transform3D::new(looking_at(-dir), pos));
        }
    }
}
