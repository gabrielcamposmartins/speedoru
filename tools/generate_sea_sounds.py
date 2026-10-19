"""Sons do fundo do mar da Atlantis Abyss (sintetizados, sem gravações) em assets/audio/ambient/:

  * underwater_hum.wav  loop de 12 s: o "silêncio" debaixo d'água — ronco grave de ruído marrom
                        abafado, um zumbido baixo que ondula devagar e ondas de pressão passando.
                        Emenda sem estalo.
  * bubbles.wav         loop de 8 s: bolhas subindo — cada uma um "plop" curto com o tom subindo
                        (como uma bolha de verdade ressoando ao se soltar), em grupos irregulares.
  * whale_call_1/2.wav  canto de baleia ao longe: notas que deslizam devagar, com harmônicos,
                        vibrato e uma cauda longa de eco.
  * waterfall.wav       loop de 8 s: cachoeira — ruído forte de água correndo (rosa, faixa média)
                        mexendo e respingos.
  * water_exit.wav      1,9 s: saída da água (a câmera passando da água para o ar) — o estouro na
                        superfície com o brilho caindo, um tum grave, a água escorrendo e pingos.

Rodar:  python tools/generate_sea_sounds.py
"""

import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "ambient")
RNG = np.random.default_rng(1977)


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


def loop_fade(x, seconds=0.6):
    """Emenda: mistura o fim no começo (crossfade) para o loop não estalar."""
    n = int(seconds * SR)
    out = x[:-n].copy()
    t = np.linspace(0.0, 1.0, n)
    out[:n] = out[:n] * np.sqrt(t) + x[-n:] * np.sqrt(1.0 - t)
    return out


def underwater_hum(seconds=12.0):
    n = int((seconds + 0.6) * SR)
    t = np.arange(n) / SR
    # Ruído marrom (grave) bem abafado
    brown = np.cumsum(RNG.normal(size=n))
    brown -= np.convolve(brown, np.ones(4410) / 4410, mode="same")
    rumble = spectrum(brown, lambda f: band(f, 18, 220, 2.0))
    # Ondas de pressão passando (modulação lenta) e um zumbido baixo
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / 6.0) * np.sin(2 * np.pi * t / 4.0 + 1.0)
    drone = (np.sin(2 * np.pi * 55 * t + 0.6 * np.sin(2 * np.pi * 0.17 * t)) * 0.18
             + np.sin(2 * np.pi * 82.5 * t + 0.4 * np.sin(2 * np.pi * 0.11 * t)) * 0.1)
    hiss = spectrum(RNG.normal(size=n), lambda f: band(f, 300, 1400, 1.5)) * 0.08
    x = rumble / np.max(np.abs(rumble)) * swell + drone * (0.7 + 0.3 * swell) + hiss
    return loop_fade(x)


def bubble(f0, length):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = f0 * (1.0 + 0.9 * t / length)  # o tom sobe enquanto a bolha se solta
    phase = 2 * np.pi * np.cumsum(f) / SR
    env = np.exp(-t / (length * 0.35)) * (1.0 - np.exp(-t / 0.002))
    return np.sin(phase) * env


def bubbles(seconds=8.0):
    n = int((seconds + 0.6) * SR)
    x = np.zeros(n)
    k = 0.0
    while k < seconds + 0.4:
        # Grupos de 1 a 7 bolhas, com intervalos irregulares
        group = RNG.integers(1, 8)
        for g in range(group):
            start = int((k + g * RNG.uniform(0.02, 0.09)) * SR)
            size = RNG.uniform(0.0, 1.0)
            b = bubble(RNG.uniform(380, 1500) * (1.4 - size * 0.6), RNG.uniform(0.03, 0.09))
            end = min(start + len(b), n)
            x[start:end] += b[: end - start] * RNG.uniform(0.3, 1.0)
        k += RNG.uniform(0.15, 0.8)
    x = spectrum(x, lambda f: band(f, 150, 3500, 1.0))
    return loop_fade(x, 0.3)


def whale_call(variant):
    seconds = 6.5
    n = int(seconds * SR)
    t = np.arange(n) / SR
    # Notas: (início, fim, tom inicial, tom final) — deslizando devagar
    if variant == 1:
        notes = [(0.2, 1.9, 260, 180), (2.1, 3.4, 190, 330), (3.6, 4.6, 330, 300)]
    else:
        notes = [(0.1, 1.2, 140, 220), (1.4, 2.1, 400, 520), (2.4, 4.2, 300, 150)]
    x = np.zeros(n)
    for a, b, f0, f1 in notes:
        i0, i1 = int(a * SR), int(b * SR)
        tt = np.arange(i1 - i0) / SR
        u = tt / (b - a)
        f = f0 + (f1 - f0) * (3 * u * u - 2 * u * u * u)
        f *= 1.0 + 0.012 * np.sin(2 * np.pi * 5.5 * tt)
        phase = 2 * np.pi * np.cumsum(f) / SR
        env = np.sin(np.pi * u) ** 0.6
        tone = np.sin(phase) + 0.45 * np.sin(2 * phase + 0.3) + 0.2 * np.sin(3 * phase + 1.1)
        x[i0:i1] += tone * env
    # Eco longo (resposta de ruído decaindo) e abafado
    ir_n = int(2.5 * SR)
    ir = RNG.normal(size=ir_n) * np.exp(-np.arange(ir_n) / SR / 0.7)
    wet = np.fft.irfft(np.fft.rfft(x, 2 * n) * np.fft.rfft(ir, 2 * n), 2 * n)[:n]
    y = x * 0.7 + wet / np.max(np.abs(wet)) * np.max(np.abs(x)) * 0.6
    y = spectrum(y, lambda f: band(f, 60, 1800, 1.5))
    fade = np.minimum(1.0, (n - np.arange(n)) / (0.8 * SR))
    return y * fade


def waterfall(seconds=8.0):
    n = int((seconds + 0.6) * SR)
    t = np.arange(n) / SR
    white = RNG.normal(size=n)
    pink = spectrum(white, lambda f: 1.0 / np.sqrt(f) * band(f, 120, 7000, 1.5))
    churn = 0.75 + 0.25 * spectrum(RNG.normal(size=n), lambda f: band(f, 0.5, 6, 1.0)) / 3.0
    x = pink / np.max(np.abs(pink)) * churn
    # Respingos
    for k in range(int(seconds * 9)):
        start = RNG.integers(0, n - 4000)
        burst = spectrum(RNG.normal(size=3000), lambda f: band(f, 1500, 9000, 1.0)) * np.exp(-np.arange(3000) / 600)
        x[start:start + 3000] += burst / np.max(np.abs(burst)) * RNG.uniform(0.1, 0.35)
    return loop_fade(x, 0.5)


def water_exit(seconds=1.9):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    # Estouro na superfície: ruído com ataque rápido, o agudo some antes (o brilho cai)
    bn = int(0.6 * SR)
    tb = np.arange(bn) / SR
    noise = RNG.normal(size=bn)
    att = 1.0 - np.exp(-tb / 0.004)
    for (lo, hi), decay, gain in (((3000, 9000), 0.05, 0.8), ((800, 3500), 0.14, 1.0), ((150, 800), 0.24, 0.7)):
        part = spectrum(noise, lambda f, lo=lo, hi=hi: band(f, lo, hi, 1.5))
        x[:bn] += part / np.max(np.abs(part)) * np.exp(-tb / decay) * att * gain
    # Tum grave (a pressão soltando)
    x[:bn] += np.sin(2 * np.pi * 68 * tb) * np.exp(-tb / 0.09) * att * 0.7
    # Água escorrendo: ruído rosa em faixa média, caindo devagar, em ondas
    drain = spectrum(RNG.normal(size=n), lambda f: 1.0 / np.sqrt(f) * band(f, 500, 5000, 1.2))
    drain = drain / np.max(np.abs(drain)) * np.exp(-t / 0.55) * (0.8 + 0.2 * np.sin(2 * np.pi * 7 * t))
    x += drain * (1.0 - np.exp(-t / 0.05)) * 0.55
    # Pingos: plinks curtos com o tom subindo, mais no começo
    for k in range(10):
        start = RNG.uniform(0.3, seconds - 0.25)
        d = bubble(RNG.uniform(1400, 3200), RNG.uniform(0.025, 0.05))
        i0 = int(start * SR)
        x[i0:i0 + len(d)] += d * RNG.uniform(0.12, 0.35) * np.exp(-(start - 0.3) / 1.1)
    fade = np.minimum(1.0, (n - np.arange(n)) / (0.3 * SR))
    return x * fade


def main():
    save("underwater_hum.wav", underwater_hum(), rms=0.14)
    save("bubbles.wav", bubbles(), rms=0.06)
    for v in (1, 2):
        save(f"whale_call_{v}.wav", whale_call(v), rms=0.1)
    save("waterfall.wav", waterfall(), rms=0.16)
    # (por último: os de cima saem iguais, a sequência do RNG não muda)
    save("water_exit.wav", water_exit(), rms=0.13)
    print("sons gravados em", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
