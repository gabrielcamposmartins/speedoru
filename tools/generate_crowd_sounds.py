"""Sons da plateia (sintetizados, sem gravações) em assets/audio/crowd/:

  * crowd_murmur.wav   loop de 10 s: centenas de vozes falando ao mesmo tempo. Cada sílaba é uma
                       vogal (formantes F1/F2/F3 de verdade) excitada por ruído (sussurro) e pulsos
                       glotais com entonação; longe vira o "mar de vozes" de arquibancada. Emenda
                       sem estalo.
  * crowd_cheer_1/2    torcida: "uuuh"/"êêê" de muitas vozes subindo de tom, gritos e assobios.
  * applause_1/2       palmas: centenas de palmas aleatórias que crescem e somem.
  * air_horn_1/2       buzinas de ar (a "corneta" das arquibancadas de corrida), uma e duas buzinadas.

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


VOWELS = [  # F1, F2, F3 (Hz) de vogais faladas
    (730, 1090, 2440), (270, 2290, 3010), (300, 870, 2240), (530, 1840, 2480), (570, 840, 2410),
    (440, 1020, 2240), (660, 1720, 2410), (490, 1350, 1690),
]


def syllable(rng, f0, vowel, seconds, voiced_mix, glide=0.0):
    """Uma sílaba: ruído + pulsos glotais com entonação, filtrados por três formantes."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = f0 * (1.0 + glide * t / max(seconds, 1e-3) + 0.03 * np.sin(2 * np.pi * rng.uniform(4, 7) * t))
    phase = np.cumsum(f) / SR
    pulses = (np.diff(np.floor(phase), prepend=0.0) > 0).astype(float)
    exc = pulses * voiced_mix * 6.0 + rng.standard_normal(n) * (1.0 - voiced_mix * 0.6)
    f1, f2, f3 = [v * rng.uniform(0.9, 1.12) for v in vowel]
    y = spectrum(exc, lambda fr: formants(fr, [(f1, 90, 1.0), (f2, 130, 0.7), (f3, 200, 0.35)]) * band(fr, 120, 5000))
    env = np.minimum(t / 0.025, 1.0) * np.minimum((seconds - t) / 0.06, 1.0)
    return y * np.clip(env, 0, 1)


def babble(n, rng, voices, rate=(0.09, 0.26), gap=(0.02, 0.35), level=(0.3, 1.0)):
    x = np.zeros(n)
    for v in range(voices):
        f0 = rng.uniform(95, 240)
        voiced = rng.uniform(0.25, 0.75)
        gain = rng.uniform(*level)
        i = int(rng.uniform(0, 1.0) * SR)
        while i < n:
            if rng.random() < 0.1:
                i += int(rng.uniform(0.3, 1.0) * SR)  # pausa entre frases
                continue
            dur = rng.uniform(*rate)
            syl = syllable(rng, f0 * rng.uniform(0.9, 1.15), VOWELS[rng.integers(len(VOWELS))], dur, voiced)
            m = min(len(syl), n - i)
            x[i:i + m] += syl[:m] / max(np.sqrt(np.mean(syl * syl)), 1e-9) * gain
            i += len(syl) + int(rng.uniform(*gap) * SR)
    return x


def crowd_murmur(seconds=10.0, voices=260):
    rng = np.random.default_rng(31)
    fade = 1.0
    n = int((seconds + fade) * SR)
    x = babble(n, rng, voices)
    x /= np.sqrt(np.mean(x * x))
    # Fundo distante: a massa de vozes vira um "chiado" na faixa da fala
    floor = spectrum(rng.standard_normal(n), lambda f: band(f, 180, 2500, 1.5) / np.sqrt(f / 300.0))
    x += floor / np.sqrt(np.mean(floor * floor)) * 0.45
    x = reverb(x, 1.1, 0.45, rng)
    m = int(fade * SR)
    out = x[: n - m].copy()
    ramp = np.linspace(0, 1, m)
    out[:m] = out[:m] * ramp + x[n - m:] * (1 - ramp)
    return out


def crowd_cheer(variant):
    rng = np.random.default_rng(100 + variant)
    seconds = 3.8
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    vowel_set = [VOWELS[2], VOWELS[4]] if variant == 1 else [VOWELS[0], VOWELS[3]]  # "uuu"/"ooo" ou "aaa"/"êêê"
    for v in range(140):
        start = rng.uniform(0.0, 0.6)
        dur = rng.uniform(1.2, 2.8)
        f0 = rng.uniform(170, 420)
        syl = syllable(rng, f0, vowel_set[rng.integers(2)], dur, rng.uniform(0.45, 0.85), glide=rng.uniform(0.05, 0.3))
        env = np.minimum(np.arange(len(syl)) / SR / rng.uniform(0.15, 0.4), 1.0)
        i = int(start * SR)
        m = min(len(syl), n - i)
        x[i:i + m] += (syl * env)[:m] / max(np.sqrt(np.mean(syl * syl)), 1e-9) * rng.uniform(0.4, 1.0)
    # Gritos curtos por cima ("êi!", "vai!")
    for k in range(10):
        syl = syllable(rng, rng.uniform(250, 480), VOWELS[rng.integers(len(VOWELS))], rng.uniform(0.18, 0.4), 0.8, glide=0.2)
        i = int(rng.uniform(0.2, 2.2) * SR)
        m = min(len(syl), n - i)
        x[i:i + m] += syl[:m] / max(np.sqrt(np.mean(syl * syl)), 1e-9) * 1.6
    x /= np.sqrt(np.mean(x * x))
    for k in range(3 if variant == 1 else 2):
        s0 = rng.uniform(0.3, 1.6)
        d = rng.uniform(0.5, 1.0)
        i0, i1 = int(s0 * SR), int(min(s0 + d, seconds) * SR)
        tt = np.arange(i1 - i0) / SR
        fw = rng.uniform(2000, 3000) * (1 + 0.06 * np.sin(2 * np.pi * rng.uniform(4, 7) * tt) + 0.15 * tt / d)
        x[i0:i1] += np.sin(2 * np.pi * np.cumsum(fw) / SR) * np.hanning(i1 - i0) * 0.5
    x *= np.clip(t / 0.3, 0, 1) * np.exp(-np.clip(t - 2.6, 0, None) / 0.5)
    return reverb(x, 1.0, 0.4, rng)


def air_horn(variant):
    """Buzina de ar: dente de serra rico em harmônicos, levemente desafinada (duas cornetas),
    ataque com "engasgo" e um pouco de vibrato; variante 2 buzina duas vezes."""
    rng = np.random.default_rng(300 + variant)
    blasts = [(0.0, 0.9)] if variant == 1 else [(0.0, 0.45), (0.6, 1.0)]
    seconds = blasts[-1][0] + blasts[-1][1] + 0.6
    n = int(seconds * SR)
    x = np.zeros(n)
    base = 415.0 if variant == 1 else 370.0
    for start, dur in blasts:
        m = int(dur * SR)
        t = np.arange(m) / SR
        y = np.zeros(m)
        for detune in (1.0, 1.012, 0.994):
            f = base * detune * (1.0 - 0.06 * np.exp(-t / 0.05)) * (1 + 0.004 * np.sin(2 * np.pi * 5.5 * t))
            ph = np.cumsum(f) / SR
            for h in range(1, 16):
                y += np.sin(2 * np.pi * h * ph) / h ** 0.9
        env = np.minimum(t / 0.03, 1.0) * np.minimum((dur - t) / 0.08, 1.0)
        y *= np.clip(env, 0, 1)
        y = spectrum(y, lambda f: band(f, 250, 6000) * (1.0 + 1.2 * np.exp(-((f - 1600.0) / 600.0) ** 2)))
        i = int(start * SR)
        x[i:i + m] += y
    return reverb(x, 1.2, 0.35, rng)


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
    save("crowd_murmur.wav", crowd_murmur(), rms=0.11)
    for v in (1, 2):
        save(f"crowd_cheer_{v}.wav", crowd_cheer(v), rms=0.14)
        save(f"applause_{v}.wav", applause(v), rms=0.11)
        save(f"air_horn_{v}.wav", air_horn(v), rms=0.12)
    print("Sons da plateia em", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
