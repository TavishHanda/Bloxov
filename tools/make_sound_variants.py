"""Makes Sound 2.0's shot variants from the shots already in audio/ (no outside recordings, no new synth).

The near sound stays the file the game already plays; this only adds mid, far, room, room_far, floor and behind
versions of it, so a shot at 30 m, a shot at 80 m, a shot indoors, one through a floor and one from behind you sound
different, and the difference is baked into the WAV (the web build skips bus effects, so reverb and muffle cannot be
done at runtime there).

Run from the repo root:  python tools/make_sound_variants.py
Check the levels:          python tools/make_sound_variants.py --check

Rules (see docs/SOUND_2_PLAN.md §3.2):
- Same format as the rest: 22 050 Hz, mono, 16-bit.
- Never peak-normalise a variant: match the base file's RMS instead, or distance attenuation would quieten it twice.
- Soft-clip before writing so an added tail cannot wrap around.
- Only audio/guns/ is written; the base files in audio/ are never touched.
"""
import array
import math
import sys
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "audio"
GUNS = OUT / "guns"

# The base sound each gun uses (ak -> the original shot.wav; the pistol got its own in 0.30.0).
BASES = {
    "default": "shot.wav",
    "pistol": "shot_pistol.wav",
    "wasp": "shot_wasp.wav",
    "mauler": "shot_mauler.wav",
    "lancer": "shot_lancer.wav",
}
# 0.30.0: distance and room; 0.30.1: floor (the blocker is a floor/ceiling) and behind (the shooter is behind you).
VARIANTS = ("mid", "far", "room", "room_far", "floor", "behind")
# The level each variant is made at, in dB against its base. Everything else is level-matched; these two carry their
# own quieter level because the effect is meant to be a step back (plan §3.2).
EXTRA_DB = {"floor": -2.0, "behind": -1.5}
MAX_SECONDS = 1.2


def read(name):
    with wave.open(str(OUT / name), "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise SystemExit(f"{name}: expected mono 16-bit, got {w.getnchannels()}ch {w.getsampwidth() * 8}bit")
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    samples = array.array("h")
    samples.frombytes(raw)
    return [s / 32768.0 for s in samples], rate


def write(name, samples, peak=0.95):
    top = max(1e-9, max(abs(s) for s in samples))
    gain = peak / top if top > peak else 1.0
    data = array.array("h", (int(max(-1.0, min(1.0, s * gain)) * 32767) for s in samples))
    GUNS.mkdir(parents=True, exist_ok=True)
    with wave.open(str(GUNS / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def soft_clip(samples):
    return [math.tanh(s) for s in samples]


def lowpass(xs, cutoff, rate=RATE):
    """One-pole low-pass: -6 dB an octave, enough to take the crack off a shot without a filter library."""
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / rate)
    out, y = [], 0.0
    for x in xs:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(xs, cutoff, rate=RATE):
    low = lowpass(xs, cutoff, rate)
    return [x - l for x, l in zip(xs, low)]


def shelf_cut(xs, cutoff, amount, rate=RATE):
    """Take `amount` (0..1) of the top off above `cutoff`: a duller copy without changing the level much."""
    high = highpass(xs, cutoff, rate)
    return [x - amount * h for x, h in zip(xs, high)]


def rms(xs):
    return math.sqrt(sum(s * s for s in xs) / max(1, len(xs)))


def match_rms(variant, base, extra_db=0.0):
    """Scale `variant` so its first len(base) samples have the same RMS as `base` (the sound's own loudness), then
    apply `extra_db`. Never peak-normalise: the 3D distance attenuation must stay the only thing deciding loudness."""
    head = variant[: len(base)]
    want = rms(base) * (10.0 ** (extra_db / 20.0))
    have = rms(head)
    return [s * (want / have) for s in variant] if have > 1e-9 else variant


def mix(a, b, at=0.0, gain=1.0):
    """`a` plus `b` starting `at` seconds in, `gain` times as loud."""
    shift = int(at * RATE)
    out = list(a)
    if len(out) < shift + len(b):
        out += [0.0] * (shift + len(b) - len(out))
    for i, s in enumerate(b):
        out[shift + i] += s * gain
    return out


def pad(xs, seconds):
    return list(xs) + [0.0] * int(seconds * RATE)


def allpass(xs, delay, g=0.5):
    n = max(1, int(delay * RATE))
    buf, idx, out = [0.0] * n, 0, []
    for x in xs:
        y = buf[idx]
        buf[idx] = x + g * y
        idx = (idx + 1) % n
        out.append(y - g * x)
    return out


def reverb(xs, rt60=0.5, wet=0.18):
    """A small room: three damped comb filters into two all-passes (Schroeder). Mono, like everything else."""
    combs = (0.0297, 0.0371, 0.0411)
    acc = [0.0] * len(xs)
    for delay in combs:
        n = max(1, int(delay * RATE))
        feedback = 10.0 ** (-3.0 * delay / rt60)
        buf, idx, damped = [0.0] * n, 0, 0.0
        for i, x in enumerate(xs):
            y = buf[idx]
            damped = 0.7 * y + 0.3 * damped
            buf[idx] = x + damped * feedback
            idx = (idx + 1) % n
            acc[i] += y
    acc = [v / len(combs) for v in acc]
    for delay in (0.0050, 0.0017):
        acc = allpass(acc, delay)
    return [x + wet * r for x, r in zip(xs, acc)]


def room_of(base, wet):
    tail = 0.35
    body = reverb(pad(base, tail), rt60=0.5, wet=wet)
    early = [s * 0.5 for s in lowpass(base, 2500)]
    return mix(body, early, at=0.012)


def mid_of(base):
    body = lowpass(base, 3000)
    return mix(body, [s * 0.12 for s in lowpass(base, 1200)], at=0.04)


def far_of(base):
    body = lowpass(base, 900)
    boom = [math.sin(2.0 * math.pi * 55.0 * i / RATE) * math.exp(-i / RATE * 9.0) * 0.35
            for i in range(int(0.30 * RATE))]
    body = mix(body, boom, at=0.02)
    return mix(body, [s * 0.15 for s in lowpass(base, 500)], at=0.12)


def floor_of(base):
    """A shot heard through a floor or ceiling (0.30.1): no crack left, just a low thud under your feet."""
    body = lowpass(base, 400)
    thump = [math.sin(2.0 * math.pi * 52.0 * i / RATE) * math.exp(-i / RATE * 7.0) * 0.55
             for i in range(int(0.28 * RATE))]
    body = mix(body, thump, at=0.01)
    return mix(body, [s * 0.12 for s in lowpass(base, 220)], at=0.06)


def behind_of(base):
    """A shot from behind you (0.30.1): the same shot with about 4 dB taken off above 4 kHz (the head blocks the top)."""
    return shelf_cut(base, 4000.0, 0.37)


def build(name):
    base, rate = read(BASES[name])
    if rate != RATE:
        raise SystemExit(f"{BASES[name]}: expected {RATE} Hz, got {rate}")
    made = {
        "mid": mid_of(base),
        "far": far_of(base),
        "room": room_of(base, 0.18),
        "room_far": room_of(far_of(base), 0.22),
        "floor": floor_of(base),
        "behind": behind_of(base),
    }
    for kind in VARIANTS:
        # Soft-clip first, then match: tanh takes about a decibel off the RMS, and matching before it would leave
        # every variant quieter than its base.
        samples = match_rms(soft_clip(made[kind]), base, EXTRA_DB.get(kind, 0.0))[: int(MAX_SECONDS * RATE)]
        write(f"{name}_{kind}.wav", samples)


def check():
    print(f"{'file':22} {'length':>7} {'rms dB vs base':>15} {'peak':>6}")
    for name in BASES:
        base, _ = read(BASES[name])
        for kind in VARIANTS:
            path = GUNS / f"{name}_{kind}.wav"
            if not path.exists():
                print(f"{path.name:22} missing")
                continue
            samples, _ = read(f"guns/{path.name}")
            ratio = 20.0 * math.log10(max(1e-9, rms(samples[: len(base)]) / max(1e-9, rms(base))))
            print(f"{path.name:22} {len(samples) / RATE:6.2f}s {ratio:+14.2f}  {max(abs(s) for s in samples):5.2f}")


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    else:
        for base_name in BASES:
            build(base_name)
            print(f"built {base_name}: {', '.join(VARIANTS)}")
        print(f"written to {GUNS}")
