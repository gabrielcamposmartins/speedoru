"""Gera as texturas das construções (sem emendas, 512 x 512) em assets/track/textures/.

    python tools/generate_textures.py

  * material_detail.png — grão do material (concreto/pintura): ruído fino + agregados. Cinza ~0.5.
  * grime.png          — manchas e escorridos (1 = limpo, escuro = sujo).
  * deform_normal.png  — normal map de pequenas deformidades (amassados, ondulações, poros).

O shader (shaders/track/building_common.gdshaderinc) projeta as três no espaço do objeto, em
escalas diferentes, e mistura com a cor de vértice de cada peça.
"""
import os
import zlib
import struct

import numpy as np

SIZE = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "track", "textures")
RNG = np.random.default_rng(31337)


def save_png(name, data):
    """data: float [0,1], (H, W) ou (H, W, 3). PNG sem dependências externas."""
    a = np.clip(data, 0.0, 1.0)
    a = (a * 255 + 0.5).astype(np.uint8)
    if a.ndim == 2:
        a = np.stack([a, a, a], axis=-1)
    h, w, _ = a.shape
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(tag, payload):
        c = struct.pack(">I", len(payload)) + tag + payload
        return c + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(png)


def periodic_noise(power, aniso=(1.0, 1.0), lo=0.0):
    """Ruído periódico (sem emenda) com espectro 1/f^power; aniso estica em x/y (escorridos)."""
    white = RNG.standard_normal((SIZE, SIZE))
    fy = np.fft.fftfreq(SIZE)[:, None] * aniso[1]
    fx = np.fft.fftfreq(SIZE)[None, :] * aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    gain = 1.0 / np.maximum(f, 1.0 / SIZE) ** power
    gain[f < lo] = 0.0
    gain[0, 0] = 0.0
    x = np.real(np.fft.ifft2(np.fft.fft2(white) * gain))
    x -= x.min()
    return x / x.max()


def blobs(count, r_min, r_max, sharp=2.0):
    """Manchas circulares suaves, com repetição nas bordas (tileable)."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    out = np.zeros((SIZE, SIZE))
    for _ in range(count):
        cx, cy = RNG.uniform(0, SIZE, 2)
        r = RNG.uniform(r_min, r_max)
        dx = np.minimum(np.abs(x - cx), SIZE - np.abs(x - cx))
        dy = np.minimum(np.abs(y - cy), SIZE - np.abs(y - cy))
        d = np.sqrt(dx * dx + dy * dy) / r
        out += np.exp(-d ** sharp) * RNG.uniform(0.4, 1.0)
    return out / max(out.max(), 1e-6)


def material_detail():
    fine = periodic_noise(0.6)
    mid = periodic_noise(1.4)
    # Agregados: pontinhos claros/escuros
    dots = np.zeros((SIZE, SIZE))
    idx = RNG.integers(0, SIZE, (5000, 2))
    dots[idx[:, 0], idx[:, 1]] = RNG.uniform(-1, 1, 5000)
    dots = np.real(np.fft.ifft2(np.fft.fft2(dots) * np.exp(-(np.fft.fftfreq(SIZE)[:, None] ** 2 + np.fft.fftfreq(SIZE)[None, :] ** 2) * 800)))
    dots /= np.abs(dots).max()
    v = 0.5 + (fine - 0.5) * 0.45 + (mid - 0.5) * 0.35 + dots * 0.18
    return np.clip(v, 0, 1)


def grime():
    blot = periodic_noise(2.0)
    blot = np.clip((blot - 0.45) * 2.4, 0, 1)          # manchas grandes
    streak = periodic_noise(1.6, aniso=(0.12, 1.0))   # escorridos verticais
    streak = np.clip((streak - 0.5) * 2.2, 0, 1)
    spots = blobs(40, 4, 18, 1.5)
    dirt = np.clip(blot * 0.55 + streak * 0.45 + spots * 0.35, 0, 1)
    return 1.0 - dirt * 0.85


def deform_normal(strength=1.8):
    dents = blobs(60, 10, 40, 2.0) - blobs(25, 5, 14, 2.0) * 0.4
    waves = periodic_noise(2.2)
    pores = periodic_noise(0.4)
    h = dents * 0.6 + waves * 0.5 + pores * 0.08
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    n = np.stack([-dx * strength * 40, -dy * strength * 40, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def main():
    os.makedirs(OUT, exist_ok=True)
    save_png("material_detail.png", material_detail())
    save_png("grime.png", grime())
    save_png("deform_normal.png", deform_normal())
    print("Texturas geradas em", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
