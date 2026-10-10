"""Placeholder scav callouts (0.12.12): short gibberish 'voice' barks made with simple formant synthesis, one per
callout kind, until real recorded lines replace them (drop audio/voice/<kind>.wav in with the same name).
Run: python3 tools/gen_voice_placeholders.py"""
import math, random, struct, wave, os

RATE = 22050
VOWELS = {"a": (730, 1090), "e": (530, 1840), "i": (390, 1990), "o": (570, 840), "u": (440, 1020)}
# kind: (syllables, pitch contour start->end multiplier, loudness)
KINDS = {
    "spotted": ("o-a", 1.25, 1.0),      # "Over there!" urgent, rising
    "lost": ("e-a-o", 0.95, 0.7),       # "Where'd he go?" questioning
    "cover": ("u-i", 1.1, 0.85),        # "Moving!"
    "flank": ("a-i-a", 1.05, 0.8),      # "Flanking!"
    "hurt": ("a", 1.4, 1.0),            # a pained shout
    "man_down": ("a-o-a", 0.9, 0.95),   # "Man down!"
    "help": ("e-o-u", 1.2, 1.0),        # "Over here!"
    "push": ("u-a-i", 1.15, 0.9),       # "Push him!"
    "heal": ("o-u", 0.85, 0.6),         # "Patching up"
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


def syllable(vowel, f0_start, f0_end, dur, rng):
    n = int(dur * RATE)
    phase, src = 0.0, []
    for k in range(n):
        t = k / n
        f0 = f0_start + (f0_end - f0_start) * t
        phase += f0 / RATE
        if phase >= 1.0:
            phase -= 1.0
        src.append((1.0 - 2.0 * phase) + rng.uniform(-0.15, 0.15))   # sawtooth glottal source + breath
    f1, f2 = VOWELS[vowel]
    a = resonate(src, f1, 90)
    b = resonate(src, f2, 120)
    env = []
    for k in range(n):
        t = k / n
        env.append(min(t / 0.15, 1.0) * min((1.0 - t) / 0.3, 1.0))
    return [(a[k] * 1.0 + b[k] * 0.5) * env[k] for k in range(n)]


def make(kind, spec, rng):
    sylls, rise, loud = spec
    parts = sylls.split("-")
    base = 135.0
    out = []
    for i, v in enumerate(parts):
        t0 = i / len(parts)
        t1 = (i + 1) / len(parts)
        f_start = base * (1 + (rise - 1) * t0)
        f_end = base * (1 + (rise - 1) * t1)
        out += syllable(v, f_start, f_end, rng.uniform(0.11, 0.16), rng)
        out += [0.0] * int(0.025 * RATE)
    peak = max(abs(s) for s in out) or 1.0
    out = [s / peak * 0.8 * loud for s in out]
    path = os.path.join(os.path.dirname(__file__), "..", "audio", "voice", kind + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in out))


if __name__ == "__main__":
    rng = random.Random(12)
    for kind, spec in KINDS.items():
        make(kind, spec, rng)
    print("wrote", len(KINDS), "placeholder barks to audio/voice/")
