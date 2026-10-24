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


# --- Sound update (0.20, owner 2026-10-24: only ADD sounds, keep today's). Each below has its own seed. ---

def _env(t, attack, decay):
    return min(1.0, t / attack) * math.exp(-t * decay) if attack > 0 else math.exp(-t * decay)


def _highpass(xs, smooth=0.85):
    low, out = 0.0, []
    for x in xs:
        low = low * smooth + x * (1 - smooth)
        out.append(x - low)
    return out


def step_wood(variant):
    """Boot on floorboards: a hollow knock (a low body and a short wooden ring), a little board creak on one variant."""
    random.seed(1000 + variant)
    n = length(0.2)
    nz = noise(n, 0.4)
    out, phase, ring = [], 0.0, 0.0
    base = 120 + variant * 22
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (base + 50 * math.exp(-t * 50)) / RATE
        ring += 2 * math.pi * (430 + variant * 40) / RATE
        knock = math.sin(phase) * math.exp(-t * 38) + math.sin(ring) * 0.35 * math.exp(-t * 60)
        out.append(knock + nz[i] * 0.35 * math.exp(-t * 70))
    if variant == 2:
        for i in range(length(0.12)):
            t = i / RATE
            k = length(0.05) + i
            if k < n:
                out[k] += math.sin(2 * math.pi * (300 + 900 * t) * t) * 0.12 * math.sin(math.pi * i / length(0.12))
    return out


def step_metal(variant):
    """Boot on sheet metal or a metal stair: a dull thud under a short, out-of-tune ring."""
    random.seed(1100 + variant)
    n = length(0.4)
    nz = noise(n, 0.3)
    partials = [(620 + variant * 55, 1.0), (1010 + variant * 70, 0.6), (1730 + variant * 40, 0.4), (2610, 0.25)]
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (110 + 40 * math.exp(-t * 45)) / RATE
        ring = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t * (14 + 6 * k)) for k, (f, a) in enumerate(partials))
        out.append(math.sin(phase) * math.exp(-t * 40) + ring * 0.28 + nz[i] * 0.3 * math.exp(-t * 90))
    return out


def step_concrete(variant):
    """Boot on concrete or tile: a hard, short heel click and a small thud, with a touch of grit."""
    random.seed(1200 + variant)
    n = length(0.13)
    sharp = _highpass(noise(n, 0.1), 0.7)
    grit = noise(n, 0.5)
    out, phase = [], 0.0
    base = 95 + variant * 15
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (base + 70 * math.exp(-t * 60)) / RATE
        out.append(math.sin(phase) * 0.8 * math.exp(-t * 55) + sharp[i] * 0.9 * math.exp(-t * 110)
                   + grit[i] * 0.25 * math.exp(-t * 35))
    return out


def step_water(variant):
    """Wading: a slosh (soft noise that swells and fades) with a few bubbly blips."""
    random.seed(1300 + variant)
    n = length(0.34)
    nz = noise(n, 0.6 + variant * 0.05)
    out = [nz[i] * _env(i / RATE, 0.025, 9.0) for i in range(n)]
    for _ in range(6):
        at = int(RATE * random.uniform(0.01, 0.2))
        f0 = random.uniform(350, 900)
        for i in range(length(0.04)):
            if at + i >= n:
                break
            t = i / RATE
            out[at + i] += math.sin(2 * math.pi * f0 * (1 + 6 * t) * t) * 0.25 * math.exp(-t * 80)
    return out


def rustle(variant):
    """Pushing through a bush: a dry leafy rustle (bright noise, crackling on and off)."""
    random.seed(1400 + variant)
    n = length(0.38)
    bright = _highpass(noise(n, 0.2), 0.8)
    out, crackle = [], 0.0
    for i in range(n):
        if i % 220 == 0:
            crackle = random.uniform(0.2, 1.0)
        t = i / n
        out.append(bright[i] * crackle * math.sin(math.pi * t) ** 1.2)
    return out


def distant_shot():
    """A shot far off (0.20.1): a dull boom with no crack (the air ate the highs) and a long rolling echo."""
    random.seed(1500)
    n = length(1.6)
    nz = noise(n, 0.9)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (55 + 40 * math.exp(-t * 12)) / RATE
        out.append(math.sin(phase) * math.exp(-t * 9) + nz[i] * 2.5 * _env(t, 0.01, 7))
    for delay, gain in ((0.22, 0.45), (0.5, 0.3), (0.85, 0.18)):   # (echoes off the hills and buildings)
        d = length(delay)
        for i in range(n - 1, d - 1, -1):
            out[i] += out[i - d] * gain * 0.6
    return [math.tanh(x * 1.5) for x in out]


def snap(variant):
    """A bullet passing close (0.20.1): a sharp supersonic crack, then a short falling whizz."""
    random.seed(1600 + variant)
    n = length(0.2)
    hiss = _highpass(noise(n, 0.3), 0.6)
    out = []
    for i in range(n):
        t = i / RATE
        crack = (1.0 if i < length(0.0012) else -0.8 if i < length(0.0026) else 0.0)
        whizz = hiss[i] * _env(t, 0.004, 22) * 0.6 + math.sin(2 * math.pi * (2400 - 5000 * t) * t) * 0.15 * math.exp(-t * 25)
        out.append(crack + whizz)
    return out


# 0.20.2: movement and the world.

def _thud(seconds, f_from, f_to, drop, decay, grit=0.3, grit_smooth=0.5, grit_decay=40):
    n = length(seconds)
    nz = noise(n, grit_smooth)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (f_to + (f_from - f_to) * math.exp(-t * drop)) / RATE
        out.append(math.sin(phase) * math.exp(-t * decay) + nz[i] * grit * math.exp(-t * grit_decay))
    return out


def _cloth(seconds, smooth=0.75, peak=0.3):
    """A cloth swish: smoothed noise swelling to `peak` (0-1 of the way) and fading."""
    n = length(seconds)
    nz = noise(n, smooth)
    return [nz[i] * math.sin(math.pi * min(1.0, (i / n) / (2 * peak) if i / n < peak else 0.5 + (i / n - peak) / (2 * (1 - peak)))) for i in range(n)]


def _creak(seconds, f0, f1, rasp=0.5):
    """A hinge creak: a buzzy tone sliding from f0 to f1, grinding in little pulses."""
    n = length(seconds)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        phase += 2 * math.pi * (f0 + (f1 - f0) * t) / RATE
        pulse = 0.6 + 0.4 * math.sin(2 * math.pi * 23 * i / RATE + 3 * math.sin(i / RATE * 7))
        buzz = math.sin(phase) + rasp * math.sin(phase * 2.01) + rasp * 0.6 * math.sin(phase * 3.03)
        out.append(buzz * pulse * math.sin(math.pi * t) ** 0.6 * 0.5)
    return out


def _mix(a, b, at=0.0, gain=1.0):
    start = length(at)
    out = list(a) + [0.0] * max(0, start + len(b) - len(a))
    for i, x in enumerate(b):
        out[start + i] += x * gain
    return out


def jump():
    random.seed(1700)
    return _mix(_cloth(0.18, 0.8, 0.25), _thud(0.06, 160, 90, 50, 60, 0.4), 0.0, 0.5)


def land():
    random.seed(1701)
    return _mix(_thud(0.3, 140, 45, 25, 16, 0.6, 0.6, 22), _cloth(0.15, 0.8, 0.2), 0.0, 0.4)


def vault():
    """Hands slapping onto the top, then a scuffle of boots and cloth over it."""
    random.seed(1702)
    slap = [x for x in _thud(0.05, 300, 180, 60, 80, 0.8, 0.2, 90)]
    return _mix(_mix(slap, _cloth(0.35, 0.7, 0.4), 0.03, 0.7), _thud(0.08, 120, 80, 40, 50, 0.5), 0.25, 0.6)


def rung():
    """A boot on a ladder rung: a short knock with a little metal ring."""
    random.seed(1703)
    n = length(0.18)
    return [x + 0.25 * math.sin(2 * math.pi * 1250 * i / RATE) * math.exp(-i / RATE * 30)
            for i, x in enumerate(_thud(0.18, 200, 140, 60, 45, 0.3, 0.3, 80))][:n]


def prone():
    random.seed(1704)
    return _mix(_cloth(0.3, 0.8, 0.3), _thud(0.2, 110, 60, 30, 25, 0.5, 0.7, 20), 0.12, 0.8)


def door_open():
    random.seed(1705)
    return _mix(click(0.03, 1500, 120, 0.1), _creak(0.55, 330, 520, 0.6), 0.02, 0.8)


def door_close():
    random.seed(1706)
    return _mix(_creak(0.2, 480, 380, 0.4), _mix(_thud(0.22, 150, 70, 35, 22, 0.5), click(0.03, 1800, 130, 0.0), 0.04, 0.7),
                0.15, 1.2)


def locked():
    """Trying a locked door: the handle rattling against the lock."""
    random.seed(1707)
    out = []
    for k in range(4):
        out += click(0.04, 700 + k * 60, 70, 0.3) + silence(0.035)
    return out


def unlock():
    """A key turning: two clicks and the bolt clunking back."""
    random.seed(1708)
    return click(0.025, 2600, 150, 0.0) + silence(0.12) + click(0.03, 2200, 140, 0.0) + silence(0.08) + \
        [x * 0.9 for x in _thud(0.18, 400, 200, 50, 35, 0.6, 0.2, 60)]


def heavy_door():
    """The bank vault / bunker door swinging: a deep grinding rumble, then a heavy clunk."""
    random.seed(1709)
    n = length(1.4)
    nz = noise(n, 0.93)
    grind = [nz[i] * 4 * math.sin(math.pi * i / n) * (0.7 + 0.3 * math.sin(2 * math.pi * 9 * i / RATE)) for i in range(n)]
    return _mix(_mix(grind, _creak(1.2, 70, 95, 0.9), 0.1, 0.5), _thud(0.5, 90, 40, 20, 9, 0.6, 0.6, 15), 1.3, 1.3)


def rummage():
    """Searching through a container: bursts of rustling and things knocking about."""
    random.seed(1710)
    out = silence(1.3)
    for _ in range(9):
        at = random.uniform(0.0, 1.1)
        out = _mix(out, _cloth(random.uniform(0.08, 0.2), random.uniform(0.3, 0.6), 0.3), at, random.uniform(0.4, 0.9))
    for _ in range(4):
        at = random.uniform(0.1, 1.1)
        out = _mix(out, _thud(0.06, random.uniform(300, 700), 200, 50, 70, 0.5, 0.2, 90), at, 0.5)
    return out[:length(1.3)]


def safe():
    """Opening a safe: the dial ticking round, the handle, and the heavy door creaking open."""
    random.seed(1711)
    out = []
    for k in range(8):
        out += click(0.012, 3200, 250, 0.0) + silence(0.045 + 0.01 * (k % 3))
    out += silence(0.1) + [x * 0.8 for x in _thud(0.12, 500, 260, 60, 45, 0.6, 0.2, 70)]
    return _mix(out, _creak(0.5, 160, 210, 0.8), len(out) / RATE - 0.02, 0.6)


def impact(kind):
    """A bullet hitting: dirt (a dull puff), wood (a thock), metal (a ping), concrete (a sharp chip)."""
    random.seed(1720 + ["dirt", "wood", "metal", "concrete"].index(kind))
    if kind == "dirt":
        return _thud(0.14, 160, 70, 50, 35, 0.9, 0.7, 30)
    if kind == "wood":
        return [x + 0.4 * math.sin(2 * math.pi * 620 * i / RATE) * math.exp(-i / RATE * 45)
                for i, x in enumerate(_thud(0.15, 380, 220, 60, 50, 0.5, 0.3, 70))]
    if kind == "metal":
        n = length(0.45)
        return [math.exp(-i / RATE * 9) * (math.sin(2 * math.pi * 2350 * i / RATE) + 0.6 * math.sin(2 * math.pi * 3710 * i / RATE)
                + 0.3 * math.sin(2 * math.pi * 1180 * i / RATE)) * 0.5 + (0.8 * math.exp(-i / RATE * 200) * random.uniform(-1, 1))
                for i in range(n)]
    sharp = _highpass(noise(length(0.2), 0.1), 0.6)
    return [sharp[i] * math.exp(-i / RATE * 45) + 0.4 * math.sin(2 * math.pi * 900 * i / RATE) * math.exp(-i / RATE * 70)
            for i in range(len(sharp))]


# 0.20.3: items and guns.

def bandage():
    """Unrolling and tearing a bandage: a few papery rips."""
    random.seed(1800)
    out = silence(0.9)
    for k, at in enumerate((0.0, 0.28, 0.55)):
        rip = _highpass(noise(length(0.18), 0.35), 0.75)
        rip = [x * math.sin(math.pi * i / len(rip)) * (0.6 + 0.4 * random.random()) for i, x in enumerate(rip)]
        out = _mix(out, rip, at, 0.8 + 0.1 * k)
    return out


def medkit():
    """A medkit: a zip, then rustling through it."""
    random.seed(1801)
    zip_n = length(0.4)
    zipper = [random.uniform(-1, 1) * (1.0 if (i // 90) % 2 else 0.25) * math.sin(math.pi * i / zip_n) for i in range(zip_n)]
    out = _mix(_highpass(zipper, 0.6), _cloth(0.4, 0.6, 0.4), 0.45, 0.8)
    return _mix(out, _cloth(0.3, 0.5, 0.3), 0.75, 0.6)


def drink():
    """An energy drink: the can cracking open with a fizz, then three gulps."""
    random.seed(1802)
    crack = [x * math.exp(-i / RATE * 60) for i, x in enumerate(_highpass(noise(length(0.05), 0.1), 0.5))]
    fizz = [x * 0.3 * math.exp(-i / RATE * 6) for i, x in enumerate(_highpass(noise(length(0.4), 0.1), 0.3))]
    out = _mix(crack, fizz, 0.02)
    for k in range(3):
        out = _mix(out, _thud(0.12, 260, 150, 30, 30, 0.3, 0.8, 30), 0.5 + 0.3 * k, 0.8)
    return out


def pin():
    """Pulling a grenade's pin: a scrape and a bright ring."""
    random.seed(1803)
    scrape = [x * math.sin(math.pi * i / length(0.08)) for i, x in enumerate(_highpass(noise(length(0.08), 0.2), 0.7))]
    ring = [math.sin(2 * math.pi * 3100 * i / RATE) * math.exp(-i / RATE * 18) * 0.5 for i in range(length(0.35))]
    return _mix(scrape, ring, 0.07)


def draw():
    """Swapping guns: cloth, then the gun clacking into the hands."""
    random.seed(1804)
    return _mix(_cloth(0.2, 0.7, 0.3), _mix(click(0.04, 900, 70, 0.3), click(0.03, 1500, 110, 0.1), 0.05), 0.15, 0.9)


def aim():
    """Raising the gun to the eye: a short soft cloth rustle."""
    random.seed(1805)
    return _cloth(0.16, 0.8, 0.35)


# 0.20.5: ambience. The loops' ends are crossfaded into their starts so they repeat without a seam
# (their .import files set edit/loop_mode=2).

def _seamless(xs, fade=0.5):
    f = length(fade)
    body = xs[:len(xs) - f]
    for i in range(f):
        w = i / f
        body[i] = body[i] * w + xs[len(xs) - f + i] * (1 - w)
    return body


def _lowpass(xs, smooth):
    low, out = 0.0, []
    for x in xs:
        low = low * smooth + x * (1 - smooth)
        out.append(low)
    return out


def wind():
    """Wind outdoors: low rushing noise that swells and drops slowly."""
    random.seed(1900)
    n = length(10.5)
    air = _lowpass(noise(n, 0.97), 0.6)
    gust = [0.55 + 0.25 * math.sin(2 * math.pi * i / n * 2 + 1.0) + 0.2 * math.sin(2 * math.pi * i / n * 5) for i in range(n)]
    return _seamless([a * g for a, g in zip(air, gust)])


def woods():
    """The woods: birds chirping and trilling now and then over faint insects."""
    random.seed(1901)
    n = length(12.5)
    out = [x * 0.04 * (0.6 + 0.4 * math.sin(2 * math.pi * 30 * i / RATE)) for i, x in enumerate(_highpass(noise(n, 0.1), 0.5))]
    for _ in range(14):
        at = random.uniform(0.0, 11.5)
        f0 = random.uniform(2200, 4200)
        notes = random.randint(1, 5)
        for k in range(notes):
            dur = random.uniform(0.04, 0.12)
            up = random.uniform(-0.4, 0.6)
            chirp = [math.sin(2 * math.pi * f0 * (1 + up * i / length(dur)) * i / RATE) * math.sin(math.pi * i / length(dur)) * 0.35
                     for i in range(length(dur))]
            out = _mix(out, chirp, at + k * (dur + 0.04))
    return _seamless(out[:n])


def creek():
    """Running water: a soft babble (bubbly noise rising and falling quickly)."""
    random.seed(1902)
    n = length(6.5)
    babble = _highpass(_lowpass(noise(n, 0.3), 0.5), 0.9)
    wob = _lowpass([random.uniform(0.2, 1.0) for _ in range(n)], 0.995)
    out = [b * w for b, w in zip(babble, wob)]
    for _ in range(40):
        at = random.uniform(0, 6.3)
        f0 = random.uniform(400, 1200)
        out = _mix(out, [math.sin(2 * math.pi * f0 * (1 + 4 * i / RATE) * i / RATE) * 0.08 * math.exp(-i / RATE * 60)
                         for i in range(length(0.05))], at)
    return _seamless(out[:n])


def waterfall():
    """The waterfall: a steady loud rush."""
    random.seed(1903)
    n = length(6.5)
    rush = _lowpass(noise(n, 0.2), 0.3)
    deep = _lowpass(noise(n, 0.9), 0.5)
    return _seamless([r * 0.7 + d * 2.0 for r, d in zip(rush, deep)])


def room():
    """Room tone indoors: a faint low hum and still air."""
    random.seed(1904)
    n = length(6.5)
    air = _lowpass(noise(n, 0.95), 0.8)
    return _seamless([a * 3.0 + 0.05 * math.sin(2 * math.pi * 60 * i / RATE) for i, a in enumerate(air)])


def rumble(variant):
    """The war far off: a distant artillery thump rolling away (no crack: it's miles off)."""
    random.seed(1910 + variant)
    n = length(3.2)
    roll = _lowpass(noise(n, 0.95), 0.7)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (35 + 25 * math.exp(-t * 4)) / RATE
        out.append(math.sin(phase) * _env(t, 0.03, 2.5) + roll[i] * 6.0 * _env(t, 0.08, 1.4))
    if variant == 2:   # (a second, further one)
        out = _mix(out, [x * 0.5 for x in out[:length(2.0)]], 0.9)[:n]
    return out


# 0.20.6: UI. Soft and low, like sell() (the owner found a bright ring annoying).

def _note(freq, seconds, decay=18, attack=0.004, square=0.0):
    out = []
    for i in range(length(seconds)):
        t = i / RATE
        x = math.sin(2 * math.pi * freq * t)
        if square:
            x = x * (1 - square) + (1.0 if x > 0 else -1.0) * square
        out.append(x * math.exp(-t * decay) * min(1.0, t / attack))
    return out


def ui_click():
    random.seed(2000)
    return [x * 0.6 for x in click(0.025, 1100, 160, 0.4)]


def ui_equip():
    random.seed(2001)
    return _mix(_cloth(0.14, 0.75, 0.3), click(0.035, 800, 90, 0.3), 0.08, 0.8)


def ui_buy():
    """Buying: a couple of coins clinking down onto the counter, softly."""
    random.seed(2002)
    out = silence(0.4)
    for at, f in ((0.0, 1900), (0.07, 2300), (0.15, 2100)):
        out = _mix(out, [x * 0.35 for x in _note(f, 0.18, 35)], at)
    return _mix(out, [x * 0.4 for x in noise(length(0.03), 0.5)], 0.0)


def ui_box():
    """Opening one of Ming's boxes: a cardboard rip, then a soft rising three-note twinkle."""
    random.seed(2003)
    rip = [x * math.sin(math.pi * i / length(0.25)) for i, x in enumerate(_highpass(noise(length(0.25), 0.4), 0.8))]
    out = rip + silence(0.05)
    for k, f in enumerate((523, 659, 784)):
        out = _mix(out, [x * 0.5 for x in _note(f, 0.35, 10)], 0.28 + 0.1 * k)
    return out


def ui_start():
    """START RAID: a radio chirp and a low drum hit."""
    random.seed(2004)
    return _mix(alert(), _thud(0.6, 110, 55, 12, 6, 0.4, 0.8, 8), 0.2, 1.4)


def ui_beep(high):
    return _note(1320 if high else 880, 0.09, 30, 0.003, 0.3)


def ui_extracted():
    """Made it out: a soft rising chord."""
    random.seed(2005)
    out = silence(1.2)
    for k, f in enumerate((392, 494, 587, 784)):
        out = _mix(out, [x * 0.35 for x in _note(f, 1.0 - 0.12 * k, 3.5, 0.02)], 0.12 * k)
    return out


def ui_died():
    """Killed / missing in action: a low falling drone hit."""
    random.seed(2006)
    n = length(2.0)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (98 - 30 * t / 2.0) / RATE
        out.append((math.sin(phase) + 0.4 * math.sin(phase * 1.5) + 0.25 * math.sin(phase * 2.01)) * _env(t, 0.02, 1.6))
    return _mix(out, _thud(0.5, 90, 40, 15, 8, 0.4, 0.8, 10), 0.0, 0.8)


def main_sound_update():
    (OUT / "steps").mkdir(exist_ok=True)
    for v in range(3):
        write(f"steps/wood{v + 1}.wav", step_wood(v))
        write(f"steps/metal{v + 1}.wav", step_metal(v))
        write(f"steps/concrete{v + 1}.wav", step_concrete(v))
        write(f"steps/water{v + 1}.wav", step_water(v))
    for v in range(2):
        write(f"steps/rustle{v + 1}.wav", rustle(v))
    write("distant_shot.wav", distant_shot())
    for v in range(2):
        write(f"snap{v + 1}.wav", snap(v))
    (OUT / "world").mkdir(exist_ok=True)
    for name, fn in (("jump", jump), ("land", land), ("vault", vault), ("rung", rung), ("prone", prone),
                     ("door_open", door_open), ("door_close", door_close), ("locked", locked), ("unlock", unlock),
                     ("heavy_door", heavy_door), ("rummage", rummage), ("safe", safe)):
        write(f"world/{name}.wav", fn())
    for kind in ("dirt", "wood", "metal", "concrete"):
        write(f"world/impact_{kind}.wav", impact(kind))
    (OUT / "items").mkdir(exist_ok=True)
    for name, fn in (("bandage", bandage), ("medkit", medkit), ("drink", drink), ("pin", pin), ("draw", draw),
                     ("aim", aim)):
        write(f"items/{name}.wav", fn())
    (OUT / "ambience").mkdir(exist_ok=True)
    for name, fn in (("wind", wind), ("woods", woods), ("creek", creek), ("waterfall", waterfall), ("room", room)):
        write(f"ambience/{name}.wav", fn())
    for v in range(3):
        write(f"ambience/rumble{v + 1}.wav", rumble(v))
    (OUT / "ui").mkdir(exist_ok=True)
    for name, fn in (("click", ui_click), ("equip", ui_equip), ("buy", ui_buy), ("box", ui_box), ("start", ui_start),
                     ("extracted", ui_extracted), ("died", ui_died)):
        write(f"ui/{name}.wav", fn())
    write("ui/beep.wav", ui_beep(False))
    write("ui/beep_last.wav", ui_beep(True))


if __name__ == "__main__":
    main()
    main_sound_update()
