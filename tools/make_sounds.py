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


def shot_pistol():
    """Pistol (Sound 2.0, 0.30.0, owner: each gun recognisable by sound): shorter and brighter than the rifle, with
    less thump, so the Stinger is not the Hound at the same volume any more."""
    random.seed(405)
    return gunshot(0.24, 0.15, 34, 140, 75, 32, 24, 0.8, 2.2)


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
    """A bullet passing close (0.20.1; 0.20.9, owner: "kinda high pitched"): a dull crack, then a low falling whoosh."""
    random.seed(1600 + variant)
    n = length(0.22)
    hiss = _lowpass(noise(n, 0.6), 0.5)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        crack = (0.6 if i < length(0.003) else -0.45 if i < length(0.006) else 0.0)
        phase += 2 * math.pi * (700 - 1400 * t) / RATE
        whizz = hiss[i] * _env(t, 0.006, 16) * 0.9 + math.sin(phase) * 0.12 * math.exp(-t * 22)
        out.append(crack + whizz)
    return _lowpass(out, 0.35)


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
    return click(0.025, 1600, 150, 0.2) + silence(0.12) + click(0.03, 1400, 140, 0.2) + silence(0.08) + \
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
        out += click(0.012, 2000, 250, 0.2) + silence(0.045 + 0.01 * (k % 3))
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
        return [math.exp(-i / RATE * 9) * (math.sin(2 * math.pi * 1450 * i / RATE) + 0.6 * math.sin(2 * math.pi * 2230 * i / RATE)
                + 0.3 * math.sin(2 * math.pi * 760 * i / RATE)) * 0.5 + (0.8 * math.exp(-i / RATE * 200) * random.uniform(-1, 1))
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
    ring = [math.sin(2 * math.pi * 1800 * i / RATE) * math.exp(-i / RATE * 22) * 0.4 for i in range(length(0.3))]
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


def _centred(xs):
    """`xs` with its average removed, so a deep rumble does not carry a DC offset into the loop."""
    mean = sum(xs) / max(1, len(xs))
    return [x - mean for x in xs]


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
    for at, f in ((0.0, 1200), (0.07, 1450), (0.15, 1320)):
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
    return _note(990 if high else 660, 0.09, 30, 0.003, 0.15)


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


# 0.21.7: the hideout's toys (owner 2026-10-25: a radio you can switch on, darts, a light switch). New sounds only.

def radio():
    """The mess's radio: a slow little tune (soft keys over a bass and a quiet beat), thin and crackly like an old
    set's speaker. 16 s, and the tune comes back round to where it started, so it loops."""
    random.seed(2100)
    bar = 2.0
    n = length(bar * 8)
    out = [0.0] * n
    chords = ((220.0, 261.6, 329.6), (174.6, 220.0, 261.6), (130.8, 164.8, 196.0), (196.0, 246.9, 293.7))  # Am F C G

    def key(freq, at, seconds, gain):
        start = length(at)
        for i in range(min(length(seconds), n - start)):
            t = i / RATE
            x = math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(4 * math.pi * freq * t) * math.exp(-t * 6)
            out[start + i] += x * gain * min(1.0, t / 0.01) * math.exp(-t * 2.2)

    melody = (659.3, 587.3, 523.3, 440.0, 523.3, 587.3, 523.3, 493.9)
    for b in range(8):
        root, third, fifth = chords[b % 4]
        for f in (root, third, fifth):
            key(f, b * bar, bar, 0.16)
            key(f, b * bar + bar * 0.5, bar * 0.5, 0.08)
        key(root / 2, b * bar, bar * 0.45, 0.3)                                   # bass
        key(root / 2, b * bar + bar * 0.75, bar * 0.25, 0.22)
        if b >= 2:
            key(melody[b], b * bar + bar * 0.25, bar * 0.5, 0.14)
            key(melody[(b + 3) % 8], b * bar + bar * 0.75, bar * 0.4, 0.1)
        for beat in range(4):                                                    # kick, soft snare, hat
            at = length(b * bar + beat * bar / 4)
            if beat % 2 == 0:
                for i in range(min(length(0.15), n - at)):
                    t = i / RATE
                    out[at + i] += math.sin(2 * math.pi * (50 + 60 * math.exp(-t * 30)) * t) * math.exp(-t * 18) * 0.45
            else:
                nz = noise(length(0.12), 0.5)
                for i in range(min(len(nz), n - at)):
                    out[at + i] += nz[i] * math.exp(-i / RATE * 30) * 0.15
            hat = length(b * bar + beat * bar / 4 + bar / 8)
            hz = _highpass(noise(length(0.03), 0.0), 0.5)
            for i in range(min(len(hz), n - hat)):
                out[hat + i] += hz[i] * math.exp(-i / RATE * 120) * 0.08
    # The old speaker: no deep bass or bright highs, a faint hiss and crackle.
    out = _highpass(_lowpass(out, 0.55), 0.96)
    hiss = _highpass(noise(n, 0.3), 0.7)
    out = [x + h * 0.015 for x, h in zip(out, hiss)]
    for _ in range(60):
        at = random.randrange(n - 40)
        out[at] += random.uniform(-0.08, 0.08)
    return out


def radio_on():
    """Turning the radio's knob: a click and a burst of static settling."""
    random.seed(2101)
    st = [x * 0.5 * math.exp(-i / RATE * 9) for i, x in enumerate(_highpass(noise(length(0.35), 0.2), 0.6))]
    return _mix(click(0.04, 1100, 90, 0.2), st, 0.02, 0.6)


def dart():
    """A dart going into the board: a short dull thock."""
    random.seed(2102)
    return _mix(_thud(0.12, 700, 300, 40, 45, 0.5, 0.3, 80), click(0.02, 2200, 200, 0.1), 0.0, 0.4)


def light_switch():
    """The bunks' light switch: a heavy old toggle, clack."""
    random.seed(2103)
    return _mix(click(0.05, 900, 90, 0.2), click(0.04, 600, 70, 0.3), 0.03, 0.8)


def jukebox():
    """The hangout's jukebox (0.25.17): brighter and quicker than the mess radio, a bouncy major tune over a walking
    bass and a backbeat, through a bigger speaker. 16 s at 120 bpm, and it loops."""
    random.seed(2104)
    bar = 2.0
    n = length(bar * 8)
    out = [0.0] * n
    chords = ((261.6, 329.6, 392.0), (220.0, 261.6, 329.6), (174.6, 220.0, 261.6), (196.0, 246.9, 293.7))  # C Am F G

    def note(freq, at, seconds, gain, bright=0.5, decay=3.0):
        start = length(at)
        for i in range(min(length(seconds), n - start)):
            t = i / RATE
            x = math.sin(2 * math.pi * freq * t) + bright * math.sin(4 * math.pi * freq * t) * math.exp(-t * 4)
            x += 0.2 * bright * math.sin(6 * math.pi * freq * t) * math.exp(-t * 8)
            out[start + i] += x * gain * min(1.0, t / 0.005) * math.exp(-t * decay)

    melody = ((659.3, 784.0, 659.3, 587.3), (523.3, 587.3, 659.3, 523.3), (523.3, 440.0, 523.3, 587.3),
              (587.3, 659.3, 587.3, 493.9))
    for b in range(8):
        root, third, fifth = chords[b % 4]
        for k in range(4):                                                       # stabs on the off-beats
            for f in (root, third, fifth):
                note(f, b * bar + k * bar / 4 + bar / 8, bar / 8, 0.07, 0.8, 9.0)
        walk = (root / 2, third / 2, fifth / 2, third / 2)                       # the walking bass
        for k, f in enumerate(walk):
            note(f, b * bar + k * bar / 4, bar / 4, 0.32, 0.3, 4.0)
        if b >= 2:
            for k, f in enumerate(melody[b % 4]):
                note(f, b * bar + k * bar / 4, bar / 4 * (1.6 if k == 3 else 0.9), 0.11, 0.6, 3.5)
        for beat in range(4):                                                    # kick, snare on 2 and 4, hats
            at = length(b * bar + beat * bar / 4)
            if beat % 2 == 0:
                for i in range(min(length(0.15), n - at)):
                    t = i / RATE
                    out[at + i] += math.sin(2 * math.pi * (55 + 70 * math.exp(-t * 30)) * t) * math.exp(-t * 16) * 0.5
            else:
                nz = noise(length(0.14), 0.4)
                for i in range(min(len(nz), n - at)):
                    out[at + i] += nz[i] * math.exp(-i / RATE * 24) * 0.22
            for half in (0.0, 0.5):
                hat = length(b * bar + (beat + half) * bar / 4)
                hz = _highpass(noise(length(0.03), 0.0), 0.5)
                for i in range(min(len(hz), n - hat)):
                    out[hat + i] += hz[i] * math.exp(-i / RATE * 140) * 0.07
    out = _highpass(_lowpass(out, 0.35), 0.985)                                 # a jukebox speaker: fuller than the radio
    peak = max(abs(x) for x in out) or 1.0
    return [x / peak * 0.8 for x in out]


def main_hideout():
    (OUT / "world").mkdir(exist_ok=True)
    for name, fn in (("radio", radio), ("radio_on", radio_on),
                     ("dart", dart), ("switch", light_switch), ("jukebox", jukebox)):
        write(f"world/{name}.wav", fn())


# 0.30.2: the hideout's ambience, remade as a steady underground bunker (owner: it sounded like the ocean, and the
# random one-off noises had to go). Three quiet beds of different lengths (so they line up again only after many
# minutes): a deep room rumble, a low ventilation rumble and an electrical hum. No drips, ticks, creaks, clanks,
# vent breaths, dust or war rumbles. room.wav stays for the raid's indoors.

def bunker_air():
    """The bunker's deep room tone: a steady low rumble, no surf-like swell."""
    random.seed(2300)
    n = length(13.7)
    air = _centred(_lowpass(noise(n, 0.97), 0.88))
    deep = _centred(_lowpass(noise(n, 0.99), 0.99))
    return _seamless([a * 2.0 + d * 2.0 for a, d in zip(air, deep)], 1.5)


def bunker_vent():
    """The ventilation: a steady low fan rumble, no hiss and no breathing."""
    random.seed(2301)
    n = length(14.7)
    fan = _lowpass(noise(n, 0.9), 0.65)
    out = []
    for i in range(n):
        t = i / RATE
        out.append(fan[i] * 5.0 + 0.12 * math.sin(2 * math.pi * 96.0 * t))
    return _seamless(out, 1.5)


def bunker_hum():
    """The lights and the generator: a steady 50 Hz hum with its harmonics, no chug."""
    random.seed(2302)
    n = length(8.9)
    out = []
    for i in range(n):
        t = i / RATE
        beat = 0.95 + 0.05 * math.sin(2 * math.pi * 0.1 * t)
        out.append((math.sin(2 * math.pi * 50.0 * t) + 0.45 * math.sin(2 * math.pi * 100.0 * t)
                    + 0.12 * math.sin(2 * math.pi * 150.0 * t)) * beat)
    rough = _lowpass(noise(n, 0.97), 0.9)
    return _seamless([o * 0.6 + r * 0.8 for o, r in zip(out, rough)], 1.5)


def main_bunker():
    (OUT / "ambience").mkdir(exist_ok=True)
    for name, fn in (("bunker_air", bunker_air), ("bunker_vent", bunker_vent), ("bunker_hum", bunker_hum)):
        write(f"ambience/{name}.wav", fn())


# --- World life (0.28.0, owner: give the world some life; new sounds only). ---

def clock_tick(variant):
    """A grandfather clock's tick (0) or tock (1): a small dry wooden knock with a short metal click on top."""
    random.seed(2800 + variant)
    n = length(0.09)
    body = 900 if variant == 0 else 760
    grit = _highpass(noise(n, 0.2), 0.7)
    out = []
    for i in range(n):
        t = i / RATE
        knock = math.sin(2 * math.pi * body * t) * math.exp(-t * 90) * 0.7
        ring = math.sin(2 * math.pi * body * 3.7 * t) * math.exp(-t * 160) * 0.35
        out.append(knock + ring + grit[i] * math.exp(-t * 260) * 0.5)
    return out


def main_life():
    (OUT / "world").mkdir(exist_ok=True)
    for v in range(2):
        write(f"world/clock_tick{v + 1}.wav", clock_tick(v))


def main_pistol():
    """0.30.0: the pistol's own shot (the Stinger used to share the Hound's file). Written on its own so re-running it
    does not rewrite any of the sounds that were already in the game."""
    write("shot_pistol.wav", shot_pistol())


# --- More sounds (0.31.14, owner 2026-11-07: armor clinks, grenade bounces, downed/revive, the world's life, casings,
# breathing and a heartbeat, gear breaking, repairs). New sounds only, each with its own seed; written on their own
# (main_more), so re-running does not rewrite any sound that was already in the game. Kept soft and short: the
# owner wants players and AI to stay the loudest thing you hear.

def _ring(seconds, partials, decay, gain=1.0):
    """A struck piece of metal: a few inharmonic partials (freq, level) dying away at `decay`."""
    out = []
    for i in range(length(seconds)):
        t = i / RATE
        out.append(sum(a * math.sin(2 * math.pi * f * t) for f, a in partials) * math.exp(-t * decay) * gain)
    return out


def armor_hit():
    """A round stopped by a plate or a helmet: a dull thump with a short metal clink on top."""
    random.seed(3100)
    body = _thud(0.18, 220, 120, 50, 38, 0.35, 0.4, 70)
    clink = _ring(0.22, ((1720, 1.0), (2630, 0.6), (3910, 0.35)), 26, 0.55)
    tick = [x * math.exp(-i / RATE * 220) for i, x in enumerate(_highpass(noise(length(0.03), 0.1), 0.6))]
    return _mix(_mix(body, clink, 0.0, 0.8), tick, 0.0, 0.6)


def gear_break():
    """Armor or a helmet giving out: a sharp crack, then bits rattling."""
    random.seed(3101)
    crack = [x * math.exp(-i / RATE * 55) for i, x in enumerate(_highpass(noise(length(0.12), 0.15), 0.55))]
    out = _mix(crack, _thud(0.2, 170, 80, 40, 26, 0.5, 0.5, 40), 0.0, 0.7)
    for k in range(4):
        out = _mix(out, click(0.03, random.uniform(1100, 1900), 120, 0.3), 0.12 + 0.07 * k + random.uniform(0, 0.03), 0.5 - 0.08 * k)
    return out


def key_break():
    """A key on its last use: a small metal snap."""
    random.seed(3102)
    snap_ = [x * math.exp(-i / RATE * 140) for i, x in enumerate(_highpass(noise(length(0.04), 0.1), 0.5))]
    return _mix(snap_, _ring(0.16, ((3150, 1.0), (4480, 0.5)), 38, 0.45), 0.005)


def repair():
    """A trader fixing your gear: a wrench ratcheting a few times and a last clank."""
    random.seed(3103)
    out = silence(0.05)
    for k in range(5):
        out = _mix(out, click(0.025, 1300 + 40 * (k % 2), 160, 0.25), 0.04 + 0.075 * k, 0.8)
    return _mix(out, _mix(_thud(0.16, 420, 240, 55, 40, 0.5, 0.2, 70), _ring(0.25, ((1180, 1.0), (1830, 0.5)), 20, 0.35)), 0.47, 0.9)


def grenade_bounce():
    """A grenade landing and bouncing: a short heavy clunk with a little ring."""
    random.seed(3104)
    return _mix(_thud(0.14, 300, 150, 60, 45, 0.5, 0.3, 80), _ring(0.18, ((1320, 1.0), (2090, 0.5)), 30, 0.4))


def downed():
    """Going down: a body dropping and the gear on it rattling."""
    random.seed(3105)
    out = _mix(_cloth(0.25, 0.8, 0.3), _thud(0.35, 120, 45, 25, 14, 0.6, 0.6, 20), 0.12, 0.9)
    for k in range(3):
        out = _mix(out, click(0.03, random.uniform(800, 1400), 110, 0.3), 0.18 + 0.06 * k, 0.35)
    return out


def reviving():
    """Being patched up by a teammate: cloth and a bandage tearing."""
    random.seed(3106)
    rip = _highpass(noise(length(0.16), 0.35), 0.75)
    rip = [x * math.sin(math.pi * i / len(rip)) for i, x in enumerate(rip)]
    return _mix(_mix(_cloth(0.35, 0.7, 0.4), rip, 0.3, 0.7), _cloth(0.3, 0.75, 0.3), 0.55, 0.7)


def get_up():
    """Back on your feet: a cloth swish, gear shifting and a boot planting."""
    random.seed(3107)
    out = _mix(_cloth(0.35, 0.75, 0.35), click(0.03, 1000, 100, 0.3), 0.15, 0.4)
    return _mix(out, _thud(0.12, 150, 90, 45, 45, 0.4), 0.3, 0.6)


def crow(variant):
    """A crow's caw (one, or two for variant 1): a buzzy falling tone with a rasp."""
    random.seed(3110 + variant)
    out = []
    for c in range(1 + variant):
        n = length(0.2 + 0.03 * c)
        rasp = noise(n, 0.3)
        phase = 0.0
        caw = []
        for i in range(n):
            t = i / n
            phase += 2 * math.pi * (620 - 170 * t + 25 * c) / RATE
            x = math.sin(phase)
            buzz = (1.0 if x > 0 else -1.0) * 0.5 + x * 0.5 + 0.3 * math.sin(phase * 3.0)
            env = min(1.0, t / 0.08) * (1 - t) ** 0.7
            caw.append((buzz * 0.8 + rasp[i] * 0.35) * env)
        out += _lowpass(caw, 0.35) + silence(0.12)
    return out


def flag():
    """A flag in the wind: soft cloth flaps coming in irregular bursts. A 4 s loop."""
    random.seed(3112)
    n = length(4.0)
    out = [0.0] * n
    at = 0.0
    while at < 3.9:
        flap = _cloth(random.uniform(0.07, 0.13), 0.6, 0.2)
        for i, x in enumerate(flap):
            k = length(at) + i
            if k < n:
                out[k] += x * random.uniform(0.5, 1.0)
        at += random.uniform(0.09, 0.3)
    return _seamless(_lowpass(out, 0.3), 0.4)


def can(kind):
    """A tin can (0) or a bottle (1) knocked about: a couple of light knocks with a ring."""
    random.seed(3113 + kind)
    if kind == 0:
        hit = lambda: _mix(_thud(0.05, 900, 600, 60, 90, 0.4, 0.2, 120), _ring(0.12, ((2380, 1.0), (3470, 0.6)), 40, 0.5))
    else:
        hit = lambda: _ring(0.2, ((2620, 1.0), (4150, 0.35), (1310, 0.2)), 24, 0.7)
    return _mix(_mix(hit(), hit(), 0.09, 0.55), hit(), 0.16, 0.3)


def lamp_creak():
    """A hanging lamp knocked into a swing: a thin creak of the cable and a faint jingle."""
    random.seed(3115)
    return _mix(_creak(0.45, 520, 430, 0.3), _ring(0.12, ((2900, 1.0),), 35, 0.25), 0.02, 0.6)


def curtain():
    """Pushing past a curtain: a soft cloth swish."""
    random.seed(3116)
    return _lowpass(_cloth(0.4, 0.8, 0.3), 0.3)


def casing(variant):
    """A spent case landing: two or three tiny brass tinks."""
    random.seed(3120 + variant)
    base = (4200, 4650, 3900)[variant]
    out = silence(0.02)
    for k, (at, gain) in enumerate(((0.0, 1.0), (0.07 + 0.02 * variant, 0.5), (0.14 + 0.02 * variant, 0.25))):
        tink = _ring(0.07, ((base * (1 + 0.03 * k), 1.0), (base * 1.47, 0.4)), 70, gain)
        out = _mix(out, tink, at)
    return out


def heartbeat():
    """A heartbeat (lub-dub), soft and low, with a little knock so phone speakers carry it."""
    random.seed(3123)
    def beat(f, gain):
        return [x * gain for x in _thud(0.18, f * 1.8, f, 40, 26, 0.15, 0.6, 60)]
    return _mix(beat(80, 1.0), beat(70, 0.7), 0.26)


def breath():
    """Out of breath: a soft breath in and a longer breath out."""
    random.seed(3124)
    def air(seconds, peak, gain):
        nz = _lowpass(_highpass(noise(length(seconds), 0.2), 0.6), 0.55)
        n = len(nz)
        return [x * gain * math.sin(math.pi * min(1.0, (i / n) / (2 * peak) if i / n < peak else 0.5 + (i / n - peak) / (2 * (1 - peak)))) for i, x in enumerate(nz)]
    return _mix(air(0.35, 0.5, 0.6), air(0.55, 0.25, 1.0), 0.4)


def main_more():
    (OUT / "world").mkdir(exist_ok=True)
    for name, fn in (("armor_hit", armor_hit), ("gear_break", gear_break), ("key_break", key_break),
                     ("grenade_bounce", grenade_bounce), ("downed", downed), ("reviving", reviving),
                     ("get_up", get_up), ("flag", flag), ("lamp_creak", lamp_creak), ("curtain", curtain),
                     ("heartbeat", heartbeat), ("breath", breath)):
        write(f"world/{name}.wav", fn())
    for v in range(2):
        write(f"world/crow{v + 1}.wav", crow(v))
    write("world/can.wav", can(0))
    write("world/bottle.wav", can(1))
    for v in range(3):
        write(f"world/casing{v + 1}.wav", casing(v))
    (OUT / "ui").mkdir(exist_ok=True)
    write("ui/repair.wav", repair())


# --- Lively hideout (owner 2026-11-09): sounds tied to things you can see, and a shell now and then. Own seeds. ---

def shell_far():
    """A shell landing up top, heard through the rock: a deep, dull thump and a long low rumble, no highs at all."""
    random.seed(3301)
    thump = _thud(0.9, 70, 38, 6, 4.5, 0.0)
    roll = _lowpass(noise(length(3.2), 0.985), 0.97)
    roll = [x * 6.0 * min(1.0, i / RATE / 0.08) * math.exp(-i / RATE * 1.3) for i, x in enumerate(roll)]
    return _lowpass(_mix(thump, roll, 0.02, 0.8), 0.6)


def grit():
    """Grit trickling off the roof: dry little ticks that thin out, over a soft hiss."""
    random.seed(3302)
    n = length(1.8)
    out = [0.0] * n
    hiss = _highpass(noise(n, 0.3), 0.7)
    for i in range(n):
        out[i] = hiss[i] * 0.08 * math.exp(-i / RATE * 1.6) * min(1.0, i / RATE / 0.05)
    k = 0
    while k < 70:
        at = int(random.expovariate(1.4) * RATE * 0.5)
        if at < n - 400:
            tick = _highpass(noise(60, 0.1), 0.5)
            g = random.uniform(0.2, 0.6) * math.exp(-at / RATE * 1.2)
            for j, x in enumerate(tick):
                out[at + j] += x * g * math.exp(-j / 18)
        k += 1
    return out


def drip(variant):
    """A drop off the tap into the steel trough: a short plink with a falling pitch, and a little splash."""
    random.seed(3303 + variant)
    f = (1250, 1500)[variant]
    n = length(0.22)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * f * (1.0 + 0.6 * math.exp(-t * 60)) / RATE
        out.append(math.sin(phase) * math.exp(-t * 28) * min(1.0, t / 0.002))
    return _mix(out, [x * 0.15 for x in _highpass(noise(length(0.04), 0.2), 0.5)], 0.0)


def pipe_knock():
    """The water pipe knocking: two dull metal bangs with a short hollow ring."""
    random.seed(3305)
    bang = lambda g: [x * g for x in _mix(_thud(0.08, 260, 160, 50, 45, 0.3, 0.3, 90), _ring(0.4, ((410, 1.0), (1130, 0.4), (1870, 0.2)), 9, 0.5))]
    return _lowpass(_mix(bang(1.0), bang(0.6), 0.17), 0.3)


def generator():
    """The generator chugging, to loop: a small engine's low thumps (about 12 a second) over a rattle."""
    random.seed(3306)
    n = length(2.0)                                                   # (24 beats: it loops without a seam)
    out = []
    for i in range(n):
        t = i / RATE
        beat = (t * 12.0) % 1.0
        thump = math.sin(2 * math.pi * 55 * t) * math.exp(-beat * 7.0)
        out.append(thump + 0.25 * math.sin(2 * math.pi * 110 * t) * math.exp(-beat * 9.0))
    rattle = _highpass(_lowpass(noise(n, 0.5), 0.5), 0.9)
    out = [o + r * 0.25 * (0.5 + 0.5 * math.exp(-((i / RATE * 12.0) % 1.0) * 5.0)) for i, (o, r) in enumerate(zip(out, rattle))]
    return _seamless(_lowpass(out, 0.4), 0.25)                       # (3 beats faded over)


def rat():
    """A rat: a few quick scrabbles of claws, and a thin squeak."""
    random.seed(3307)
    out = [0.0] * length(0.9)
    for k in range(9):
        at = length(0.05 + k * 0.055 + random.uniform(0, 0.02))
        tick = _highpass(noise(90, 0.1), 0.6)
        for j, x in enumerate(tick):
            out[at + j] += x * 0.3 * math.exp(-j / 25)
    sq, phase = [], 0.0
    m = length(0.16)
    for i in range(m):
        t = i / m
        phase += 2 * math.pi * (3400 + 900 * math.sin(math.pi * t)) / RATE
        sq.append(math.sin(phase) * math.sin(math.pi * t) ** 0.8 * 0.35)
    return _mix(out, sq, 0.6)


def snore():
    """Someone asleep: a slow rasping breath in (a low, buzzing flutter) and a soft breath out."""
    random.seed(3308)
    n = length(1.3)
    out, phase = [], 0.0
    nz = _lowpass(noise(n, 0.5), 0.6)
    for i in range(n):
        t = i / n
        phase += 2 * math.pi * 38 / RATE
        flutter = 0.5 + 0.5 * math.sin(phase)
        swell = math.sin(math.pi * min(1.0, t / 0.55)) if t < 0.55 else 0.0
        out.append(nz[i] * (0.3 + 0.7 * flutter) * swell)
    breath_out = _lowpass(_cloth(0.6, 0.6, 0.2), 0.7)
    return _mix(_lowpass(out, 0.5), [x * 0.35 for x in breath_out], 0.68)


def wrench():
    """A wrench on the generator: a few ratchet clicks, then a knock of steel on steel."""
    random.seed(3309)
    out = []
    for k in range(5):
        out = _mix(out, [x * 0.35 for x in click(0.02, 3200, 260, 0.0)], 0.06 * k)
    return _mix(out, _mix(_thud(0.06, 700, 500, 60, 70, 0.4, 0.2, 120), _ring(0.3, ((1650, 1.0), (2480, 0.5), (4100, 0.2)), 18, 0.4)), 0.36, 0.8)


def purr():
    """The cat purring: a soft rumble of ~26 Hz pulses, swelling as it breathes in and out (a seamless loop)."""
    random.seed(3310)
    n = length(2.4)
    nz = _lowpass(noise(n, 0.4), 0.55)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        phase += 2 * math.pi * 26 / RATE
        pulse = max(0.0, math.sin(phase)) ** 3
        breath = 0.65 + 0.35 * math.sin(2 * math.pi * 2 * t)     # (two breaths a loop: in purrs a bit louder)
        out.append(nz[i] * pulse * breath)
    return _seamless(_centred(_lowpass(out, 0.35)), 0.2)


def meow():
    """A short, friendly cat's mew: a rising-then-falling voice through an "ee-ow" mouth."""
    random.seed(3311)
    n = length(0.55)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f0 = 520 + 260 * math.sin(math.pi * min(1.0, t * 1.4)) - 120 * t
        phase += 2 * math.pi * f0 / RATE
        voice = sum(math.sin(phase * h) / h for h in range(1, 7))
        # (the mouth opening: high bright harmonics early, darker at the end)
        bright = 1.0 - 0.6 * t
        voice = voice * (0.6 + 0.4 * bright) + 0.25 * math.sin(phase * 3) * bright
        env = min(1.0, t / 0.08) * (1.0 - t) ** 1.2
        out.append(voice * env * 0.4)
    return _lowpass(out, 0.3)


def main_lively():
    (OUT / "world").mkdir(exist_ok=True)
    for name, fn in (("shell_far", shell_far), ("grit", grit), ("pipe_knock", pipe_knock), ("generator", generator),
                     ("rat", rat), ("snore", snore), ("wrench", wrench),
                     ("purr", purr), ("meow", meow)):
        write(f"world/{name}.wav", fn())
    for v in range(2):
        write(f"world/drip{v + 1}.wav", drip(v))


if __name__ == "__main__":
    main()
    main_sound_update()
    main_hideout()
    main_bunker()
    main_life()
    main_pistol()
    main_more()
    main_lively()
