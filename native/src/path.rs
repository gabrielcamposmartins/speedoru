//! Cópia nativa da TrackPath e da RacingLine (só leitura, feita depois de montadas): projeção na
//! pista, posição/direção num ponto e amostragem de perfis. O GDScript (track_path.gd,
//! racing_line.gd) continua montando os dados e passa a chamar estas funções; os bots em Rust usam
//! direto.

use std::collections::HashMap;

use godot::prelude::*;

use crate::util::{fposmod, posmod};

const GRID_CELL: f32 = 40.0;

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct PathCore {
    pub points: Vec<Vector3>,
    pub tangents: Vec<Vector3>,
    pub lefts: Vec<Vector3>,
    pub width_left: Vec<f32>,
    pub width_right: Vec<f32>,
    pub curvature: Vec<f32>,
    pub spacing: f64,
    pub length: f64,
    cross_zone: Vec<bool>,
    has_crossings: bool,
    grid: HashMap<(i32, i32), Vec<usize>>,
}

impl PathCore {
    pub fn index_at_s(&self, s: f64) -> usize {
        posmod((s / self.spacing).round() as i64, self.points.len() as i64) as usize
    }

    pub fn wrap_index(&self, i: i64) -> usize {
        posmod(i, self.points.len() as i64) as usize
    }

    pub fn half_width_at(&self, i: usize, side: i64) -> f64 {
        if side > 0 {
            self.width_left[i] as f64
        } else {
            self.width_right[i] as f64
        }
    }

    /// Distância à frente (com sinal, entre -L/2 e L/2) de `target_s` a partir de `s`.
    pub fn ahead(&self, target_s: f64, s: f64) -> f64 {
        fposmod(target_s - s + self.length * 0.5, self.length) - self.length * 0.5
    }

    pub fn position(&self, s: f64, lateral: f64) -> Vector3 {
        let n = self.points.len();
        let f = fposmod(s, self.length) / self.spacing;
        let i = f.floor() as i64;
        let t = f - i as f64;
        let i0 = (i as usize) % n;
        let i1 = (i as usize + 1) % n;
        let lat = lateral as f32;
        let a = self.points[i0] + self.lefts[i0] * lat;
        let b = self.points[i1] + self.lefts[i1] * lat;
        a.lerp(b, t as f32)
    }

    pub fn tangent(&self, s: f64) -> Vector3 {
        let n = self.points.len();
        let f = fposmod(s, self.length) / self.spacing;
        let i = f.floor() as i64;
        let t = f - i as f64;
        let a = self.tangents[(i as usize) % n];
        let b = self.tangents[(i as usize + 1) % n];
        a.slerp(b, t as f32).normalized()
    }

    pub fn frame(&self, s: f64, lateral: f64, height: f64) -> Transform3D {
        let fwd = self.tangent(s);
        let left = Vector3::new(fwd.z, 0.0, -fwd.x).normalized();
        let up = fwd.cross(left);
        Transform3D::new(Basis::from_cols(left, up, fwd), self.position(s, lateral) + up * height as f32)
    }

    /// Valor de um perfil por amostra (velocidade, curvatura…) interpolado em s.
    pub fn sample_arr(&self, arr: &[f32], s: f64) -> f64 {
        let n = arr.len();
        if n == 0 {
            return 0.0;
        }
        let f = fposmod(s, self.length) / self.spacing;
        let i = f.floor() as i64;
        let t = f - i as f64;
        let a = arr[(i as usize) % n] as f64;
        let b = arr[(i as usize + 1) % n] as f64;
        a + (b - a) * t
    }

    fn height_penalty(dy: f64) -> f64 {
        let e = (dy.abs() - 2.5).max(0.0) * 6.0;
        e * e
    }

    pub fn project_pos(&self, pos: Vector3, exhaustive: bool, use_height: bool) -> Vector2 {
        let height = use_height && self.has_crossings;
        let kx = (pos.x / GRID_CELL).floor() as i32;
        let kz = (pos.z / GRID_CELL).floor() as i32;
        let mut best: i64 = -1;
        let mut best_d = f64::INFINITY;
        let dist = |i: usize| -> f64 {
            let p = self.points[i];
            let mut d = Vector2::new(p.x - pos.x, p.z - pos.z).length_squared() as f64;
            if height && self.cross_zone[i] {
                d += Self::height_penalty((pos.y - p.y) as f64);
            }
            d
        };
        for r in 0..3i32 {
            for dx in -r..=r {
                for dz in -r..=r {
                    if dx.abs().max(dz.abs()) != r {
                        continue;
                    }
                    if let Some(cell) = self.grid.get(&(kx + dx, kz + dz)) {
                        for &i in cell {
                            let d = dist(i);
                            if d < best_d {
                                best_d = d;
                                best = i as i64;
                            }
                        }
                    }
                }
            }
            if best >= 0 && best_d.sqrt() < (GRID_CELL * r as f32) as f64 {
                break;
            }
        }
        if best < 0 && !exhaustive {
            return Vector2::new(-1.0, f32::INFINITY);
        }
        if best < 0 {
            for i in 0..self.points.len() {
                let d = dist(i);
                if d < best_d {
                    best_d = d;
                    best = i as i64;
                }
            }
        }
        let b = best as usize;
        let rel = pos - self.points[b];
        let along = rel.dot(self.tangents[b]) as f64;
        Vector2::new(
            fposmod(b as f64 * self.spacing + along, self.length) as f32,
            rel.dot(self.lefts[b]),
        )
    }
}

#[godot_api]
impl PathCore {
    /// Copia os dados de uma TrackPath já montada.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn setup(
        &mut self,
        points: PackedVector3Array,
        tangents: PackedVector3Array,
        lefts: PackedVector3Array,
        width_left: PackedFloat32Array,
        width_right: PackedFloat32Array,
        curvature: PackedFloat32Array,
        spacing: f64,
        length: f64,
        cross_zone: PackedByteArray,
        has_crossings: bool,
    ) {
        self.points = points.to_vec();
        self.tangents = tangents.to_vec();
        self.lefts = lefts.to_vec();
        self.width_left = width_left.to_vec();
        self.width_right = width_right.to_vec();
        self.curvature = curvature.to_vec();
        self.spacing = spacing;
        self.length = length;
        self.cross_zone = cross_zone.as_slice().iter().map(|&b| b != 0).collect();
        self.cross_zone.resize(self.points.len(), false);
        self.has_crossings = has_crossings;
        self.grid.clear();
        for (i, p) in self.points.iter().enumerate() {
            let key = ((p.x / GRID_CELL).floor() as i32, (p.z / GRID_CELL).floor() as i32);
            self.grid.entry(key).or_default().push(i);
        }
    }

    #[func]
    fn project(&self, pos: Vector3, exhaustive: bool, use_height: bool) -> Vector2 {
        self.project_pos(pos, exhaustive, use_height)
    }

    #[func]
    fn project_near(&self, pos: Vector3, s0: f64, reach: f64) -> Vector2 {
        let i0 = self.index_at_s(s0) as i64;
        let k = (reach / self.spacing) as i64;
        let mut best = i0 as usize;
        let mut best_d = f64::INFINITY;
        for d in -k..=k {
            let i = self.wrap_index(i0 + d);
            let p = self.points[i];
            let dd = Vector2::new(p.x - pos.x, p.z - pos.z).length_squared() as f64;
            if dd < best_d {
                best_d = dd;
                best = i;
            }
        }
        let rel = pos - self.points[best];
        Vector2::new(
            fposmod(best as f64 * self.spacing + rel.dot(self.tangents[best]) as f64, self.length) as f32,
            rel.dot(self.lefts[best]),
        )
    }

    #[func]
    fn position_at(&self, s: f64, lateral: f64) -> Vector3 {
        self.position(s, lateral)
    }

    #[func]
    fn tangent_at(&self, s: f64) -> Vector3 {
        self.tangent(s)
    }

    #[func]
    fn frame_at(&self, s: f64, lateral: f64, height: f64) -> Transform3D {
        self.frame(s, lateral, height)
    }

    #[func]
    fn sample(&self, arr: PackedFloat32Array, s: f64) -> f64 {
        self.sample_arr(arr.as_slice(), s)
    }
}

/// Linha de corrida (deslocamento lateral e curvatura por amostra da pista).
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct LineCore {
    pub path: Option<Gd<PathCore>>,
    pub lateral: Vec<f32>,
    pub curvature: Vec<f32>,
}

impl LineCore {
    pub fn lateral_at_s(&self, p: &PathCore, s: f64) -> f64 {
        p.sample_arr(&self.lateral, s)
    }
}

#[godot_api]
impl LineCore {
    #[func]
    fn setup(&mut self, path: Gd<PathCore>, lateral: PackedFloat32Array, curvature: PackedFloat32Array) {
        self.path = Some(path);
        self.lateral = lateral.to_vec();
        self.curvature = curvature.to_vec();
    }

    #[func]
    fn lateral_at(&self, s: f64) -> f64 {
        let p = self.path.as_ref().expect("LineCore sem pista").bind();
        self.lateral_at_s(&p, s)
    }

    #[func]
    fn position_at(&self, s: f64, extra_lateral: f64) -> Vector3 {
        let p = self.path.as_ref().expect("LineCore sem pista").bind();
        p.position(s, self.lateral_at_s(&p, s) + extra_lateral)
    }
}
