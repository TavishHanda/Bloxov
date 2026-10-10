"""AI callouts: cartoony gibberish barks (0.12.27, owner: no real voice lines, "cartoony gibberish" that fits the
game's other sounds). Each callout kind has its own shape so players learn what it means (spotted = sharp and rising,
hurt = a pained yelp, heal = a low mumble...), and 3 takes per kind (<kind>.wav, <kind>_2.wav, <kind>_3.wav) so the
same line doesn't repeat. Raiders and Bon play them lower (voice_pitch in their scenes).
Run: python3 tools/gen_voice_placeholders.py"""
import math, random, struct, wave, os

RATE = 22050
TAKES = 3
VOWELS = {"a": (800, 1250), "e": (550, 1900), "i": (380, 2200), "o": (550, 900), "u": (400, 950)}
ONSETS = ["b", "d", "g", "m", "n", "h", "w", ""]
# kind: (syllables (min, max), pitch start, pitch end (x base), syllable length (s), gap (s), loudness, vowels to use)
KINDS = {
    "spotted": ((2, 2), 1.05, 1.6, 0.09, 0.03, 1.0, "aoe"),     # "Hey-yah!": sharp, rising
    "lost": ((3, 3), 1.1, 1.25, 0.11, 0.05, 0.7, "eou"),        # "Wha-da-wo?": puzzled, rising at the end
    "cover": ((2, 2), 1.2, 0.95, 0.08, 0.03, 0.85, "uia"),      # "Bu-dip!": quick
    "flank": ((3, 3), 1.0, 1.2, 0.08, 0.025, 0.8, "aie"),       # "Ga-di-ga": sneaky, quick
    "hurt": ((1, 1), 1.7, 1.1, 0.22, 0.0, 1.0, "aeo"),          # "Yaow!": a pained yelp
    "man_down": ((3, 3), 1.2, 0.8, 0.12, 0.04, 0.95, "aou"),    # "Ma-no-wah": falling, dismayed
    "help": ((3, 4), 1.15, 1.45, 0.12, 0.04, 1.0, "eoa"),       # "He-yo-wa-ah!": long, loud call
    "push": ((2, 3), 1.25, 1.35, 0.08, 0.02, 0.95, "uai"),      # "Bu-ga-di!": excited, fast
    "heal": ((2, 3), 0.9, 0.8, 0.12, 0.05, 0.55, "ou"),         # "Mm-mo-mu": a low mumble
}


def resonate(samples, freq, bw):
    r = math.exp(-math.pi * bw / RATE)
    c = 2 * r * math.cos(2 * math.pi * freq / RATE)
    y1 = y2 = 0.0
    out = []
    for x in samples:
        y = x + c * y1 - r * r * y2
        out.append(y)
        y2, y1 = y1, y
    return out


def onset(kind, rng):
    """A short consonant in front of a vowel: a plosive pop, a nasal hum or a breath."""
    if not kind:
        return []
    if kind in "bdg":
        n = int(0.012 * RATE)
        tone = {"b": 300, "d": 1800, "g": 1100}[kind]
        return resonate([rng.uniform(-1, 1) * (1 - k / n) for k in range(n)], tone, 400)
    if kind in "mn":
        n = int(0.04 * RATE)
        return [math.sin(2 * math.pi * 200 * k / RATE) * 0.35 * min(k / 80, 1) for k in range(n)]
    if kind in "hw":
        n = int(0.03 * RATE)
        return [rng.uniform(-0.25, 0.25) * k / n for k in range(n)]
    return []


def syllable(vowel, f0_start, f0_end, dur, rng):
    n = int(dur * RATE)
    phase, src = 0.0, []
    wobble = rng.uniform(5, 8)
    for k in range(n):
        t = k / n
        f0 = (f0_start + (f0_end - f0_start) * t) * (1 + 0.04 * math.sin(2 * math.pi * wobble * k / RATE))
        phase += f0 / RATE
        if phase >= 1.0:
            phase -= 1.0
        src.append((1.0 - 2.0 * phase) + rng.uniform(-0.08, 0.08))   # sawtooth "throat" + a little breath
    f1, f2 = VOWELS[vowel]
    a = resonate(src, f1, 110)
    b = resonate(src, f2, 150)
    out = []
    for k in range(n):
        t = k / n
        env = min(t / 0.08, 1.0) * min((1.0 - t) / 0.25, 1.0)   # snappy attack, short tail: bouncy, cartoony
        out.append((a[k] + b[k] * 0.6) * env)
    return out


def crunch(samples):
    """A little lo-fi crunch (half the sample rate, 6-bit steps) so the barks sit with the game's other sounds."""
    out, held = [], 0.0
    for k, s in enumerate(samples):
        if k % 2 == 0:
            held = round(s * 32) / 32
        out.append(held)
    return out


def make(kind, spec, take, rng):
    (lo, hi), p0, p1, syl, gap, loud, vowels = spec
    count = rng.randint(lo, hi)
    base = 185.0 * rng.uniform(0.95, 1.05)
    out = []
    for i in range(count):
        t0, t1 = i / count, (i + 1) / count
        jump = rng.uniform(0.92, 1.1)   # each syllable bounces a little up or down
        f_start = base * (p0 + (p1 - p0) * t0) * jump
        f_end = base * (p0 + (p1 - p0) * t1) * jump
        out += onset(rng.choice(ONSETS), rng)
        out += syllable(rng.choice(vowels), f_start, f_end, syl * rng.uniform(0.85, 1.2), rng)
        out += [0.0] * int(gap * RATE)
    peak = max(abs(s) for s in out) or 1.0
    out = crunch([s / peak * 0.8 * loud for s in out])
    name = kind + (".wav" if take == 1 else f"_{take}.wav")
    path = os.path.join(os.path.dirname(__file__), "..", "audio", "voice", name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in out))


if __name__ == "__main__":
    rng = random.Random(27)
    for kind, spec in KINDS.items():
        for take in range(1, TAKES + 1):
            make(kind, spec, take, rng)
    print("wrote", len(KINDS) * TAKES, "gibberish barks to audio/voice/")
