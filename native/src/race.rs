//! Partes do RaceManager que rodam a cada passo de física e comparam todos os carros entre si.

use godot::builtin::AnyArray;
use godot::prelude::*;

use crate::car::F1CarCore;
use crate::util::{move_toward, smoothstep};

// Vácuo (os mesmos valores de scripts/race/slipstream.gd)
const NEAR: f64 = 3.0;
const FULL: f64 = 14.0;
const FAR: f64 = 42.0;
const CORE: f64 = 0.9;
const SPREAD: f64 = 0.025;
const EDGE: f64 = 1.1;
const MIN_SPEED: f64 = 22.0;
const RATE: f64 = 2.5;

#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct RaceNative {}

struct CarState {
    car: Gd<F1CarCore>,
    xf: Transform3D,
    speed: f64,
}

#[godot_api]
impl RaceNative {
    /// Atualiza o vácuo de todos os carros (com suavização) — Slipstream.update_all.
    #[func]
    fn update_slipstream(cars: AnyArray, delta: f64) {
        let states: Vec<CarState> = cars
            .iter_shared()
            .filter_map(|v| v.try_to::<Gd<F1CarCore>>().ok())
            .map(|car| {
                let body = car.clone().upcast::<Node3D>();
                let speed = car.clone().upcast::<godot::classes::RigidBody3D>().get_linear_velocity().length() as f64;
                CarState { xf: body.get_global_transform(), speed, car }
            })
            .collect();
        for (k, me) in states.iter().enumerate() {
            let (best, src) = source_for(&states, k);
            let mut car = me.car.clone();
            let (slip, written) = {
                let mut c = car.bind_mut();
                c.slipstream = move_toward(c.slipstream, best, delta * RATE);
                (c.slipstream, c.slip_src)
            };
            // A propriedade do GDScript só é escrita quando muda (era em quase todo carro a cada passo)
            match src {
                Some(o) => {
                    let id = states[o].car.instance_id();
                    if written != Some(id) {
                        car.set("slipstream_source", &states[o].car.to_variant());
                        car.bind_mut().slip_src = Some(id);
                    }
                }
                None if slip <= 0.0 => {
                    if written.is_some() {
                        car.set("slipstream_source", &Variant::nil());
                        car.bind_mut().slip_src = None;
                    }
                }
                None => {}
            }
        }
    }
}

/// (força 0..1, índice do carro que dá o vácuo).
fn source_for(states: &[CarState], k: usize) -> (f64, Option<usize>) {
    let me = &states[k];
    if me.speed < MIN_SPEED {
        return (0.0, None);
    }
    let mut best = 0.0;
    let mut src = None;
    for (j, other) in states.iter().enumerate() {
        if j == k || other.speed < MIN_SPEED * 0.8 {
            continue;
        }
        let b = other.xf.basis;
        let rel = me.xf.origin - other.xf.origin;
        let behind = -(rel.dot(b.col_c()) as f64);
        if !(NEAR..=FAR).contains(&behind) {
            continue;
        }
        // Mesmo sentido (não vale para quem vem na contramão)
        if (me.xf.basis.col_c().dot(b.col_c()) as f64) < 0.7 {
            continue;
        }
        let lateral = (rel.dot(b.col_a()) as f64).abs();
        let width = CORE + SPREAD * behind;
        let side = 1.0 - smoothstep(width, width + EDGE, lateral);
        let along = smoothstep(NEAR, NEAR + 1.5, behind) * (1.0 - smoothstep(FULL, FAR, behind));
        if side * along > best {
            best = side * along;
            src = Some(j);
        }
    }
    (best, src)
}
