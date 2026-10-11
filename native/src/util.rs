//! Funções de matemática com a mesma semântica das do GDScript (@GlobalScope).

pub fn fposmod(x: f64, m: f64) -> f64 {
    let mut v = x % m;
    if (v < 0.0 && m > 0.0) || (v > 0.0 && m < 0.0) {
        v += m;
    }
    v
}

pub fn posmod(a: i64, b: i64) -> i64 {
    let mut v = a % b;
    if (v < 0 && b > 0) || (v > 0 && b < 0) {
        v += b;
    }
    v
}

pub fn lerp(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

pub fn clamp(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo {
        lo
    } else if x > hi {
        hi
    } else {
        x
    }
}

pub fn move_toward(from: f64, to: f64, delta: f64) -> f64 {
    if (to - from).abs() <= delta {
        to
    } else {
        from + (to - from).signum() * delta
    }
}

fn is_equal_approx(a: f64, b: f64) -> bool {
    if a == b {
        return true;
    }
    let tolerance = (1e-5 * a.abs()).max(1e-5);
    (a - b).abs() < tolerance
}

pub fn smoothstep(from: f64, to: f64, x: f64) -> f64 {
    if is_equal_approx(from, to) {
        if from <= to {
            return if x <= from { 0.0 } else { 1.0 };
        }
        return if x <= to { 1.0 } else { 0.0 };
    }
    let s = clamp((x - from) / (to - from), 0.0, 1.0);
    s * s * (3.0 - 2.0 * s)
}

/// signf do GDScript: 0 para 0 (o signum do Rust dá ±1).
pub fn signf(x: f64) -> f64 {
    if x > 0.0 {
        1.0
    } else if x < 0.0 {
        -1.0
    } else {
        0.0
    }
}

/// Basis.looking_at(target) do Godot (up = +Y, frente do modelo em -Z).
pub fn looking_at(target: godot::builtin::Vector3) -> godot::builtin::Basis {
    use godot::builtin::{Basis, Vector3};
    let z = -target.normalized();
    let x = Vector3::UP.cross(z).normalized();
    let y = z.cross(x);
    Basis::from_cols(x, y, z)
}
