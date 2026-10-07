"""Sons da plateia (sintetizados, sem gravações) em assets/audio/crowd/:

  * crowd_murmur.wav   loop de 10 s: dezenas de vozes "conversando" (fonte vozeada com formantes,
                       sílabas irregulares), chão de ruído e eco de estádio; emenda sem estalo.
  * crowd_cheer_1/2    torcida: muitas vozes num "aaah" que sobe e cai, com alguns assobios.
  * applause_1/2       palmas: centenas de palmas aleatórias que crescem e somem.

Rodar:  python tools/generate_crowd_sounds.py
"""

import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "crowd")


def save(name, x, rms=0.12):
    x = np.asarray(x, dtype=np.float64)
    x -= x.mean()
    x *= rms / max(np.sqrt(np.mean(x * x)), 1e-9)
    x = np.tanh(x / 0.9) * 0.9
    data = (np.clip(x, -1.0, 1.0) * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def spectrum(x, gain_fn):
    spec = np.fft.rfft(x)
    f = np.maximum(np.fft.rfftfreq(len(x), 1.0 / SR), 1e-3)
    return np.fft.irfft(spec * gain_fn(f), len(x))


def band(f, lo, hi, order=2.0):
    hp = 1.0 / np.sqrt(1.0 + (lo / f) ** (2 * order)) if lo > 0 else 1.0
    lp = 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order)) if hi > 0 else 1.0
    return hp * lp


def formants(f, peaks):
    """Ganho com picos de formante [(freq, largura, ganho)] sobre uma base."""
    g = np.full_like(f, 0.15)
    for fc, bw, amp in peaks:
        g += amp / (1.0 + ((f - fc) / bw) ** 2)
    return g


def voiced(n, f0, rng, glide=0.0, harmonics=14):
    """Fonte vozeada (dente de serra com poucos harmônicos) com jitter e glide de pitch."""
    t = np.arange(n) / SR
    jitter = np.cumsum(rng.standard_normal(n)) * 0.00004
    freq = f0 * (1.0 + glide * np.clip(t / (n / SR), 0, 1) + jitter)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    x = np.zeros(n)
    for h in range(1, harmonics + 1):
        x += np.sin(h * phase) / h
    return x


def syllables(n, rng, rate=(0.12, 0.32), gap=(0.04, 0.45), pause=0.12):
    """Envelope de fala: sílabas suaves com tamanhos e pausas irregulares."""
    env = np.zeros(n)
    i = int(rng.uniform(0, 0.5) * SR)
    while i < n:
        if rng.random() < pause:
            i += int(rng.uniform(0.4, 1.2) * SR)  # fim de frase
            continue
        m = int(rng.uniform(*rate) * SR)
        w = np.hanning(m) * rng.uniform(0.4, 1.0)
        size = min(m, n - i)
        env[i:i + size] = np.maximum(env[i:i + size], w[:size])
        i += m + int(rng.uniform(*gap) * SR)
    return env


def reverb(x, seconds=0.7, mix=0.35, rng=None):
    """Eco de estádio: convolução com ruído decaindo (IR sintética)."""
    rng = rng or np.random.default_rng(1)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t / (seconds / 4.0))
    ir = spectrum(ir, lambda f: band(f, 150, 4000))
    ir /= np.sqrt(np.sum(ir * ir))
    size = len(x) + n
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return x * (1 - mix) + wet * mix * np.sqrt(np.mean(x * x)) / max(np.sqrt(np.mean(wet * wet)), 1e-9)


def crowd_murmur(seconds=10.0, voices=70):
    rng = np.random.default_rng(31)
    fade = 1.0
    n = int((seconds + fade) * SR)
    x = np.zeros(n)
    for v in range(voices):
        f0 = rng.uniform(95, 260)
        src = voiced(n, f0, rng)
        x += src * syllables(n, rng) * rng.uniform(0.3, 1.0)
    # Formantes médios de fala (vários vogais misturados) e só a faixa de voz
    x = spectrum(x, lambda f: formants(f, [(500, 180, 1.0), (1100, 300, 0.7), (2300, 500, 0.35)]) * band(f, 130, 3500))
    x /= np.sqrt(np.mean(x * x))
    floor = spectrum(rng.standard_normal(n), lambda f: band(f, 100, 1800) / np.sqrt(f))
    x += floor / np.sqrt(np.mean(floor * floor)) * 0.25
    x = reverb(x, 0.8, 0.4, rng)
    # Loop sem emenda: o último segundo entra por cima do começo
    m = int(fade * SR)
    out = x[: n - m].copy()
    ramp = np.linspace(0, 1, m)
    out[:m] = out[:m] * ramp + x[n - m:] * (1 - ramp)
    return out


def crowd_cheer(variant):
    rng = np.random.default_rng(100 + variant)
    seconds = 3.6
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for v in range(110):
        f0 = rng.uniform(150, 420)
        src = voiced(n, f0, rng, glide=rng.uniform(0.05, 0.22), harmonics=10)
        start = rng.uniform(0.0, 0.5)
        attack = rng.uniform(0.15, 0.45)
        end = rng.uniform(1.8, 3.0)
        env = np.clip((t - start) / attack, 0, 1) * np.exp(-np.clip(t - end, 0, None) / 0.35)
        x += src * env * rng.uniform(0.4, 1.0)
    vowel = [(750, 200, 1.0), (1200, 280, 0.75), (2600, 500, 0.3)] if variant == 1 else [(450, 160, 1.0), (850, 220, 0.8), (2400, 500, 0.25)]
    x = spectrum(x, lambda f: formants(f, vowel) * band(f, 140, 4000))
    x /= np.sqrt(np.mean(x * x))
    # Assobios
    for k in range(3 if variant == 1 else 2):
        s = rng.uniform(0.3, 1.6)
        d = rng.uniform(0.5, 1.0)
        i0, i1 = int(s * SR), int(min(s + d, seconds) * SR)
        tt = np.arange(i1 - i0) / SR
        fw = rng.uniform(2000, 3000) * (1 + 0.06 * np.sin(2 * np.pi * rng.uniform(4, 7) * tt) + 0.15 * tt / d)
        x[i0:i1] += np.sin(2 * np.pi * np.cumsum(fw) / SR) * np.hanning(i1 - i0) * 0.35
    floor = spectrum(rng.standard_normal(n), lambda f: band(f, 200, 3000))
    x += floor / np.sqrt(np.mean(floor * floor)) * 0.3 * np.clip(t / 0.5, 0, 1) * np.exp(-np.clip(t - 2.4, 0, None) / 0.5)
    return reverb(x, 0.9, 0.4, rng)


def applause(variant):
    rng = np.random.default_rng(200 + variant)
    seconds = 4.0
    n = int(seconds * SR)
    t = np.arange(n) / SR
    density = 650.0 * np.clip(t / 0.35, 0, 1) * np.exp(-np.clip(t - (1.6 if variant == 1 else 2.2), 0, None) / 0.55)
    x = np.zeros(n)
    # Quatro "tipos de mão" (palmas mais secas ou mais cheias), cada um um filtro diferente
    for g in range(4):
        impulses = (rng.random(n) < density / SR / 4.0) * rng.uniform(0.3, 1.0, n)
        k_len = int(0.03 * SR)
        kt = np.arange(k_len) / SR
        kernel = rng.standard_normal(k_len) * np.exp(-kt / rng.uniform(0.004, 0.009))
        center = rng.uniform(900, 2400)
        kernel = spectrum(kernel, lambda f: band(f, center * 0.5, center * 2.2, 1.5))
        size = n + k_len
        x += np.fft.irfft(np.fft.rfft(impulses, size) * np.fft.rfft(kernel, size), size)[:n]
    x = spectrum(x, lambda f: band(f, 300, 6500))
    return reverb(x, 0.7, 0.35, rng)


def main():
    save("crowd_murmur.wav", crowd_murmur(), rms=0.1)
    for v in (1, 2):
        save(f"crowd_cheer_{v}.wav", crowd_cheer(v), rms=0.13)
        save(f"applause_{v}.wav", applause(v), rms=0.11)
    print("Sons da plateia em", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
