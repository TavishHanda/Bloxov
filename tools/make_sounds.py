"""Generates the placeholder sound effects in audio/ (no external assets needed).

Run from the repo root:  python3 tools/make_sounds.py
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "audio"
random.seed(1)


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.9 / peak
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))


def noise(n, smooth=0.0):
    out, last = [], 0.0
    for _ in range(n):
        last = last * smooth + random.uniform(-1, 1) * (1 - smooth)
        out.append(last)
    return out


def length(seconds):
    return int(RATE * seconds)


def shot():
    n = length(0.38)
    nz = noise(n, 0.35)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        freq = 50 + 110 * math.exp(-t * 25)
        phase += 2 * math.pi * freq / RATE
        crack = nz[i] * math.exp(-t * 22)
        thump = math.sin(phase) * math.exp(-t * 14) * 1.2
        out.append(math.tanh((crack + thump) * 2.0))
    return out


def tone(freqs, seconds, decay):
    n = length(seconds)
    return [sum(math.sin(2 * math.pi * f * i / RATE) for f in freqs) * math.exp(-i / RATE * decay) for i in range(n)]


def kill():
    a = tone([880, 1760], 0.09, 25)
    b = tone([1320, 2640], 0.22, 14)
    return a + b


def click(seconds=0.05, freq=1400, decay=90, smooth=0.1):
    nz = noise(length(seconds), smooth)
    return [(nz[i] * 0.7 + math.sin(2 * math.pi * freq * i / RATE) * 0.5) * math.exp(-i / RATE * decay) for i in range(len(nz))]


def silence(seconds):
    return [0.0] * length(seconds)


def mag_in():
    return click(0.06, 900, 70) + silence(0.12) + click(0.07, 1300, 60) + silence(0.05) + click(0.05, 1700, 80)


def hurt():
    n = length(0.3)
    nz = noise(n, 0.7)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (60 + 80 * math.exp(-t * 20)) / RATE
        out.append((math.sin(phase) * 1.3 + nz[i] * 0.8) * math.exp(-t * 12))
    return out


def alert():
    """Radio chirp a scav makes when it spots you."""
    out = []
    for f, secs in ((1050, 0.07), (0, 0.03), (1400, 0.09)):
        nz = noise(length(secs), 0.2)
        for i in range(length(secs)):
            t = i / RATE
            square = 1.0 if math.sin(2 * math.pi * f * t) > 0 else -1.0
            out.append((square * 0.5 + nz[i] * 0.25) if f else nz[i] * 0.15)
    return out


def pop():
    n = length(0.35)
    nz = noise(n, 0.5)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (90 + 420 * math.exp(-t * 18)) / RATE
        out.append((math.sin(phase) + nz[i] * 0.6 * math.exp(-t * 30)) * math.exp(-t * 9))
    return out


def footstep(variant):
    """Short boot thud plus a gravelly crunch. Variants differ slightly so steps don't sound identical."""
    random.seed(100 + variant)
    n = length(0.14)
    nz = noise(n, 0.55 + variant * 0.08)
    out, phase = [], 0.0
    base = 85 + variant * 18
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (base + 60 * math.exp(-t * 40)) / RATE
        thud = math.sin(phase) * math.exp(-t * 45)
        crunch = nz[i] * math.exp(-t * 28) * 0.7
        out.append(thud + crunch)
    return out


def swing():
    """Knife whoosh: smoothed noise that swells and fades, sweeping from low to higher."""
    random.seed(200)
    n = length(0.22)
    out, low = [], 0.0
    for i in range(n):
        t = i / n
        smooth = 0.92 - 0.25 * t
        low = low * smooth + random.uniform(-1, 1) * (1 - smooth)
        out.append(low * math.sin(math.pi * t) ** 1.5)
    return out


def main():
    OUT.mkdir(exist_ok=True)
    write("shot.wav", shot())
    write("hit.wav", tone([1600, 2400], 0.07, 60))
    write("headshot.wav", tone([2200, 3300], 0.2, 20))
    write("kill.wav", kill())
    write("empty.wav", click(0.04, 2500, 120, 0.0))
    write("mag_out.wav", click(0.08, 700, 50))
    write("mag_in.wav", mag_in())
    write("hurt.wav", hurt())
    write("alert.wav", alert())
    write("pop.wav", pop())
    for v in range(3):
        write(f"step{v + 1}.wav", footstep(v))
    write("swing.wav", swing())


if __name__ == "__main__":
    main()
