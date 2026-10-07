"""Gera os sons do carro (WAV mono 16 bits, 44,1 kHz) em assets/audio/car/.

    python tools/generate_car_sounds.py

Tudo é sintetizado (não há gravações):
  * engine_on_<rpm>.wav / engine_off_<rpm>.wav — V6 turbo de 4 tempos em vários giros, com e sem
    carga. Cada cilindro gera um pulso de escape filtrado por ressonâncias do escapamento; os 6
    cilindros disparam a cada 120° de virabrequim (3 pulsos por volta).
  * loops: turbo, gear_whine (engrenagens retas), wind, tire_squeal, tire_scrub, gravel, grass, kerb.
  * sons curtos: shift_up, shift_down, backfire_1..3, impact_1..2, drs.

Os loops são periódicos por construção (síntese no domínio da frequência / convolução circular e
número inteiro de ciclos), então repetem sem clique. Ajuste as constantes e rode de novo.
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "car")
ENGINE_RPMS = [4000, 5500, 7000, 8500, 10000, 11500, 13000]
CYLINDERS = 6
RNG = np.random.default_rng(20261005)


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
def save(name, x, rms=None, peak=0.89):
    x = np.asarray(x, dtype=np.float64)
    x = x - x.mean()
    if rms is not None:
        x *= rms / max(np.sqrt(np.mean(x * x)), 1e-9)
        # Limita os picos sem mudar o timbre de forma audível
        x = np.tanh(x / 0.95) * 0.95
    else:
        x *= peak / max(np.abs(x).max(), 1e-9)
    data = (np.clip(x, -1.0, 1.0) * 32767).astype("<i2")
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    return path


def spectrum_filter(x, gain_fn):
    """Filtro circular (mantém o loop perfeito): multiplica o espectro por gain_fn(freqs)."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    return np.fft.irfft(spec * gain_fn(freqs), len(x))


def bandpass(f, lo, hi, order=2.0):
    """Ganho de um passa-faixa suave (formato Butterworth) para usar em spectrum_filter."""
    f = np.maximum(f, 1e-3)
    hp = 1.0 / np.sqrt(1.0 + (lo / f) ** (2 * order)) if lo > 0 else 1.0
    lp = 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order)) if hi > 0 else 1.0
    return hp * lp


def peak(f, center, width, gain):
    """Ressonância (pico em dB) para somar curvas de EQ."""
    return 1.0 + (10 ** (gain / 20.0) - 1.0) / (1.0 + ((f - center) / width) ** 2)


def periodic_noise(n, color=0.0):
    """Ruído periódico; color = expoente do espectro (0 branco, 1 rosa, 2 marrom)."""
    x = RNG.standard_normal(n)
    return spectrum_filter(x, lambda f: 1.0 / np.maximum(f, 20.0) ** (color * 0.5))


def resonator_kernel(n, modes):
    """Resposta ao impulso (comprimento n) de ressonâncias amortecidas: [(freq, decaimento s, ganho)]."""
    t = np.arange(n) / SR
    h = np.zeros(n)
    for freq, decay, gain in modes:
        h += gain * np.exp(-t / decay) * np.sin(2 * np.pi * freq * t)
    return h


def circular_convolve(x, h):
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h, len(x)), len(x))


def envelope(n, attack, decay, sustain_shape=1.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay) ** sustain_shape


# ---------------------------------------------------------------------------
# Motor
# ---------------------------------------------------------------------------
def engine_loop(rpm, on_load, seconds=2.0):
    """Motor V6 turbo de 4 tempos por síntese aditiva (sem distorção dura, sem aliasing).

    Todas as componentes são múltiplos inteiros da frequência do ciclo (rpm/120), então o loop
    fecha sem emenda. A "voz" do motor:
      * ordem de disparo (3 por volta = rpm/20 Hz) e seus harmônicos: o tom principal;
      * ordens de virabrequim e meias-ordens (cilindros um pouco desiguais): o "ronco"/textura;
      * envelope espectral com ressonâncias do escapamento (graves encorpados, médio nasal e brilho
        de turbo), mais brilhante com o acelerador no fundo;
      * pequenas flutuações lentas de amplitude por harmônico (o som "vive" em vez de ficar parado);
      * ruído de combustão filtrado, pulsando no ritmo dos disparos (aspereza do escape);
      * sem carga: mais grave e "borbulhando" (meias-ordens mais fortes, mais modulação).
    """
    cycle_hz = rpm / 120.0
    n_cycles = max(1, int(round(cycle_hz * seconds)))
    n = int(round(n_cycles / cycle_hz * SR))
    cycle_hz = n_cycles * SR / n
    firing = cycle_hz * CYLINDERS
    load = 1.0 if on_load else 0.0
    t = np.arange(n) / SR
    rng = np.random.default_rng(int(rpm) * 7 + int(load))

    def envelope_db(f):
        """Ganho (dB) do escapamento/admissão em função da frequência."""
        g = np.minimum(-7.0 * np.log2(np.maximum(f, 40.0) / 300.0), 3.0)  # queda geral (~-7 dB/oitava)
        g += 10.0 * np.exp(-((f - (150.0 + 30 * load)) / 90.0) ** 2)     # corpo grave
        g += (6.0 + 3.0 * load) * np.exp(-((f - 650.0) / 220.0) ** 2)   # médio "nasal"
        g += (4.0 + 6.0 * load) * np.exp(-((f - 1700.0) / 500.0) ** 2)  # rasgado do escape
        g += (2.0 + 5.0 * load) * np.exp(-((f - 3400.0) / 900.0) ** 2)  # brilho
        g -= 30.0 * (1.0 - np.clip(f / 60.0, 0, 1))                     # corta subgrave
        g -= np.clip((f - 6000.0) / 1000.0, 0, None) * 6.0              # agudos suaves
        if not on_load:
            g -= np.clip((f - 900.0) / 600.0, 0, None) * 5.0            # abafado sem carga
        return g

    x = np.zeros(n)
    max_k = int(min(14000.0, SR * 0.45) / cycle_hz)
    for k in range(1, max_k + 1):
        f = k * cycle_hz
        if k % CYLINDERS == 0:
            order = 1.0                         # harmônicos da frequência de disparo
        elif k % 3 == 0:
            order = 0.2 + 0.1 * (1 - load)      # ordens do virabrequim
        elif k % 2 == 0:
            order = 0.06 + 0.06 * (1 - load)
        else:
            order = 0.03 + 0.05 * (1 - load)    # meias-ordens: desigualdade entre cilindros
        if order < 0.05 and f > 3000.0:
            continue
        amp = order * 10 ** (envelope_db(f) / 20.0)
        # Flutuação lenta (frequência inteira por loop para fechar sem emenda)
        lfo_hz = rng.integers(1, 4) / (n / SR)
        depth = 0.12 + 0.25 * (1 - load)
        mod = 1.0 + depth * np.sin(2 * np.pi * lfo_hz * t + rng.random() * 6.28)
        x += amp * mod * np.sin(2 * np.pi * f * t + rng.random() * 6.28)

    # Ruído de combustão pulsando com os disparos (aspereza), filtrado e suave
    phase = (t * firing) % 1.0
    pulse = np.exp(-phase / 0.18)
    noise = spectrum_filter(periodic_noise(n, 0.6), lambda f: bandpass(f, 500, 6000) * peak(f, 1800, 700, 4))
    noise /= np.abs(noise).max()
    x = x / np.sqrt(np.mean(x * x))
    # Giro baixo: combustão irregular, cada disparo com força um pouco diferente (marcha lenta
    # "pulsando" em vez de um zumbido de tom puro). A sequência fecha no loop.
    rough = float(np.clip((7000.0 - rpm) / 3000.0, 0.0, 1.0))
    if rough > 0.0:
        events = n_cycles * CYLINDERS
        gains = 1.0 + rough * 0.45 * rng.uniform(-1.0, 1.0, events)
        idx = np.floor(t * firing).astype(int) % events
        nxt = (idx + 1) % events
        fr = (t * firing) % 1.0
        sm = fr * fr * (3 - 2 * fr)
        x *= gains[idx] * (1 - sm) + gains[nxt] * sm
        x /= np.sqrt(np.mean(x * x))
    x += noise * pulse * (0.10 + 0.08 * load + 0.22 * rough)
    # Sem carga: pequenos "borbulhos" esparsos no escapamento
    if not on_load:
        pops = np.zeros(n)
        for c in range(n_cycles):
            if rng.random() < 0.08:
                i = int((c + rng.random()) / cycle_hz * SR) % n
                pops[i] = rng.uniform(0.5, 1.0)
        h = resonator_kernel(int(0.03 * SR), [(110.0, 0.012, 1.0), (420.0, 0.005, 0.4)])
        x += circular_convolve(pops, h) * 0.6
    # Saturação muito leve (só arredonda picos)
    x = x / np.abs(x).max()
    return np.tanh(x * 1.3) / np.tanh(1.3)


# ---------------------------------------------------------------------------
# Outros loops
# ---------------------------------------------------------------------------
def tone_loop(partials, seconds=1.0, wobble=0.0):
    """Soma de senos com frequências inteiras por loop (periódico). partials: [(Hz, ganho)]."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for freq, gain in partials:
        f = round(freq * seconds) / seconds
        x += gain * np.sin(2 * np.pi * f * t + RNG.random() * 6.28)
    if wobble > 0:
        am = 1.0 + wobble * spectrum_filter(periodic_noise(n), lambda f: bandpass(f, 0, 6, 2))
        x *= am
    return x


def turbo():
    x = tone_loop([(2400, 1.0), (4800, 0.3), (7200, 0.12), (3150, 0.25)], wobble=0.3)
    hiss = spectrum_filter(periodic_noise(SR), lambda f: bandpass(f, 3000, 9000) * peak(f, 5200, 800, 8))
    return x + 0.25 * hiss / np.abs(hiss).max()


def gear_whine():
    return tone_loop([(1100, 1.0), (2200, 0.45), (3300, 0.2), (1650, 0.15)], wobble=0.25)


def wind():
    n = SR * 2
    x = periodic_noise(n, 1.4)
    x = spectrum_filter(x, lambda f: bandpass(f, 60, 4000) * peak(f, 700, 500, 4))
    gust = 1.0 + 0.35 * spectrum_filter(periodic_noise(n), lambda f: bandpass(f, 0, 1.5, 2)) * 6
    return x * np.clip(gust, 0.3, 2.0)


def tire_squeal():
    n = SR * 2
    t = np.arange(n) / SR
    x = np.zeros(n)
    # Tons instáveis perto de 1 kHz (pneu "cantando") com modulação lenta
    for base in (820, 1040, 1310, 1620):
        f = round(base * 2) / 2
        fm = 1.0 + 0.012 * np.sin(2 * np.pi * round(RNG.uniform(2, 6) * 2) / 2 * t)
        x += np.sin(2 * np.pi * np.cumsum(f * fm) / SR) * RNG.uniform(0.4, 1.0)
    am = np.clip(1.0 + 4.0 * spectrum_filter(periodic_noise(n), lambda f: bandpass(f, 0, 12, 2)), 0.1, 2.0)
    noise = spectrum_filter(periodic_noise(n), lambda f: bandpass(f, 700, 2500))
    return x * am + 0.4 * noise / np.abs(noise).max() * 3


def tire_scrub():
    n = SR * 2
    x = spectrum_filter(periodic_noise(n, 0.6), lambda f: bandpass(f, 150, 1800) * peak(f, 450, 200, 5))
    rough = np.clip(1.0 + 5.0 * spectrum_filter(periodic_noise(n), lambda f: bandpass(f, 10, 60, 2)), 0.2, 2.5)
    return x * rough


def gravel():
    n = SR * 2
    x = np.zeros(n)
    # Pedrinhas: milhares de cliques curtos + ronco grave
    clicks = np.zeros(n)
    idx = RNG.integers(0, n, 2600)
    clicks[idx] = RNG.uniform(-1, 1, idx.size) * RNG.uniform(0.2, 1.0, idx.size) ** 2
    h = resonator_kernel(400, [(2800, 0.0006, 1.0), (5200, 0.0003, 0.6), (1300, 0.0012, 0.5)])
    x += circular_convolve(clicks, h)
    rumble = spectrum_filter(periodic_noise(n, 1.0), lambda f: bandpass(f, 40, 400))
    return x / np.abs(x).max() + 0.6 * rumble / np.abs(rumble).max()


def grass():
    n = SR * 2
    swish = spectrum_filter(periodic_noise(n, 0.5), lambda f: bandpass(f, 1500, 7000))
    rumble = spectrum_filter(periodic_noise(n, 1.6), lambda f: bandpass(f, 30, 250))
    return 0.5 * swish / np.abs(swish).max() + rumble / np.abs(rumble).max()


def kerb():
    """Batidas da zebra a 20 Hz (o pitch no jogo acompanha a velocidade)."""
    n = SR  # 1 s → 20 batidas
    pulses = np.zeros(n)
    for k in range(20):
        pulses[int(k * n / 20)] = 1.0 if k % 2 == 0 else 0.8
    h = resonator_kernel(int(0.04 * SR), [(70, 0.012, 1.0), (140, 0.006, 0.5), (900, 0.002, 0.3)])
    x = circular_convolve(pulses, h)
    rattle = spectrum_filter(periodic_noise(n), lambda f: bandpass(f, 200, 2000)) * 0.15
    return x / np.abs(x).max() + rattle / np.abs(rattle).max() * 0.25


# ---------------------------------------------------------------------------
# Sons curtos
# ---------------------------------------------------------------------------
def burst(seconds, lo, hi, attack, decay, color=0.0):
    n = int(SR * seconds)
    x = RNG.standard_normal(n)
    if color:
        x = spectrum_filter(x, lambda f: 1.0 / np.maximum(f, 20.0) ** (color * 0.5))
    x = spectrum_filter(x, lambda f: bandpass(f, lo, hi))
    return x / np.abs(x).max() * envelope(n, attack, decay)


def thump(seconds, freq, decay, drop=0.5):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    f = freq * (1.0 - drop * (1 - np.exp(-t / decay)))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)


def shift_up():
    click = burst(0.05, 1500, 8000, 0.0005, 0.006)
    crack = burst(0.22, 200, 5000, 0.001, 0.04, 0.5)
    body = thump(0.22, 160, 0.05)
    n = int(SR * 0.25)
    x = np.zeros(n)
    x[:click.size] += click * 0.6
    x[int(0.01 * SR):int(0.01 * SR) + crack.size] += crack[: n - int(0.01 * SR)] * 0.9
    x[: body.size] += body * 0.7
    return x


def shift_down():
    click = burst(0.04, 1200, 7000, 0.0005, 0.005)
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    # "Blip" do acelerador: rajada que sobe de tom
    f = 300 + 500 * np.clip(t / 0.12, 0, 1)
    blip = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * envelope(n, 0.01, 0.07)
    blip = spectrum_filter(blip, lambda f: bandpass(f, 80, 4000))
    x = blip / np.abs(blip).max() * 0.8
    x[: click.size] += click * 0.6
    return x


def backfire(variant):
    """Ronco do escapamento ao aliviar ("brap-brap"), não estalos: 3/4/6 pulsos graves (55–85 Hz,
    ataque de alguns ms, ~55 ms de queda) com sopro de ar filtrado, em intervalos irregulares e
    cada vez mais fracos; ressonância do cano em 180–420 Hz e nada acima de ~2,5 kHz (o que dava o
    som de pipoca). Gerador próprio por variante: não muda o ruído dos outros sons."""
    rng = np.random.default_rng(7000 + variant)
    n = int(SR * 0.75)
    x = np.zeros(n)
    count = (3, 4, 6)[variant - 1]
    start = 0.0
    for k in range(count):
        m = int(SR * 0.2)
        t = np.arange(m) / SR
        f0 = rng.uniform(55.0, 85.0)
        f = f0 * (1.0 - 0.3 * (1.0 - np.exp(-t / 0.04)))
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * envelope(m, 0.004, 0.055)
        noise = rng.standard_normal(m)
        noise = spectrum_filter(noise, lambda fr: bandpass(fr, 120, 1800) / np.maximum(fr, 20.0) ** 0.35)
        noise = noise / max(np.abs(noise).max(), 1e-9) * envelope(m, 0.003, 0.035)
        pulse = body * 0.95 + noise * 0.55
        level = (1.0 - 0.12 * k) * rng.uniform(0.7, 1.0)
        i = int(start * SR)
        size = min(m, n - i)
        x[i:i + size] += pulse[:size] * level
        start += rng.uniform(0.045, 0.11)
    x = spectrum_filter(x, lambda fr: bandpass(fr, 40, 2500) * (1.0 + 0.8 * bandpass(fr, 180, 420, 1.0)))
    return np.tanh(x * 1.4)


def impact(variant):
    n = int(SR * (0.9 if variant == 1 else 0.6))
    x = np.zeros(n)
    low = thump(n / SR, 70 if variant == 1 else 110, 0.12, 0.6)
    crash = burst(n / SR, 300, 9000, 0.001, 0.08 if variant == 1 else 0.05, 0.3)
    t = np.arange(n) / SR
    ring = np.zeros(n)
    for f in (523.0, 1187.0, 1931.0, 2874.0):  # parciais inarmônicas (metal/fibra de carbono)
        ring += np.sin(2 * np.pi * f * RNG.uniform(0.9, 1.1) * t) * np.exp(-t / RNG.uniform(0.05, 0.2))
    x += low * 1.0 + crash * 0.8 + ring * 0.12
    return x


def scrape():
    """Fibra de carbono/metal raspando no muro ou no chão: chiado áspero + estalos."""
    n = SR * 2
    hiss = spectrum_filter(periodic_noise(n, 0.3), lambda f: bandpass(f, 1200, 9000) * peak(f, 3200, 900, 6))
    grind = spectrum_filter(periodic_noise(n, 1.0), lambda f: bandpass(f, 120, 900) * peak(f, 260, 80, 8))
    rough = np.clip(1.0 + 3.0 * spectrum_filter(periodic_noise(n), lambda f: bandpass(f, 15, 90, 2)), 0.1, 3.0)
    clicks = np.zeros(n)
    idx = RNG.integers(0, n, 900)
    clicks[idx] = RNG.uniform(-1, 1, idx.size)
    clicks = circular_convolve(clicks, resonator_kernel(300, [(4200, 0.0005, 1.0), (2100, 0.001, 0.6)]))
    return (hiss / np.abs(hiss).max() * 0.8 + grind / np.abs(grind).max() * 0.7) * rough + clicks / np.abs(clicks).max() * 0.5


def crack(variant):
    """Peça de fibra de carbono quebrando e se soltando."""
    n = int(SR * 0.7)
    x = np.zeros(n)
    snaps = [0.0, 0.03, 0.07] if variant == 1 else [0.0, 0.05]
    for k, start in enumerate(snaps):
        b = burst(0.25, 800, 9000, 0.0003, 0.02 + 0.01 * k, 0.2)
        i = int(start * SR)
        m = min(b.size, n - i)
        x[i:i + m] += b[:m] * (1.0 - 0.25 * k)
    x += thump(n / SR, 140 if variant == 1 else 190, 0.06, 0.5) * 0.7
    t = np.arange(n) / SR
    for f in (1650.0, 2730.0, 4100.0):  # zumbido da fibra vibrando
        x += np.sin(2 * np.pi * f * RNG.uniform(0.95, 1.05) * t) * np.exp(-t / 0.06) * 0.15
    return x


def boost():
    """Motor elétrico do boost: zumbido subindo + brilho cintilante (loop)."""
    n = SR * 2
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f, a in ((220.0, 0.6), (440.0, 0.5), (660.0, 0.3), (1320.0, 0.25), (1760.0, 0.15)):
        x += a * np.sin(2 * np.pi * f * t + RNG.random() * 6.28)
    whine = np.sin(2 * np.pi * 3520.0 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 6.0 * t)) * 0.12
    shimmer = spectrum_filter(periodic_noise(n), lambda f: bandpass(f, 5000, 12000)) * 0.6
    sparkle = np.zeros(n)
    idx = RNG.integers(0, n, 300)
    sparkle[idx] = RNG.uniform(0.3, 1.0, idx.size)
    sparkle = circular_convolve(sparkle, resonator_kernel(2000, [(4186.0, 0.03, 1.0), (5274.0, 0.025, 0.7), (6272.0, 0.02, 0.5)]))
    am = 1.0 + 0.25 * np.sin(2 * np.pi * 4.0 * t)
    return x * am + whine + shimmer / np.abs(shimmer).max() * 0.15 + sparkle / np.abs(sparkle).max() * 0.35


def drs():
    whoosh = burst(0.25, 400, 4000, 0.02, 0.06)
    click = burst(0.03, 2000, 9000, 0.0003, 0.004)
    x = whoosh * 0.6
    x[: click.size] += click
    return x


def main():
    os.makedirs(OUT, exist_ok=True)
    for rpm in ENGINE_RPMS:
        save(f"engine_on_{rpm}.wav", engine_loop(rpm, True), rms=0.2)
        save(f"engine_off_{rpm}.wav", engine_loop(rpm, False), rms=0.14)
    save("turbo.wav", turbo(), rms=0.2)
    save("gear_whine.wav", gear_whine(), rms=0.2)
    save("wind.wav", wind(), rms=0.2)
    save("tire_squeal.wav", tire_squeal(), rms=0.2)
    save("tire_scrub.wav", tire_scrub(), rms=0.2)
    save("gravel.wav", gravel(), rms=0.2)
    save("grass.wav", grass(), rms=0.2)
    save("kerb.wav", kerb(), rms=0.22)
    save("shift_up.wav", shift_up())
    save("shift_down.wav", shift_down())
    for v in (1, 2, 3):
        save(f"backfire_{v}.wav", backfire(v))
    for v in (1, 2):
        save(f"impact_{v}.wav", impact(v))
    save("drs.wav", drs())
    save("scrape.wav", scrape(), rms=0.22)
    save("boost.wav", boost(), rms=0.2)
    for v in (1, 2):
        save(f"crack_{v}.wav", crack(v))
    print("Sons gerados em", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
