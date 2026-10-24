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


def explosion():
    """Grenade blast: a deep boom (falling sine) under a long rumble of smoothed noise."""
    random.seed(300)
    n = length(1.4)
    nz = noise(n, 0.82)
    crack = noise(n, 0.2)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (38 + 90 * math.exp(-t * 9)) / RATE
        boom = math.sin(phase) * math.exp(-t * 3.5) * 1.4
        rumble = nz[i] * 3.0 * math.exp(-t * 2.6)
        snap = crack[i] * math.exp(-t * 40)
        out.append(math.tanh((boom + rumble + snap) * 1.6))
    return out


def throw():
    """Grenade throw: a short whoosh and a pin click."""
    random.seed(301)
    return click(0.03, 3000, 150, 0.0) + [s * 0.6 for s in swing()]


# --- Guns update (0.15.12): the new guns' own sounds. The Hound and Stinger keep shot.wav. Owner (0.15.13): he
# likes the game's sounds, so the new shots are small tweaks of shot(), not new sounds. ---

def gunshot(seconds, crack_smooth, crack_decay, thump_from, thump_to, thump_drop, thump_decay, thump_gain, drive,
            tail=0.0, tail_decay=4.0):
    """A shot: a noise crack plus a falling low thump, with an optional long echo tail of smoothed noise."""
    n = length(seconds)
    nz = noise(n, crack_smooth)
    echo = noise(n, 0.9)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (thump_to + thump_from * math.exp(-t * thump_drop)) / RATE
        crack = nz[i] * math.exp(-t * crack_decay)
        thump = math.sin(phase) * math.exp(-t * thump_decay) * thump_gain
        rumble = echo[i] * tail * math.exp(-t * tail_decay) * min(1.0, t * 30)
        out.append(math.tanh((crack + thump + rumble) * drive))
    return out


def shot_wasp():
    """SMG: the original shot (owner likes it), a little shorter and lighter so a fast burst stays clear."""
    random.seed(400)
    return gunshot(0.3, 0.3, 27, 115, 58, 27, 17, 1.0, 2.0)


def shot_mauler():
    """Shotgun: the original shot, a little deeper and fuller with a short rumble after it."""
    random.seed(401)
    return gunshot(0.48, 0.42, 17, 105, 44, 21, 11, 1.4, 2.1, tail=0.35, tail_decay=7.0)


def shot_lancer():
    """Sniper: the original shot, a little sharper with a short echo after it."""
    random.seed(402)
    return gunshot(0.6, 0.28, 21, 115, 48, 23, 12, 1.25, 2.15, tail=0.45, tail_decay=4.5)


def pump():
    """Shotgun pump: slide back (a rattly clack), then forward (a harder one)."""
    random.seed(403)
    return (click(0.07, 600, 45, 0.3) + silence(0.09) + click(0.05, 900, 60, 0.2) + silence(0.02)
            + click(0.06, 500, 55, 0.35))


def bolt():
    """Sniper bolt: lift, pull back, push forward, lock down."""
    random.seed(404)
    return (click(0.03, 1800, 120, 0.0) + silence(0.06) + click(0.07, 700, 50, 0.4) + silence(0.1)
            + click(0.06, 850, 55, 0.35) + silence(0.05) + click(0.03, 2000, 130, 0.0))


def shell_in():
    """One shell pushed into the shotgun's tube."""
    random.seed(405)
    return click(0.03, 1200, 110, 0.1) + click(0.05, 650, 70, 0.3)


def sell():
    """Selling an item (0.15.18; softer in 0.15.24, owner: "kinda annoying"): two quiet low notes, like coins
    dropped in a pouch, no bright ring."""
    random.seed(511)
    def note(freq, seconds):
        return [math.sin(2 * math.pi * freq * i / RATE) * math.exp(-i / RATE * 22)
                * min(1.0, i / (RATE * 0.004)) for i in range(length(seconds))]
    thud = [x * 0.35 for x in noise(length(0.03), 0.6)]
    return thud + note(660, 0.07) + note(880, 0.16)


def glass():
    """A window pane going: a sharp crack, then shards tinkling down (bright clicks that thin out)."""
    random.seed(900)
    n = length(0.6)
    nz = noise(n, 0.1)
    out = []
    for i in range(n):
        t = i / RATE
        out.append(nz[i] * math.exp(-t * 55) * 0.9)
    for k in range(22):
        at = int(RATE * random.uniform(0.02, 0.5))
        freq = random.uniform(2200, 5200)
        amp = random.uniform(0.15, 0.5) * math.exp(-at / RATE * 3.0)
        for i in range(length(0.05)):
            if at + i >= n:
                break
            out[at + i] += math.sin(2 * math.pi * freq * i / RATE) * amp * math.exp(-i / RATE * 90)
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
    write("explosion.wav", explosion())
    write("throw.wav", throw())
    # (New sounds go last, each with its own seed, so the ones above come out the same as before.)
    write("shot_wasp.wav", shot_wasp())
    write("shot_mauler.wav", shot_mauler())
    write("shot_lancer.wav", shot_lancer())
    write("pump.wav", pump())
    write("bolt.wav", bolt())
    write("shell_in.wav", shell_in())
    write("sell.wav", sell())
    write("glass.wav", glass())


if __name__ == "__main__":
    main()
