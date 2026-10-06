"""Gera a música de fundo (faixa original, estilo pop anime animado) em assets/audio/music/.

    python tools/generate_music.py

152 BPM, Dó maior, 32 compassos (~50 s) em loop sem emenda:
  intro/verso (I–V–vi–IV) → pré-refrão → refrão na progressão "royal road" (IV–V–iii–vi) → ponte.
Instrumentos sintetizados com osciladores limitados em banda (sem aliasing): bumbo, caixa com palmas,
chimbal, baixo, acordes em "stabs", pad com pulsação (sidechain), arpejo e melodia principal
(onda quadrada com vibrato e eco estéreo). A melodia é gerada a partir dos acordes com motivos que
se repetem e variam (semente fixa: sempre a mesma música). Edite SEED/BPM/progressões e rode de novo.
"""
import os
import wave

import numpy as np

SR = 44100
BPM = 152
SEED = 7
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "music")
BEAT = 60.0 / BPM
BAR = 4 * BEAT
STEP = BEAT / 4  # semicolcheia

# Acordes: (fundamental MIDI, tipo)
CHORDS = {"C": (60, "maj"), "G": (55, "maj"), "Am": (57, "min"), "F": (53, "maj"),
          "Em": (52, "min"), "Dm": (50, "min")}
SECTIONS = [
    ("verso", ["C", "G", "Am", "F", "C", "G", "F", "G"]),
    ("pre", ["Am", "F", "C", "G", "Am", "F", "Dm", "G"]),
    ("refrao", ["F", "G", "Em", "Am", "F", "G", "C", "C"]),
    ("ponte", ["Am", "Em", "F", "C", "Dm", "Em", "F", "G"]),
]
SCALE = [0, 2, 4, 5, 7, 9, 11]  # Dó maior
RNG = np.random.default_rng(SEED)


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def chord_notes(name):
    root, kind = CHORDS[name]
    third = 3 if kind == "min" else 4
    return [root, root + third, root + 7]


# ---------------------------------------------------------------------------
# Osciladores (aditivos, limitados abaixo de Nyquist)
# ---------------------------------------------------------------------------
def osc(freq, dur, shape="saw", vibrato=0.0, detune=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * 2 ** (detune / 1200.0)
    phase_mod = vibrato * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.25, 0, 1)
    out = np.zeros(n)
    k_max = int(min(60, (SR * 0.45) / f))
    for k in range(1, k_max + 1):
        if shape == "square" and k % 2 == 0:
            continue
        if shape == "tri" and k % 2 == 0:
            continue
        if shape == "saw":
            a = 1.0 / k
        elif shape == "square":
            a = 1.0 / k
        elif shape == "tri":
            a = (1.0 / k ** 2) * (1 if (k // 2) % 2 == 0 else -1)
        else:  # "sine"
            a = 1.0 if k == 1 else 0.0
        if a == 0.0:
            continue
        out += a * np.sin(2 * np.pi * f * k * t + k * phase_mod)
    return out


def adsr(n, a=0.005, d=0.1, s=0.6, r=0.05, hold=None):
    t = np.arange(n) / SR
    hold = n / SR - r if hold is None else hold
    env = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip((t - hold) / max(r, 1e-4), 0, 1)
    return env * (1 - rel)


def spectral_lowpass(x, cutoff, order=2.0):
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = 1.0 / np.sqrt(1.0 + (f / cutoff) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x) * g, len(x))


def spectral_highpass(x, cutoff, order=2.0):
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = 1.0 / np.sqrt(1.0 + (cutoff / np.maximum(f, 1.0)) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x) * g, len(x))


# ---------------------------------------------------------------------------
# Instrumentos
# ---------------------------------------------------------------------------
def kick():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t / 0.035)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.11)
    click = spectral_highpass(RNG.standard_normal(n), 2000) * np.exp(-t / 0.004) * 0.25
    return body + click


def snare():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    noise = spectral_highpass(spectral_lowpass(RNG.standard_normal(n), 9000), 1200) * np.exp(-t / 0.07)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05)
    clap = np.zeros(n)
    for k in range(3):  # palmas: três rajadas curtas
        i = int(k * 0.011 * SR)
        clap[i:] += spectral_highpass(RNG.standard_normal(n - i), 900) * np.exp(-np.arange(n - i) / SR / 0.02)
    return noise * 0.6 + tone * 0.5 + clap * 0.25


def hat(open_=False):
    n = int((0.22 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    x = spectral_highpass(RNG.standard_normal(n), 7000)
    return x * np.exp(-t / (0.08 if open_ else 0.012))


def bass_note(m, dur):
    x = osc(midi_hz(m), dur, "saw") * 0.7 + osc(midi_hz(m), dur, "sine") * 0.5
    x = spectral_lowpass(x, 1400)
    return x * adsr(len(x), 0.003, 0.12, 0.7, 0.03)


def stab(notes, dur):
    x = np.zeros(int(dur * SR))
    for m in notes:
        for det in (-7, 7):
            x += osc(midi_hz(m), dur, "saw", detune=det) * 0.5
    x = spectral_lowpass(x, 3200)
    return x * adsr(len(x), 0.004, 0.09, 0.25, 0.04)


def pad(notes, dur):
    x = np.zeros(int(dur * SR))
    for m in notes:
        for det in (-11, 0, 11):
            x += osc(midi_hz(m + 12), dur, "saw", detune=det) * 0.3
    x = spectral_lowpass(x, 2200)
    return x * adsr(len(x), 0.25, 1.0, 0.85, 0.3)


def lead_note(m, dur):
    x = osc(midi_hz(m), dur, "square", vibrato=0.35) * 0.7 + osc(midi_hz(m + 12), dur, "tri") * 0.25
    x = spectral_lowpass(x, 5500)
    return x * adsr(len(x), 0.006, 0.18, 0.65, 0.06)


def arp_note(m, dur):
    x = osc(midi_hz(m), dur, "tri") + osc(midi_hz(m), dur, "sine") * 0.5
    return x * adsr(len(x), 0.002, 0.07, 0.2, 0.02)


# ---------------------------------------------------------------------------
# Melodia: motivos sobre os acordes
# ---------------------------------------------------------------------------
RHYTHMS = {
    "verso": [[0, 2, 3, 6, 8, 10, 12], [0, 3, 6, 8, 11, 14], [0, 2, 4, 6, 10, 12, 14]],
    "pre": [[0, 3, 6, 8, 10, 12, 14], [0, 2, 4, 6, 8, 11, 14]],
    "refrao": [[0, 4, 6, 8, 12], [0, 2, 4, 8, 10, 12], [0, 6, 8, 12, 14]],
    "ponte": [[0, 4, 8, 12], [0, 6, 8, 14]],
}


def scale_notes(lo, hi):
    return [m for m in range(lo, hi + 1) if m % 12 in SCALE]


def make_melody(section, chords, octave_shift):
    """Lista de (passo inicial em semicolcheias, duração em passos, nota MIDI)."""
    pool = scale_notes(67 + octave_shift, 86 + octave_shift)
    rhythm_a = RHYTHMS[section][RNG.integers(len(RHYTHMS[section]))]
    rhythm_b = RHYTHMS[section][RNG.integers(len(RHYTHMS[section]))]
    notes = []
    current = 72 + octave_shift
    motif = None
    for bar, name in enumerate(chords):
        rhythm = rhythm_a if bar % 2 == 0 else rhythm_b
        tones = [n for n in pool if n % 12 in [c % 12 for c in chord_notes(name)]]
        bar_notes = []
        if bar in (4, 5) and motif is not None:
            # Repete o motivo dos compassos 0-1, ajustado aos acordes atuais
            for st, ln, m in motif[bar - 4]:
                target = min(tones, key=lambda n: abs(n - m)) if st in (0, 8) else m
                bar_notes.append((st, ln, target))
        else:
            for k, st in enumerate(rhythm):
                nxt = rhythm[k + 1] if k + 1 < len(rhythm) else 16
                strong = st in (0, 8)
                if strong:
                    current = min(tones, key=lambda n: abs(n - current) + RNG.random() * 3)
                else:
                    idx = pool.index(min(pool, key=lambda n: abs(n - current)))
                    idx = int(np.clip(idx + RNG.choice([-2, -1, 1, 1, 2]), 0, len(pool) - 1))
                    current = pool[idx]
                ln = nxt - st if RNG.random() < 0.8 else max(1, (nxt - st) // 2)
                if bar == 7 and k == len(rhythm) - 1:
                    ln = 16 - st
                bar_notes.append((st, ln, current))
        if bar in (0, 1):
            motif = (motif or []) + [bar_notes]
        notes += [(bar * 16 + st, ln, m) for st, ln, m in bar_notes]
    return notes


# ---------------------------------------------------------------------------
# Montagem
# ---------------------------------------------------------------------------
def main():
    total_bars = sum(len(c) for _, c in SECTIONS)
    n = int(round(total_bars * BAR * SR))
    L = np.zeros(n)
    R = np.zeros(n)
    drums = np.zeros(n)
    duck = np.ones(n)  # pulsação dos pads/acordes com o bumbo (sidechain)
    lead = np.zeros(n)

    def put(buf, sig, t0, gain=1.0):
        i = int(round(t0 * SR)) % n
        end = i + len(sig)
        if end <= n:
            buf[i:end] += sig * gain
        else:
            first = n - i
            buf[i:] += sig[:first] * gain
            buf[:end - n] += sig[first:] * gain

    def stereo(sig, t0, gain=1.0, pan=0.0):
        put(L, sig, t0, gain * np.sqrt(0.5 * (1 - pan)) * 1.414)
        put(R, sig, t0, gain * np.sqrt(0.5 * (1 + pan)) * 1.414)

    K, S, H, HO = kick(), snare(), hat(), hat(True)
    bar0 = 0
    for section, chords in SECTIONS:
        chorus = section == "refrao"
        bridge = section == "ponte"
        for b, name in enumerate(chords):
            t_bar = (bar0 + b) * BAR
            notes = chord_notes(name)
            # Bateria
            for beat in range(4):
                tb = t_bar + beat * BEAT
                if (chorus or beat in (0, 2) or (section == "pre" and b >= 4)) and not (bridge and beat == 2 and b < 4):
                    put(drums, K, tb, 0.55)
                    i = int(round(tb * SR)) % n
                    m = int(0.18 * SR)
                    seg = np.minimum(np.arange(m) / (0.18 * SR), 1.0) ** 0.6
                    idx = (i + np.arange(m)) % n
                    duck[idx] = np.minimum(duck[idx], 0.35 + 0.65 * seg)
                if beat in (1, 3) and not (bridge and b < 2):
                    put(drums, S, tb, 0.8)
                for half in range(2):
                    th = tb + half * BEAT / 2
                    if half == 1 and (chorus or section == "pre"):
                        put(drums, HO, th, 0.35)
                    else:
                        put(drums, H, th, 0.3 if half == 0 else 0.45)
            if b == 7:  # virada no fim de cada seção
                for k in range(4):
                    put(drums, S, t_bar + 3 * BEAT + k * STEP, 0.35 + 0.15 * k)
            # Baixo: oitavas em colcheias (no refrão), notas longas na ponte
            root = notes[0] - 24
            if bridge:
                stereo(bass_note(root, BAR * 0.95), t_bar, 0.4)
            else:
                for k in range(8):
                    m = root + (12 if (k % 2 == 1 and chorus) else 0)
                    stereo(bass_note(m, BEAT / 2 * 0.9), t_bar + k * BEAT / 2, 0.36)
            # Acordes: pad sempre, stabs no contratempo (verso/pré/refrão)
            p = pad(notes, BAR * 1.02)
            put(L, p, t_bar, 0.24 * (1.3 if chorus else 1.0))
            put(R, p, t_bar + 0.012, 0.24 * (1.3 if chorus else 1.0))
            if not bridge:
                for k in (1, 3, 4, 6):
                    st = stab([x + 12 for x in notes], STEP * 1.6)
                    stereo(st, t_bar + k * BEAT / 2, 0.2, -0.35 if k % 2 else 0.35)
            # Arpejo em semicolcheias
            arp = notes + [notes[0] + 12, notes[1] + 12]
            for k in range(16):
                if bridge and k % 2:
                    continue
                m = arp[[0, 1, 2, 3, 4, 3, 2, 1][k % 8]] + 12
                stereo(arp_note(m, STEP * 0.9), t_bar + k * STEP, 0.12 if not chorus else 0.15, 0.5 if k % 2 else -0.5)
        # Melodia
        shift = 5 if chorus else 0
        for st, ln, m in make_melody(section, chords, shift if chorus else 0):
            note = lead_note(m, ln * STEP * 0.95)
            put(lead, note, bar0 * BAR + st * STEP, 0.6 if chorus else 0.5)
        bar0 += len(chords)

    # Eco estéreo (pingue-pongue) na melodia, circular para o loop fechar
    d = int(round(BEAT * 0.75 * SR))
    echo_l = np.zeros(n)
    echo_r = np.zeros(n)
    src = lead.copy()
    for k in range(1, 5):
        tap = np.roll(src, d * k) * (0.38 ** k)
        if k % 2:
            echo_r += tap
        else:
            echo_l += tap
    echo_l = spectral_lowpass(echo_l, 3500)
    echo_r = spectral_lowpass(echo_r, 3500)

    L = L * duck + drums + lead + echo_l
    R = R * duck + drums + lead + echo_r
    mix = np.stack([L, R], axis=1)
    # Graves um pouco mais limpos e compressão suave (mantém a dinâmica entre seções)
    mix = np.stack([spectral_highpass(mix[:, 0], 35), spectral_highpass(mix[:, 1], 35)], axis=1)
    mix /= np.abs(mix).max()
    mix = np.tanh(mix * 1.15) / np.tanh(1.15) * 0.9
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "race_theme.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((mix * 32767).astype("<i2").tobytes())
    print("Música gerada: %s (%.1f s)" % (os.path.abspath(path), n / SR))


if __name__ == "__main__":
    main()
