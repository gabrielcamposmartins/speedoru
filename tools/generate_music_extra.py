"""Gera mais 3 faixas originais de música de fundo, em estilos diferentes, em assets/audio/music/.

    python tools/generate_music_extra.py

* synthwave.wav   — synthwave/outrun, 104 BPM, Lá menor: baixo arpejado em semicolcheias, caixa
                    com reverb "gated", pads largos, lead com portamento e eco (combina com a
                    interface retrofuturista).
* drum_and_bass.wav — drum & bass, 174 BPM, Ré menor: breakbeat sincopado, baixo "reese"
                    (serras desafinadas filtradas), pads atmosféricos e stabs.
* chiptune.wav    — chiptune 8-bit, 144 BPM, Mi maior: onda de pulso com duty variável, baixo
                    triangular, bateria de ruído e arpejos rápidos de console antigo.

Cada faixa fecha em loop sem emenda (os ecos e caudas dão a volta no fim). Usa os osciladores
de tools/generate_music.py; sementes fixas (sempre as mesmas músicas).
"""
import os
import wave

import numpy as np

from generate_music import SR, adsr, midi_hz, osc, spectral_highpass, spectral_lowpass

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "music")


class Track:
    """Buffer estéreo circular (o fim emenda no começo) com ajudas de mixagem."""

    def __init__(self, bpm, bars, seed):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bar = 4 * self.beat
        self.step = self.beat / 4
        self.bars = bars
        self.n = int(round(bars * self.bar * SR))
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)
        self.rng = np.random.default_rng(seed)

    def put(self, buf, sig, t0, gain=1.0):
        i = int(round(t0 * SR)) % self.n
        end = i + len(sig)
        if end <= self.n:
            buf[i:end] += sig * gain
        else:
            first = self.n - i
            buf[i:] += sig[:first] * gain
            buf[:end - self.n] += sig[first:] * gain

    def stereo(self, sig, t0, gain=1.0, pan=0.0):
        self.put(self.L, sig, t0, gain * np.sqrt(0.5 * (1 - pan)) * 1.414)
        self.put(self.R, sig, t0, gain * np.sqrt(0.5 * (1 + pan)) * 1.414)

    def mono(self):
        return np.zeros(self.n)

    def noise(self, dur):
        return self.rng.standard_normal(int(dur * SR))


def echo(src, delay_s, feedback, taps, n, cutoff=4000):
    """Eco circular pingue-pongue: devolve (esquerda, direita)."""
    d = int(round(delay_s * SR))
    left = np.zeros(n)
    right = np.zeros(n)
    for k in range(1, taps + 1):
        tap = np.roll(src, d * k) * (feedback ** k)
        if k % 2:
            right += tap
        else:
            left += tap
    return spectral_lowpass(left, cutoff), spectral_lowpass(right, cutoff)


def reverb(src, n, length=1.6, mix=0.25, seed=3):
    """Reverb simples por convolução circular com ruído decaindo (estéreo)."""
    rng = np.random.default_rng(seed)
    m = int(length * SR)
    t = np.arange(m) / SR
    outs = []
    for ch in range(2):
        ir = rng.standard_normal(m) * np.exp(-t / (length / 5.0))
        ir = spectral_lowpass(ir, 5000)
        ir /= np.sqrt(np.sum(ir ** 2))
        pad_ir = np.zeros(n)
        pad_ir[:min(m, n)] = ir[:min(m, n)]
        wet = np.fft.irfft(np.fft.rfft(src) * np.fft.rfft(pad_ir), n)
        outs.append(wet * mix)
    return outs


## Volume médio de todas as faixas (igual ao race_theme.wav), para não mudar de volume na troca.
TARGET_RMS_DB = -16.5


def master(L, R, name, drive=1.2):
    mix = np.stack([spectral_highpass(L, 30), spectral_highpass(R, 30)], axis=1)
    mix /= np.abs(mix).max()
    mix = np.tanh(mix * drive) / np.tanh(drive)
    rms = np.sqrt(np.mean(mix ** 2))
    gain = min(10 ** (TARGET_RMS_DB / 20) / rms, 0.9 / np.abs(mix).max())
    mix *= gain
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((mix * 32767).astype("<i2").tobytes())
    print("Música gerada: %s (%.1f s)" % (os.path.abspath(path), len(mix) / SR))


def triad(root, minor):
    return [root, root + (3 if minor else 4), root + 7]


# ---------------------------------------------------------------------------
# 1. Synthwave / outrun
# ---------------------------------------------------------------------------
def synthwave():
    tr = Track(104, 32, seed=21)
    # Lá menor: Am F C G | Am F G Em  (verso), F G Am Am | F G C E (refrão)
    sections = [
        ("intro", [(57, 1), (53, 0), (48, 0), (55, 0)] * 2),
        ("verso", [(57, 1), (53, 0), (48, 0), (55, 0), (57, 1), (53, 0), (55, 0), (52, 1)]),
        ("refrao", [(53, 0), (55, 0), (57, 1), (57, 1), (53, 0), (55, 0), (48, 0), (52, 0)]),
        ("ponte", [(50, 1), (53, 0), (57, 1), (55, 0), (50, 1), (53, 0), (52, 0), (52, 0)]),
    ]
    drums = tr.mono()
    lead = tr.mono()
    snare_bus = tr.mono()
    duck = np.ones(tr.n)
    rng = tr.rng

    def kick80():
        n = int(0.5 * SR)
        t = np.arange(n) / SR
        f = 42 + 90 * np.exp(-t / 0.05)
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.22)

    def snare80():
        n = int(0.3 * SR)
        t = np.arange(n) / SR
        body = np.sin(2 * np.pi * 180 * t) * np.exp(-t / 0.06)
        nz = spectral_highpass(spectral_lowpass(rng.standard_normal(n), 8000), 900) * np.exp(-t / 0.09)
        return body * 0.5 + nz * 0.8

    def hat80():
        n = int(0.06 * SR)
        t = np.arange(n) / SR
        return spectral_highpass(rng.standard_normal(n), 8000) * np.exp(-t / 0.015)

    def bass16(m, dur):
        x = osc(midi_hz(m), dur, "saw", detune=-6) * 0.6 + osc(midi_hz(m), dur, "saw", detune=6) * 0.6
        x = spectral_lowpass(x, 900)
        return x * adsr(len(x), 0.002, 0.09, 0.35, 0.02)

    def pad80(notes, dur):
        x = np.zeros(int(dur * SR))
        for m in notes:
            for det in (-14, -5, 5, 14):
                x += osc(midi_hz(m + 12), dur, "saw", detune=det) * 0.22
        x = spectral_lowpass(x, 1800)
        return x * adsr(len(x), 0.6, 1.5, 0.9, 0.5)

    def lead80(m_from, m_to, dur):
        n = int(dur * SR)
        t = np.arange(n) / SR
        glide = np.clip(t / 0.06, 0, 1)
        f = midi_hz(m_from) * (1 - glide) + midi_hz(m_to) * glide
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.15) / 0.3, 0, 1)
        phase = 2 * np.pi * np.cumsum(f * vib) / SR
        x = np.zeros(n)
        for k in range(1, 30):
            if f.max() * k > SR * 0.45:
                break
            x += np.sin(k * phase) / k
        x = spectral_lowpass(x, 3600)
        return x * adsr(n, 0.01, 0.3, 0.7, 0.08)

    K, S, H = kick80(), snare80(), hat80()
    scale = [57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81]  # Lá menor natural
    bar0 = 0
    last_note = 69
    for section, chords in sections:
        intro = section == "intro"
        chorus = section == "refrao"
        for b, (root, minor) in enumerate(chords):
            t_bar = (bar0 + b) * tr.bar
            notes = triad(root, minor)
            # Bateria: bumbo em todos os tempos no refrão, caixa no 2 e 4 com reverb "gated"
            for beat in range(4):
                tb = t_bar + beat * tr.beat
                if not intro or beat in (0, 2):
                    if chorus or beat in (0, 2) or section == "ponte":
                        tr.put(drums, K, tb, 0.7)
                        i = int(round(tb * SR)) % tr.n
                        m = int(0.22 * SR)
                        idx = (i + np.arange(m)) % tr.n
                        duck[idx] = np.minimum(duck[idx], 0.4 + 0.6 * (np.arange(m) / m) ** 0.7)
                if beat in (1, 3) and not (intro and b < 4):
                    tr.put(snare_bus, S, tb, 0.8)
                for half in range(2):
                    if not intro or b >= 4:
                        tr.put(drums, H, tb + half * tr.beat / 2, 0.22 if half == 0 else 0.32)
            # Baixo arpejado em semicolcheias (oitava em cima no 4º de cada grupo)
            for k in range(16):
                m = notes[0] - 24 + (12 if k % 4 == 3 else 0)
                tr.stereo(bass16(m, tr.step * 0.85), t_bar + k * tr.step, 0.32)
            # Pad largo
            p = pad80(notes, tr.bar * 1.05)
            tr.put(tr.L, p, t_bar, 0.2)
            tr.put(tr.R, p, t_bar + 0.015, 0.2)
            # Lead (verso e refrão): notas longas com portamento
            if section in ("verso", "refrao", "ponte"):
                rhythm = [(0, 6), (6, 2), (8, 6), (14, 2)] if chorus else [(0, 8), (8, 4), (12, 4)]
                tones = [m for m in scale if m % 12 in [x % 12 for x in notes]]
                for st, ln in rhythm:
                    if st in (0, 8):
                        target = min(tones, key=lambda m: abs(m - last_note) + rng.random() * 4)
                    else:
                        i = scale.index(min(scale, key=lambda m: abs(m - last_note)))
                        target = scale[int(np.clip(i + rng.choice([-1, 1, 2]), 0, len(scale) - 1))]
                    note = lead80(last_note, target + (12 if chorus else 0), ln * tr.step * 0.95)
                    tr.put(lead, note, t_bar + st * tr.step, 0.42 if chorus else 0.34)
                    last_note = target
        bar0 += len(chords)

    # Caixa com reverb "gated" (cauda cortada rápido, típico dos anos 80)
    rl, rr = reverb(snare_bus, tr.n, length=0.9, mix=0.9, seed=5)
    gate = np.zeros(tr.n)
    beat_n = int(tr.beat * SR)
    for i in range(0, tr.n, beat_n):
        g = np.clip(1.0 - np.arange(min(beat_n, tr.n - i)) / (0.32 * SR), 0, 1) ** 0.5
        gate[i:i + len(g)] = g
    snare_l = snare_bus + rl * gate
    snare_r = snare_bus + rr * gate
    el, er = echo(lead, tr.beat * 0.75, 0.42, 5, tr.n, 3000)
    ll, lr = reverb(lead, tr.n, length=2.4, mix=0.35, seed=8)
    L = tr.L * duck + drums + snare_l + lead + el + ll
    R = tr.R * duck + drums + snare_r + lead + er + lr
    master(L, R, "synthwave.wav", drive=1.1)


# ---------------------------------------------------------------------------
# 2. Drum & bass
# ---------------------------------------------------------------------------
def drum_and_bass():
    tr = Track(174, 48, seed=33)
    rng = tr.rng
    # Ré menor: Dm Bb F C | Dm Bb Gm A (com "drop" nas seções B)
    prog_a = [(50, 1), (46, 0), (53, 0), (48, 0)]
    prog_b = [(50, 1), (46, 0), (43, 1), (45, 0)]
    sections = [("intro", prog_a * 2), ("drop", (prog_a + prog_b) * 2), ("pausa", prog_b * 2),
                ("drop2", (prog_a + prog_b) * 2)]
    drums = tr.mono()
    reese_bus = tr.mono()
    stabs = tr.mono()

    def kick_dnb():
        n = int(0.28 * SR)
        t = np.arange(n) / SR
        f = 50 + 140 * np.exp(-t / 0.025)
        click = spectral_highpass(rng.standard_normal(n), 3000) * np.exp(-t / 0.003) * 0.4
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09) + click

    def snare_dnb():
        n = int(0.22 * SR)
        t = np.arange(n) / SR
        crack = spectral_highpass(spectral_lowpass(rng.standard_normal(n), 10000), 1500) * np.exp(-t / 0.05)
        body = np.sin(2 * np.pi * 220 * t) * np.exp(-t / 0.035)
        return crack * 0.9 + body * 0.6

    def ghost():
        return snare_dnb()[: int(0.1 * SR)] * 0.25

    def ride():
        n = int(0.25 * SR)
        t = np.arange(n) / SR
        x = spectral_highpass(rng.standard_normal(n), 6000)
        x += 0.3 * np.sin(2 * np.pi * 5100 * t) + 0.2 * np.sin(2 * np.pi * 7300 * t)
        return x * np.exp(-t / 0.08)

    def reese(m, dur):
        x = np.zeros(int(dur * SR))
        for det in (-18, -7, 7, 18):
            x += osc(midi_hz(m), dur, "saw", detune=det) * 0.35
        x = spectral_lowpass(x, 420)
        x += osc(midi_hz(m), dur, "sine") * 0.6  # sub
        return x * adsr(len(x), 0.01, 0.4, 0.85, 0.05)

    def dnb_pad(notes, dur):
        x = np.zeros(int(dur * SR))
        for m in notes:
            for det in (-9, 9):
                x += osc(midi_hz(m + 12), dur, "tri", detune=det) * 0.4
        return spectral_lowpass(x, 2500) * adsr(len(x), 0.8, 2.0, 0.9, 0.6)

    def stab_dnb(notes, dur):
        x = np.zeros(int(dur * SR))
        for m in notes:
            x += osc(midi_hz(m + 12), dur, "square") * 0.3
        return spectral_lowpass(x, 2800) * adsr(len(x), 0.002, 0.12, 0.1, 0.03)

    K, S, G, RD = kick_dnb(), snare_dnb(), ghost(), ride()
    # Break em semicolcheias (16 passos): bumbo 0 e 10, caixa 4 e 12, fantasmas
    KICKS = [0, 10]
    KICKS_ALT = [0, 7, 10]
    SNARES = [4, 12]
    GHOSTS = [7, 9, 14]
    bar0 = 0
    for section, chords in sections:
        full = section.startswith("drop")
        for b, (root, minor) in enumerate(chords):
            t_bar = (bar0 + b) * tr.bar
            notes = triad(root, minor)
            if section != "pausa" and not (section == "intro" and b < 4):
                for st in (KICKS_ALT if b % 4 == 3 else KICKS):
                    tr.put(drums, K, t_bar + st * tr.step, 0.75)
                for st in SNARES:
                    tr.put(drums, S, t_bar + st * tr.step, 0.75)
                for st in GHOSTS:
                    tr.put(drums, G, t_bar + st * tr.step, 1.0)
            for st in range(0, 16, 2):
                if section != "pausa" or st % 4 == 0:
                    tr.put(drums, RD, t_bar + st * tr.step, 0.12 if st % 4 else 0.18)
            # Reese: nota longa por compasso; no drop, ataque extra no contratempo
            if full or section == "pausa":
                tr.put(reese_bus, reese(notes[0] - 24, tr.bar * 0.98), t_bar, 0.5)
                if full and b % 2 == 1:
                    tr.put(reese_bus, reese(notes[0] - 12, tr.step * 3), t_bar + 14 * tr.step, 0.25)
            # Pad atmosférico
            p = dnb_pad(notes, tr.bar * 1.1)
            tr.put(tr.L, p, t_bar, 0.18)
            tr.put(tr.R, p, t_bar + 0.02, 0.18)
            # Stabs sincopados no drop
            if full:
                for st in (3, 6, 11):
                    tr.put(stabs, stab_dnb(notes, tr.step * 1.5), t_bar + st * tr.step, 0.28)
        bar0 += len(chords)

    sl, sr_ = echo(stabs, tr.beat * 0.75, 0.45, 4, tr.n, 3200)
    pl, pr = reverb(tr.L + tr.R, tr.n, length=3.0, mix=0.3, seed=11)
    L = tr.L + pl + drums + reese_bus + stabs + sl
    R = tr.R + pr + drums + reese_bus + stabs + sr_
    master(L, R, "drum_and_bass.wav", drive=1.35)


# ---------------------------------------------------------------------------
# 3. Chiptune 8-bit
# ---------------------------------------------------------------------------
def chiptune():
    tr = Track(144, 32, seed=55)
    rng = tr.rng
    # Mi maior: E B C#m A | E B A B ; ponte: C#m A E B
    sections = [
        ("a", [(52, 0), (59, 0), (61, 1), (57, 0), (52, 0), (59, 0), (57, 0), (59, 0)]),
        ("b", [(57, 0), (59, 0), (56, 1), (61, 1), (57, 0), (59, 0), (52, 0), (52, 0)]),
        ("a2", [(52, 0), (59, 0), (61, 1), (57, 0), (52, 0), (59, 0), (57, 0), (59, 0)]),
        ("ponte", [(61, 1), (57, 0), (52, 0), (59, 0), (61, 1), (57, 0), (54, 1), (59, 0)]),
    ]
    scale = [52, 54, 56, 57, 59, 61, 63, 64, 66, 68, 69, 71, 73, 75, 76, 78, 80, 81, 83]

    def pulse(m, dur, duty=0.25, vol=1.0):
        n = int(dur * SR)
        t = np.arange(n) / SR
        f = midi_hz(m)
        # Pulso limitado em banda: soma de harmônicos com amplitude do pulso de duty d
        x = np.zeros(n)
        for k in range(1, 40):
            if f * k > SR * 0.45:
                break
            x += (np.sin(np.pi * k * duty) / k) * np.cos(2 * np.pi * f * k * t)
        x /= max(np.abs(x).max(), 1e-6)
        # Volume em degraus (como os chips antigos)
        env = np.floor(adsr(n, 0.002, 0.15, 0.55, 0.02) * 15) / 15
        return x * env * vol

    def tri_bass(m, dur):
        n = int(dur * SR)
        t = np.arange(n) / SR
        ph = (midi_hz(m) * t) % 1.0
        x = 4 * np.abs(ph - 0.5) - 1  # triângulo
        x = np.round(x * 8) / 8  # quantizado em 4 bits
        return spectral_lowpass(x, 6000) * adsr(n, 0.001, 0.2, 0.9, 0.01)

    def noise_drum(kind):
        n = int((0.12 if kind == "snare" else 0.04 if kind == "hat" else 0.1) * SR)
        t = np.arange(n) / SR
        # Ruído "LFSR": amostra e segura (sample & hold) para o som granulado dos chips
        hold = {"hat": 2, "snare": 6, "kick": 24}[kind]
        raw = rng.choice([-1.0, 1.0], size=n // hold + 1)
        x = np.repeat(raw, hold)[:n]
        if kind == "kick":
            f = 60 + 160 * np.exp(-t / 0.02)
            x = x * 0.2 + np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR))
            return spectral_lowpass(x, 3000) * np.exp(-t / 0.05)
        return x * np.exp(-t / (0.04 if kind == "snare" else 0.01))

    lead = tr.mono()
    drums = tr.mono()
    KD, SD, HD = noise_drum("kick"), noise_drum("snare"), noise_drum("hat")
    bar0 = 0
    current = 68
    for section, chords in sections:
        bridge = section == "ponte"
        for b, (root, minor) in enumerate(chords):
            t_bar = (bar0 + b) * tr.bar
            notes = triad(root, minor)
            # Bateria de ruído
            for st in range(16):
                ts = t_bar + st * tr.step
                if st in (0, 6, 8) or (st == 14 and b % 2):
                    tr.put(drums, KD, ts, 0.6)
                if st in (4, 12):
                    tr.put(drums, SD, ts, 0.45)
                if st % 2 == 0 and not bridge:
                    tr.put(drums, HD, ts, 0.18)
            # Baixo triangular em oitavas (colcheias)
            for k in range(8):
                m = notes[0] - 12 + (12 if k % 2 else 0)
                tr.stereo(tri_bass(m, tr.beat / 2 * 0.9), t_bar + k * tr.beat / 2, 0.38)
            # Acorde em arpejo bem rápido (fusas): o "acorde" dos consoles de 3 canais
            arp = [notes[0] + 12, notes[1] + 12, notes[2] + 12]
            k = 0
            t = 0.0
            while t < tr.bar - 1e-6:
                tr.stereo(pulse(arp[k % 3], tr.step / 2, 0.5, 1.0), t_bar + t, 0.08, 0.3)
                t += tr.step / 2
                k += 1
            # Melodia em pulso 12,5 %/25 % (duty troca por seção)
            duty = 0.125 if section == "b" else 0.25
            rhythm = [0, 2, 4, 6, 7, 8, 10, 12, 14] if not bridge else [0, 4, 6, 8, 12]
            tones = [m for m in scale if m % 12 in [x % 12 for x in notes]]
            for i, st in enumerate(rhythm):
                nxt = rhythm[i + 1] if i + 1 < len(rhythm) else 16
                if st in (0, 8):
                    current = min(tones, key=lambda m: abs(m - current) + rng.random() * 3)
                else:
                    idx = scale.index(min(scale, key=lambda m: abs(m - current)))
                    current = scale[int(np.clip(idx + rng.choice([-2, -1, 1, 1, 2]), 0, len(scale) - 1))]
                ln = (nxt - st) * tr.step * 0.9
                tr.put(lead, pulse(current + 12, ln, duty, 1.0), t_bar + st * tr.step, 0.3)
        bar0 += len(chords)

    el, er = echo(lead, tr.beat * 0.5, 0.3, 3, tr.n, 6000)
    L = tr.L + drums + lead + el
    R = tr.R + drums + lead + er
    master(L, R, "chiptune.wav", drive=1.05)


if __name__ == "__main__":
    synthwave()
    drum_and_bass()
    chiptune()
