"""Makes muffled footsteps (0.36.24) from the footsteps already in audio/: one for a wall, shut door or pane in the
way, one for a floor or ceiling. Baked into WAVs because the web build plays sounds as samples and skips the runtime
low-pass that desktop used, so on web a step behind a wall was only 5 dB quieter and not muffled at all.

Most step energy sits at 100-400 Hz, so the old 900 Hz runtime cutoff barely touched it either: the muffle here cuts
lower (two passes, about -12 dB an octave) and smears the hit a little, but keeps the 150-400 Hz body so a step is
still heard on laptop and phone speakers (see the 0.34.5 low-bass gotcha: nothing below 100 Hz carries).

Run from the repo root:  python tools/make_step_variants.py
Check the levels:          python tools/make_step_variants.py --check
Only audio/steps/muffled/ is written; the base files are never touched.
"""
import math
import sys
import wave
import array
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_sound_variants import RATE, OUT, read, soft_clip, lowpass, highpass, match_rms, mix, rms  # noqa: E402

MUFFLED = OUT / "steps" / "muffled"
# Every step and rustle the game plays (Surfaces.STEPS, Surfaces.RUSTLES), by their path under audio/.
BASES = ["step1", "step2", "step3"] + [f"steps/{kind}{v}" for kind in ("wood", "metal", "concrete", "water")
                                        for v in (1, 2, 3)] + ["steps/rustle1", "steps/rustle2"]
VARIANTS = ("wall", "floor")
# Level against the base (RMS, dB). The runtime -5 dB (Hearing.MUFFLED_DB) still goes on top.
EXTRA_DB = {"wall": 0.0, "floor": -1.0}


def write(name, samples, peak=0.95):
    top = max(1e-9, max(abs(s) for s in samples))
    gain = peak / top if top > peak else 1.0
    data = array.array("h", (int(max(-1.0, min(1.0, s * gain)) * 32767) for s in samples))
    MUFFLED.mkdir(parents=True, exist_ok=True)
    with wave.open(str(MUFFLED / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def wall_of(base):
    """Through a wall: the click and scuff gone (two-pole 500 Hz), the thump kept, a short smear as the wall rings."""
    body = highpass(lowpass(lowpass(base, 500), 500), 90)
    return mix(body + [0.0] * int(0.06 * RATE), [s * 0.25 for s in lowpass(body, 300)], at=0.018)


def floor_of(base):
    """Through a floor or ceiling: darker still (two-pole 320 Hz), a thud, but nothing under 110 Hz."""
    body = highpass(lowpass(lowpass(base, 320), 320), 110)
    return mix(body + [0.0] * int(0.08 * RATE), [s * 0.3 for s in lowpass(body, 220)], at=0.025)


def out_name(base, kind):
    return f"{base.split('/')[-1]}_{kind}.wav"


def build(base_name):
    base, rate = read(base_name + ".wav")
    if rate != RATE:
        raise SystemExit(f"{base_name}: expected {RATE} Hz, got {rate}")
    if "rustle" in base_name:
        # A bush is all highs (most of it above 2.5 kHz): cut it like the steps and nothing is left, so it only dulls.
        made = {"wall": lowpass(lowpass(base, 1400), 1400), "floor": lowpass(lowpass(base, 900), 900)}
        extra = {"wall": -4.0, "floor": -6.0}
    else:
        made = {"wall": wall_of(base), "floor": floor_of(base)}
        extra = EXTRA_DB
    for kind in VARIANTS:
        write(out_name(base_name, kind), match_rms(soft_clip(made[kind]), base, extra[kind]))


def check():
    print(f"{'file':22} {'length':>7} {'rms dB vs base':>15} {'peak':>6}")
    for base_name in BASES:
        base, _ = read(base_name + ".wav")
        for kind in VARIANTS:
            name = out_name(base_name, kind)
            samples, _ = read(f"steps/muffled/{name}")
            ratio = 20.0 * math.log10(max(1e-9, rms(samples[: len(base)]) / max(1e-9, rms(base))))
            print(f"{name:22} {len(samples) / RATE:6.2f}s {ratio:+14.2f}  {max(abs(s) for s in samples):5.2f}")


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    else:
        for b in BASES:
            build(b)
        print(f"built {len(BASES) * len(VARIANTS)} muffled steps in {MUFFLED}")
