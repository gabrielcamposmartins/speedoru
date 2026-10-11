//! Tabelas dos pisos, lidas uma vez das constantes de scripts/track/track_surface.gd (a fonte é o
//! GDScript; aqui só se copia).

use std::sync::OnceLock;

use godot::classes::Script;
use godot::prelude::*;

pub const ASPHALT: i32 = 0;
pub const KERB: i32 = 1;
pub const GRASS: i32 = 2;
pub const GRAVEL: i32 = 3;

pub struct Tables {
    pub grip: Vec<f64>,
    pub side_grip: Vec<f64>,
    pub drag: Vec<f64>,
    pub rumble: Vec<f64>,
}

static TABLES: OnceLock<Tables> = OnceLock::new();

fn floats(map: &VarDictionary, key: &str, fallback: &[f64]) -> Vec<f64> {
    match map.get(&Variant::from(key)).and_then(|v| v.try_to::<VarArray>().ok()) {
        Some(arr) => arr.iter_shared().map(|v| v.try_to::<f64>().unwrap_or(0.0)).collect(),
        None => {
            godot_warn!("speedoru_native: TrackSurface.{key} não encontrado; usando os valores padrão");
            fallback.to_vec()
        }
    }
}

pub fn tables() -> &'static Tables {
    TABLES.get_or_init(|| {
        let map = try_load::<Script>("res://scripts/track/track_surface.gd")
            .map(|s| s.get_script_constant_map())
            .unwrap_or_default();
        Tables {
            grip: floats(&map, "GRIP", &[1.0, 0.9, 0.55, 0.5, 0.6, 0.97]),
            side_grip: floats(&map, "SIDE_GRIP", &[1.0, 1.0, 0.7, 0.66, 1.0, 1.0]),
            drag: floats(&map, "DRAG", &[0.0, 0.004, 0.025, 0.16, 0.0, 0.0]),
            rumble: floats(&map, "RUMBLE", &[0.0, 2.5, 0.6, 3.5, 0.0, 0.2]),
        }
    })
}

/// Piso de um corpo (metadado "surface"; sem ele, asfalto) — como TrackSurface.of_body.
pub fn of_body(body: Option<Gd<Node3D>>) -> i32 {
    match body {
        Some(b) if b.has_meta("surface") => b.get_meta("surface").try_to::<i64>().unwrap_or(0) as i32,
        _ => ASPHALT,
    }
}

pub fn at(table: &[f64], surface: i32) -> f64 {
    table.get(surface as usize).copied().unwrap_or(0.0)
}
