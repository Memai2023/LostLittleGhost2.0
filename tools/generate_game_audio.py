#!/usr/bin/env python3
"""Generates the original sound effects and music used by the game.

Pure standard library (wave/struct/math/random) -- no numpy, no external
tools, no Homebrew dependency. Every sound below is synthesized (sine
sweeps, additive "bell" tones, and gently low-pass-filtered noise for
airy/breathy texture) rather than sampled or copied from anywhere, and every
file gets short start/end fades so nothing clicks or pops.

Run from the project root:
    python3 tools/generate_game_audio.py

Writes into assets/audio/ and assets/audio/sfx/. Re-running regenerates all
files from scratch (deterministic -- every noise layer uses a fixed seed),
so it's safe to tweak the design constants below and re-run.
"""

import math
import os
import random
import struct
import wave

SR = 44100  # 44,100 Hz, matches the project's existing background music.

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
SFX_DIR = os.path.join(OUT_DIR, "sfx")


# ---------------------------------------------------------------------------
# Synthesis primitives
# ---------------------------------------------------------------------------

def n_samples(duration: float) -> int:
    return max(1, int(round(SR * duration)))


def sine_sweep(freq_start: float, freq_end: float, duration: float, amp: float = 1.0) -> list:
    """A single sine tone whose frequency glides linearly from freq_start to
    freq_end over `duration` seconds. Phase is integrated sample-by-sample
    (not just evaluated from instantaneous frequency) so the sweep itself
    never clicks or has phase discontinuities."""
    n = n_samples(duration)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = freq_start + (freq_end - freq_start) * (t / duration if duration > 0 else 0.0)
        phase += 2.0 * math.pi * f / SR
        out[i] = amp * math.sin(phase)
    return out


def vibrato_tone(base_freq: float, duration: float, depth_hz: float,
                  rate_start: float, rate_end: float, amp: float = 1.0) -> list:
    """A tone with frequency vibrato whose *rate* itself glides from
    rate_start to rate_end -- used for the portal's slowly-quickening
    "swirl"."""
    n = n_samples(duration)
    out = [0.0] * n
    phase = 0.0
    vib_phase = 0.0
    for i in range(n):
        t = i / SR
        rate = rate_start + (rate_end - rate_start) * (t / duration if duration > 0 else 0.0)
        vib_phase += 2.0 * math.pi * rate / SR
        f = base_freq + depth_hz * math.sin(vib_phase)
        phase += 2.0 * math.pi * f / SR
        out[i] = amp * math.sin(phase)
    return out


def harmonic_bell(freq: float, duration: float, amp: float = 1.0, decay: float = 6.0,
                   harmonics=((1.0, 1.0), (2.0, 0.35), (3.0, 0.15))) -> list:
    """Warm additive "bell"/music-box tone: a few harmonically-related sine
    partials, each with its own independent exponential decay (higher
    partials fade a little faster, like a real struck bell)."""
    n = n_samples(duration)
    out = [0.0] * n
    for h_index, (h_mult, h_amp) in enumerate(harmonics):
        f = freq * h_mult
        this_decay = decay * (1.0 + 0.15 * h_index)
        phase = 0.0
        for i in range(n):
            t = i / SR
            env = math.exp(-this_decay * t)
            phase += 2.0 * math.pi * f / SR
            out[i] += amp * h_amp * env * math.sin(phase)
    return out


def soft_noise(duration: float, amp: float = 1.0, cutoff: float = 0.06, seed: int = 0) -> list:
    """White noise through a simple one-pole low-pass filter, for a soft
    airy/breathy texture (never harsh full-band hiss)."""
    rnd = random.Random(seed)
    n = n_samples(duration)
    out = [0.0] * n
    y = 0.0
    for i in range(n):
        x = rnd.uniform(-1.0, 1.0)
        y = cutoff * x + (1.0 - cutoff) * y
        out[i] = amp * y
    return out


def env_linear(samples: list, attack: float, release: float, sustain: float = 1.0) -> list:
    """Applies a simple linear attack/sustain/release envelope in place
    (returns a new list)."""
    n = len(samples)
    a_n = n_samples(attack)
    r_n = n_samples(release)
    out = list(samples)
    for i in range(min(a_n, n)):
        out[i] *= sustain * (i / a_n if a_n > 0 else 1.0)
    for i in range(min(r_n, n)):
        idx = n - 1 - i
        mult = (i / r_n) if r_n > 0 else 0.0
        out[idx] *= min(1.0, mult) if idx >= a_n else out[idx]
    return out


def mix(layers, offsets=None) -> list:
    """Sums layers (lists of floats), each optionally starting at its own
    sample offset (for staggered/layered entrances)."""
    if offsets is None:
        offsets = [0] * len(layers)
    n = max((off + len(layer) for off, layer in zip(offsets, layers)), default=0)
    out = [0.0] * n
    for off, layer in zip(offsets, layers):
        for i, s in enumerate(layer):
            out[off + i] += s
    return out


def fade_io(samples: list, fade_in: float = 0.006, fade_out: float = 0.012) -> list:
    """Short linear fades at the very start/end of a buffer -- this is what
    actually prevents clicks at file boundaries, independent of whatever
    envelope the sound's own layers already have."""
    n = len(samples)
    out = list(samples)
    fi = n_samples(fade_in)
    fo = n_samples(fade_out)
    for i in range(min(fi, n)):
        out[i] *= i / fi
    for i in range(min(fo, n)):
        idx = n - 1 - i
        out[idx] *= i / fo
    return out


def normalize(samples: list, peak: float = 0.78) -> list:
    m = max((abs(s) for s in samples), default=0.0)
    if m <= 0.0001:
        return samples
    scale = peak / m
    return [s * scale for s in samples]


def soft_clip(samples: list, threshold: float = 0.92) -> list:
    """Gentle saturation for any sample that still pokes above `threshold`
    after normalization (guards against clipping when several loud layers
    happen to line up in phase) without hard-clipping/crackling."""
    out = []
    for s in samples:
        a = abs(s)
        if a <= threshold:
            out.append(s)
        else:
            sign = 1.0 if s > 0 else -1.0
            over = a - threshold
            out.append(sign * (threshold + math.tanh(over * 4.0) * (1.0 - threshold)))
    return out


def finalize_mono(samples: list, peak: float = 0.78) -> list:
    samples = normalize(samples, peak)
    samples = soft_clip(samples)
    samples = fade_io(samples)
    return samples


def write_wav_mono(path: str, samples: list) -> None:
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32767)
            frames += struct.pack("<h", v)
        f.writeframes(bytes(frames))


def write_wav_stereo(path: str, left: list, right: list) -> None:
    n = min(len(left), len(right))
    with wave.open(path, "w") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        frames = bytearray()
        for i in range(n):
            vl = int(max(-1.0, min(1.0, left[i])) * 32767)
            vr = int(max(-1.0, min(1.0, right[i])) * 32767)
            frames += struct.pack("<hh", vl, vr)
        f.writeframes(bytes(frames))


def widen_stereo(mono: list, delay_ms: float = 9.0, detune_cents: float = 4.0) -> tuple:
    """Cheap, dependency-free stereo widening for the victory theme: the
    right channel is a tiny delayed/slightly-retimed copy of the left, which
    reads as a gentle chorus-like width rather than true mono. Not a full
    DSP pitch-shift -- just enough softening that the loop doesn't feel
    pinned dead-center."""
    delay_n = int(SR * delay_ms / 1000.0)
    n = len(mono)
    left = list(mono)
    right = [0.0] * n
    stretch = 1.0 + detune_cents / 1200.0 * math.log(2.0)
    for i in range(n):
        src = (i - delay_n) / stretch
        i0 = int(src)
        frac = src - i0
        if 0 <= i0 < n - 1:
            right[i] = mono[i0] * (1 - frac) + mono[i0 + 1] * frac
        elif 0 <= i0 < n:
            right[i] = mono[i0]
    return left, right


# ---------------------------------------------------------------------------
# 1. jump.wav -- short, soft, airy upward whoosh.
# ---------------------------------------------------------------------------

def gen_jump() -> list:
    duration = 0.18
    tone = sine_sweep(340.0, 640.0, duration, amp=0.85)
    tone = env_linear(tone, attack=0.008, release=0.12, sustain=1.0)
    whoosh = soft_noise(duration, amp=0.22, cutoff=0.10, seed=1)
    whoosh = env_linear(whoosh, attack=0.01, release=duration, sustain=1.0)
    return finalize_mono(mix([tone, whoosh]))


# ---------------------------------------------------------------------------
# 2. double_jump.wav -- brighter, two layered magical sparkle tones (kept
# as the original; three alternatives are generated further below).
# ---------------------------------------------------------------------------

def gen_double_jump() -> list:
    layer_a = sine_sweep(460.0, 920.0, 0.26, amp=0.75)
    layer_a = env_linear(layer_a, attack=0.006, release=0.20)

    layer_b = sine_sweep(700.0, 1350.0, 0.22, amp=0.55)
    layer_b = env_linear(layer_b, attack=0.005, release=0.16)

    sparkle_1 = harmonic_bell(1700.0, 0.12, amp=0.35, decay=20.0,
                               harmonics=((1.0, 1.0), (1.5, 0.4)))
    sparkle_2 = harmonic_bell(2100.0, 0.12, amp=0.30, decay=20.0,
                               harmonics=((1.0, 1.0), (1.5, 0.4)))

    off_b = n_samples(0.05)
    off_s1 = n_samples(0.09)
    off_s2 = n_samples(0.18)
    mixed = mix([layer_a, layer_b, sparkle_1, sparkle_2],
                offsets=[0, off_b, off_s1, off_s2])
    return finalize_mono(mixed)


# ---------------------------------------------------------------------------
# 2b. double_jump_air.wav -- soft upward air burst, minimal tonal content.
# ---------------------------------------------------------------------------

def gen_double_jump_air() -> list:
    duration = 0.28
    whoosh = soft_noise(duration, amp=0.5, cutoff=0.14, seed=10)
    whoosh = env_linear(whoosh, attack=0.02, release=duration * 0.85)
    # A single very soft rising undertone -- present but subordinate to the
    # air/whoosh texture, so this never reads as a tonal two-note melody.
    tone = sine_sweep(280.0, 460.0, duration, amp=0.22)
    tone = env_linear(tone, attack=0.02, release=duration * 0.8)
    return finalize_mono(mix([whoosh, tone]), peak=0.7)


# ---------------------------------------------------------------------------
# 2c. double_jump_spectral.wav -- deeper spectral opening, rapid sweep.
# ---------------------------------------------------------------------------

def gen_double_jump_spectral() -> list:
    duration = 0.38
    deep = sine_sweep(140.0, 320.0, duration * 0.6, amp=0.5)
    deep = env_linear(deep, attack=0.01, release=duration * 0.5)

    sweep = sine_sweep(500.0, 1400.0, duration * 0.55, amp=0.45)
    sweep = env_linear(sweep, attack=0.005, release=duration * 0.4)
    sweep_off = n_samples(duration * 0.15)

    shimmer = harmonic_bell(1900.0, 0.16, amp=0.28, decay=18.0,
                             harmonics=((1.0, 1.0), (1.5, 0.35)))
    shimmer_off = n_samples(duration - 0.16)

    mixed = mix([deep, sweep, shimmer], offsets=[0, sweep_off, shimmer_off])
    return finalize_mono(mixed, peak=0.72)


# ---------------------------------------------------------------------------
# 2e. double_jump_ghost_burst.wav -- rounded magical pulse -> fast spectral
# whoosh -> one subtle sparkle. Purely tonal (no noise layer, unlike
# double_jump_air.wav) so it reads as substantial rather than thin/airy.
# ---------------------------------------------------------------------------

def gen_double_jump_ghost_burst() -> list:
    duration = 0.38

    # Soft, rounded magical pulse -- the "boost" beginning; a bell's smooth
    # exponential decay reads as rounded rather than a hard percussive hit.
    pulse = harmonic_bell(340.0, 0.14, amp=0.55, decay=13.0,
                           harmonics=((1.0, 1.0), (2.0, 0.3)))

    # Brief low body under the pulse for weight -- short enough to read as
    # "substantial" without becoming a sustained low rumble.
    body = sine_sweep(190.0, 150.0, 0.11, amp=0.35)
    body = env_linear(body, attack=0.008, release=0.09)

    # Fast upward spectral whoosh -- the actual "second push" sensation.
    whoosh = sine_sweep(420.0, 1500.0, 0.20, amp=0.62)
    whoosh = env_linear(whoosh, attack=0.006, release=0.16)
    whoosh_off = n_samples(0.05)

    # One subtle bright sparkle at the very end, kept well below harsh
    # territory (no partials above ~3.4kHz, quiet, fast decay).
    sparkle = harmonic_bell(2100.0, 0.13, amp=0.24, decay=18.0,
                             harmonics=((1.0, 1.0), (1.6, 0.25)))
    sparkle_off = n_samples(duration - 0.13)

    mixed = mix([pulse, body, whoosh, sparkle],
                offsets=[0, 0, whoosh_off, sparkle_off])
    return finalize_mono(mixed, peak=0.8)


# ---------------------------------------------------------------------------
# 2d. double_jump_magic.wav -- short magical pulse, one subtle sparkle.
# ---------------------------------------------------------------------------

def gen_double_jump_magic() -> list:
    duration = 0.3
    bloom = sine_sweep(500.0, 760.0, duration * 0.8, amp=0.6)
    bloom = env_linear(bloom, attack=0.015, release=duration * 0.65)

    sparkle = harmonic_bell(1800.0, 0.14, amp=0.3, decay=22.0,
                             harmonics=((1.0, 1.0), (2.0, 0.2)))
    sparkle_off = n_samples(duration - 0.14)

    mixed = mix([bloom, sparkle], offsets=[0, sparkle_off])
    return finalize_mono(mixed, peak=0.72)


# ---------------------------------------------------------------------------
# 3. portal_enter.wav -- swirling, shimmering, soft inward pull.
# ---------------------------------------------------------------------------

def gen_portal_enter() -> list:
    duration = 0.95
    swirl = vibrato_tone(320.0, duration, depth_hz=22.0,
                          rate_start=1.5, rate_end=7.0, amp=0.55)
    swirl = env_linear(swirl, attack=0.05, release=0.05)

    # Gentle shimmer/chime, entering partway through.
    shimmer = harmonic_bell(1250.0, 0.5, amp=0.28, decay=5.0,
                             harmonics=((1.0, 1.0), (2.0, 0.3), (3.0, 0.12)))
    shimmer_off = n_samples(0.28)

    # Soft inward pull: a quick downward glide right at the very end, faded
    # under the swirl's own tail so it reads as being "pulled in" rather than
    # a separate sound.
    pull_dur = 0.22
    pull = sine_sweep(420.0, 90.0, pull_dur, amp=0.5)
    pull = env_linear(pull, attack=0.02, release=pull_dur * 0.9)
    pull_off = n_samples(duration - pull_dur)

    mixed = mix([swirl, shimmer, pull], offsets=[0, shimmer_off, pull_off])
    return finalize_mono(mixed, peak=0.72)


# ---------------------------------------------------------------------------
# 4. ghost_hurt.wav -- short soft spectral impact, descending tone.
# ---------------------------------------------------------------------------

def gen_ghost_hurt() -> list:
    duration = 0.34
    tone = sine_sweep(520.0, 250.0, duration, amp=0.8)
    tone = env_linear(tone, attack=0.004, release=0.26)

    impact = soft_noise(0.05, amp=0.3, cutoff=0.18, seed=2)
    impact = env_linear(impact, attack=0.002, release=0.045)

    mixed = mix([tone, impact])
    return finalize_mono(mixed, peak=0.7)


# ---------------------------------------------------------------------------
# 5. ghost_death.wav -- longer magical dissolve, descending + fading shimmer.
# ---------------------------------------------------------------------------

def gen_ghost_death() -> list:
    duration = 1.4
    partials = [
        (440.0, 190.0, 0.42, 0.0),
        (660.0, 280.0, 0.30, 0.03),
        (880.0, 360.0, 0.20, 0.06),
    ]
    layers = []
    offsets = []
    for f_start, f_end, amp, start_offset in partials:
        remaining = duration - start_offset
        layer = sine_sweep(f_start, f_end, remaining, amp=amp)
        layer = env_linear(layer, attack=0.03, release=remaining * 0.8)
        layers.append(layer)
        offsets.append(n_samples(start_offset))

    # Fading shimmer tail: slow tremolo on a high, quiet layer.
    shimmer_dur = duration - 0.15
    shimmer = sine_sweep(1300.0, 760.0, shimmer_dur, amp=0.16)
    trem_n = len(shimmer)
    for i in range(trem_n):
        t = i / SR
        shimmer[i] *= 0.6 + 0.4 * math.sin(2.0 * math.pi * 4.0 * t)
    shimmer = env_linear(shimmer, attack=0.05, release=shimmer_dur * 0.85)
    layers.append(shimmer)
    offsets.append(n_samples(0.1))

    mixed = mix(layers, offsets=offsets)
    return finalize_mono(mixed, peak=0.72)


# ---------------------------------------------------------------------------
# 6. superpower_activate.wav -- ascending layered shimmer + magical burst.
# ---------------------------------------------------------------------------

def gen_superpower_activate() -> list:
    rise_dur = 0.55
    layer1 = sine_sweep(300.0, 600.0, rise_dur, amp=0.5)
    layer1 = env_linear(layer1, attack=0.05, release=rise_dur * 0.5)
    layer2 = sine_sweep(400.0, 800.0, rise_dur, amp=0.42)
    layer2 = env_linear(layer2, attack=0.05, release=rise_dur * 0.5)
    layer3 = sine_sweep(500.0, 1000.0, rise_dur, amp=0.36)
    layer3 = env_linear(layer3, attack=0.05, release=rise_dur * 0.5)

    off2 = n_samples(0.15)
    off3 = n_samples(0.30)

    # Peak "magical burst": bright filtered-noise sparkle plus a tight
    # close-harmony bell chord, right where the ascending layers crest.
    burst_off_s = 0.72
    burst_noise = soft_noise(0.22, amp=0.30, cutoff=0.32, seed=3)
    burst_noise = env_linear(burst_noise, attack=0.006, release=0.2)

    burst_chord = mix([
        harmonic_bell(1400.0, 0.45, amp=0.26, decay=5.5, harmonics=((1.0, 1.0), (2.0, 0.25))),
        harmonic_bell(1750.0, 0.45, amp=0.22, decay=5.5, harmonics=((1.0, 1.0), (2.0, 0.25))),
        harmonic_bell(2100.0, 0.45, amp=0.18, decay=5.5, harmonics=((1.0, 1.0), (2.0, 0.25))),
    ])

    mixed = mix(
        [layer1, layer2, layer3, burst_noise, burst_chord],
        offsets=[0, off2, off3, n_samples(burst_off_s), n_samples(burst_off_s)],
    )
    return finalize_mono(mixed, peak=0.75)


# ---------------------------------------------------------------------------
# 6b. pure_orb_collect.wav -- bright, clean, comforting collection chime.
# Softer than superpower_activate.wav, distinct from portal_enter.wav and
# victory_chime.wav (a plain rising two/three-note chime, no sweep, no
# closing chord), suitable for frequent repeated collection.
# ---------------------------------------------------------------------------

def gen_pure_orb_collect() -> list:
    notes = [659.25, 987.77, 1318.51]  # E5-B5-E6, soft rising chime.
    layers = []
    offsets = []
    step = 0.11
    for i, f in enumerate(notes):
        bell = harmonic_bell(f, 0.55, amp=0.4, decay=5.5,
                              harmonics=((1.0, 1.0), (2.0, 0.3), (3.0, 0.1)))
        layers.append(bell)
        offsets.append(n_samples(i * step))

    # Warm resonance under the chime.
    warmth = harmonic_bell(329.63, 0.75, amp=0.18, decay=3.2,
                            harmonics=((1.0, 1.0), (2.0, 0.15)))
    layers.append(warmth)
    offsets.append(0)

    # Small shimmer at the very end.
    shimmer = harmonic_bell(2000.0, 0.25, amp=0.14, decay=9.0)
    layers.append(shimmer)
    offsets.append(n_samples(len(notes) * step))

    mixed = mix(layers, offsets=offsets)
    return finalize_mono(mixed, peak=0.72)


# ---------------------------------------------------------------------------
# 7. victory_chime.wav -- short hopeful ascending bell arpeggio.
# ---------------------------------------------------------------------------

def gen_victory_chime() -> list:
    # A simple original rising broken chord -- generic scale degrees, not a
    # copied melody. C5-E5-G5-C6 (major arpeggio) with a soft closing chord.
    notes = [523.25, 659.25, 783.99, 1046.50]
    layers = []
    offsets = []
    step = 0.26
    for i, f in enumerate(notes):
        bell = harmonic_bell(f, 0.9, amp=0.5, decay=3.4,
                              harmonics=((1.0, 1.0), (2.0, 0.4), (3.0, 0.18), (4.0, 0.08)))
        layers.append(bell)
        offsets.append(n_samples(i * step))

    # Warm closing chord shimmer under the last note.
    chord = mix([
        harmonic_bell(783.99, 1.1, amp=0.22, decay=2.6),
        harmonic_bell(1046.50, 1.1, amp=0.20, decay=2.6),
        harmonic_bell(1318.51, 1.1, amp=0.16, decay=2.6),
    ])
    layers.append(chord)
    offsets.append(n_samples(len(notes) * step))

    mixed = mix(layers, offsets=offsets)
    return finalize_mono(mixed, peak=0.75)


# ---------------------------------------------------------------------------
# 8. victory_theme.wav -- warm, hopeful, seamlessly-looping ending music.
# ---------------------------------------------------------------------------

def gen_victory_theme_phrase(phrase_duration: float) -> list:
    """One repeatable phrase: a soft sustained pad chord under a simple
    music-box-like pentatonic melody. Every voice's own envelope has fully
    decayed by the end of the phrase, so phrases can be concatenated back to
    back with no seam."""
    pad_notes = [261.63, 329.63, 392.00]  # C4-E4-G4, soft sustained pad.
    pad_layers = [
        harmonic_bell(f, phrase_duration, amp=0.14, decay=1.15,
                       harmonics=((1.0, 1.0), (2.0, 0.22)))
        for f in pad_notes
    ]

    # C major pentatonic melody notes, a simple original 6-note pattern.
    melody_notes = [523.25, 587.33, 659.25, 783.99, 659.25, 523.25]
    melody_times = [0.0, 0.5, 1.0, 1.6, 2.2, 2.75]
    melody_layers = []
    melody_offsets = []
    for f, t in zip(melody_notes, melody_times):
        remaining = max(0.05, phrase_duration - t)
        bell = harmonic_bell(f, min(0.9, remaining), amp=0.34, decay=3.0,
                              harmonics=((1.0, 1.0), (2.0, 0.3), (3.0, 0.1)))
        melody_layers.append(bell)
        melody_offsets.append(n_samples(t))

    all_layers = pad_layers + melody_layers
    all_offsets = [0] * len(pad_layers) + melody_offsets
    phrase = mix(all_layers, offsets=all_offsets)

    target_n = n_samples(phrase_duration)
    if len(phrase) < target_n:
        phrase += [0.0] * (target_n - len(phrase))
    else:
        phrase = phrase[:target_n]
    return phrase


def gen_victory_theme() -> tuple:
    phrase_duration = 3.25
    repeats = 4  # 4 * 3.25s = 13.0s, inside the requested 10-16s range.
    mono = []
    for _ in range(repeats):
        mono += gen_victory_theme_phrase(phrase_duration)

    mono = normalize(mono, peak=0.7)
    mono = soft_clip(mono)
    # Fades only at the very outer edges (short enough to stay inaudible as
    # a "fade", long enough to guarantee a click-free loop seam once Godot
    # wraps the whole file back to sample 0).
    mono = fade_io(mono, fade_in=0.01, fade_out=0.02)

    left, right = widen_stereo(mono)
    return left, right


# ---------------------------------------------------------------------------
# Shared helper for the new looping themes below: repeats a phrase function
# N times, normalizes/soft-clips/edge-fades the concatenated result exactly
# like gen_victory_theme() above, then stereo-widens it. Each phrase
# function is responsible for its own layers fully decaying (or being
# force-faded) by its own end, so back-to-back concatenation stays seamless.
# ---------------------------------------------------------------------------

def build_looping_theme(phrase_fn, phrase_duration: float, repeats: int, peak: float = 0.7) -> tuple:
    mono = []
    for _ in range(repeats):
        mono += phrase_fn(phrase_duration)

    mono = normalize(mono, peak=peak)
    mono = soft_clip(mono)
    mono = fade_io(mono, fade_in=0.01, fade_out=0.02)

    left, right = widen_stereo(mono)
    return left, right


def _pad_or_trim(phrase: list, phrase_duration: float) -> list:
    target_n = n_samples(phrase_duration)
    if len(phrase) < target_n:
        phrase = phrase + [0.0] * (target_n - len(phrase))
    else:
        phrase = phrase[:target_n]
    return phrase


# ---------------------------------------------------------------------------
# 9. superpower_theme.wav -- mysterious, weightless, spectral loop played
# while the ghost is transparent. Softer ethereal pad, a slow "breathing"
# magical pulse (not percussion), subtle drifting vibrato, and sparse high
# shimmer -- atmospheric rather than aggressive, no drums, no copied melody.
# ---------------------------------------------------------------------------

def gen_superpower_theme_phrase(phrase_duration: float) -> list:
    pad_notes = [220.00, 261.63, 329.63]  # A3-C4-E4, hollow minor pad.
    pad_layers = [
        harmonic_bell(f, phrase_duration, amp=0.13, decay=1.0,
                      harmonics=((1.0, 1.0), (2.0, 0.18), (3.0, 0.08)))
        for f in pad_notes
    ]

    # Slow magical "breathing" pulse -- a sustained low tone with a slow
    # sinusoidal amplitude swell, standing in for a pulse without any
    # percussive attack. Forced to a hard zero by phrase end via env_linear's
    # release, so it never contributes to a loop-seam discontinuity.
    pulse = sine_sweep(110.0, 110.0, phrase_duration, amp=0.22)
    for i in range(len(pulse)):
        t = i / SR
        pulse[i] *= 0.5 + 0.5 * math.sin(2.0 * math.pi * 0.25 * t)
    pulse = env_linear(pulse, attack=0.4, release=phrase_duration * 0.6)

    # Subtle spectral movement -- a slow, quiet vibrato tone drifting through
    # the middle register.
    drift = vibrato_tone(493.88, phrase_duration, depth_hz=14.0,
                          rate_start=0.15, rate_end=0.35, amp=0.09)
    drift = env_linear(drift, attack=0.6, release=phrase_duration * 0.5)

    # Sparse high shimmer chimes.
    shimmer_notes = [1046.50, 1318.51, 1567.98]
    shimmer_times = [phrase_duration * 0.2, phrase_duration * 0.45, phrase_duration * 0.68]
    shimmer_layers = []
    shimmer_offsets = []
    for f, t in zip(shimmer_notes, shimmer_times):
        remaining = max(0.1, phrase_duration - t)
        bell = harmonic_bell(f, min(1.1, remaining), amp=0.16, decay=2.6,
                              harmonics=((1.0, 1.0), (2.0, 0.3)))
        shimmer_layers.append(bell)
        shimmer_offsets.append(n_samples(t))

    all_layers = pad_layers + [pulse, drift] + shimmer_layers
    all_offsets = [0] * (len(pad_layers) + 2) + shimmer_offsets
    phrase = mix(all_layers, offsets=all_offsets)
    return _pad_or_trim(phrase, phrase_duration)


def gen_superpower_theme() -> tuple:
    phrase_duration = 4.0
    repeats = 4  # 16.0s, inside the requested 12-18s range.
    return build_looping_theme(gen_superpower_theme_phrase, phrase_duration, repeats, peak=0.65)


# ---------------------------------------------------------------------------
# 8b. stealth_ambience.wav -- a quiet, continuous "ghost is invisible" bed,
# meant to sit underneath superpower_theme.wav (not compete with it as a
# second melody). No notes, no rhythm: soft filtered air/breath, a slow
# amplitude swell, one faint drifting tone, and two very sparse high
# touches. Seamlessness comes from the same technique already proven for
# superpower_theme.wav/victory_theme.wav: content that's essentially
# stationary/decayed by the buffer's edges, finished with a short linear
# fade at sample 0 and the last sample so the wrap is silence-to-silence.
# ---------------------------------------------------------------------------

def gen_stealth_ambience_buffer(duration: float) -> list:
    # Soft filtered wind/breath -- the base layer. cutoff kept mid-range
    # (not too low) so this stays airy rather than a low-frequency rumble,
    # and mid (not too high) so it stays soft rather than a harsh hiss.
    breath = soft_noise(duration, amp=0.10, cutoff=0.13, seed=42)

    # Slow phase movement: a gentle amplitude swell, an integer number of
    # cycles across the buffer so its own value/slope line up at the loop
    # point (an extra layer of seam-safety on top of the edge fade below).
    swell_cycles = 2.0
    for i in range(len(breath)):
        t = i / SR
        breath[i] *= 0.65 + 0.35 * math.sin(2.0 * math.pi * (swell_cycles / duration) * t)

    # A second, brighter/quieter filtered layer for subtle width -- not a
    # second audible voice, just wispier air alongside the breath layer.
    air = soft_noise(duration, amp=0.05, cutoff=0.22, seed=97)

    # One faint, slow drifting tone -- a gentle spectral pulse, not a
    # rhythm: it never repeats on a regular beat.
    drift = vibrato_tone(760.0, duration, depth_hz=6.0,
                          rate_start=0.1, rate_end=0.16, amp=0.045)

    # Two very sparse, very quiet high touches -- faint shimmer, not a
    # chime: both are fully decayed well before the loop boundary.
    shimmer_a = harmonic_bell(2400.0, 1.6, amp=0.05, decay=3.2,
                               harmonics=((1.0, 1.0), (2.0, 0.2)))
    shimmer_b = harmonic_bell(3100.0, 1.4, amp=0.035, decay=3.6,
                               harmonics=((1.0, 1.0),))

    mixed = mix(
        [breath, air, drift, shimmer_a, shimmer_b],
        offsets=[0, 0, 0, n_samples(1.8), n_samples(duration - 1.9)],
    )
    return mixed


def gen_stealth_ambience() -> tuple:
    duration = 6.0
    mixed = gen_stealth_ambience_buffer(duration)
    mixed = normalize(mixed, peak=0.22)
    mixed = soft_clip(mixed)
    # Longer edge fades than a note-based SFX/phrase -- this is a
    # continuous, stationary texture, so a slightly longer taper keeps the
    # loop seam inaudible against its own quiet character.
    mixed = fade_io(mixed, fade_in=0.05, fade_out=0.08)

    left, right = widen_stereo(mixed, delay_ms=6.0, detune_cents=3.0)
    return left, right


# ---------------------------------------------------------------------------
# 10a. victory_theme_gentle.wav -- warm, peaceful, spacious music-box melody.
# ---------------------------------------------------------------------------

def gen_victory_gentle_phrase(phrase_duration: float) -> list:
    pad_notes = [349.23, 440.00, 523.25]  # F4-A4-C5, warm major pad.
    pad_layers = [
        harmonic_bell(f, phrase_duration, amp=0.15, decay=1.0,
                      harmonics=((1.0, 1.0), (2.0, 0.2)))
        for f in pad_notes
    ]

    melody_notes = [523.25, 659.25, 587.33, 440.00, 523.25]
    melody_times = [0.0, 0.9, 1.8, 2.6, 3.4]
    melody_layers = []
    melody_offsets = []
    for f, t in zip(melody_notes, melody_times):
        remaining = max(0.1, phrase_duration - t)
        bell = harmonic_bell(f, min(1.3, remaining), amp=0.32, decay=2.2,
                              harmonics=((1.0, 1.0), (2.0, 0.35), (3.0, 0.12)))
        melody_layers.append(bell)
        melody_offsets.append(n_samples(t))

    all_layers = pad_layers + melody_layers
    all_offsets = [0] * len(pad_layers) + melody_offsets
    phrase = mix(all_layers, offsets=all_offsets)
    return _pad_or_trim(phrase, phrase_duration)


def gen_victory_theme_gentle() -> tuple:
    phrase_duration = 4.2
    repeats = 3  # 12.6s
    return build_looping_theme(gen_victory_gentle_phrase, phrase_duration, repeats, peak=0.68)


# ---------------------------------------------------------------------------
# 10b. victory_theme_enchanted.wav -- sparkling, hopeful, brighter chimes.
# ---------------------------------------------------------------------------

def gen_victory_enchanted_phrase(phrase_duration: float) -> list:
    pad_notes = [392.00, 493.88, 587.33, 880.00]  # G4-B4-D5-A5, bright/open.
    pad_layers = [
        harmonic_bell(f, phrase_duration, amp=0.11, decay=1.1,
                      harmonics=((1.0, 1.0), (2.0, 0.25)))
        for f in pad_notes
    ]

    melody_notes = [783.99, 987.77, 1174.66, 987.77, 1318.51, 1174.66]
    melody_times = [0.0, 0.45, 0.9, 1.45, 1.9, 2.45]
    melody_layers = []
    melody_offsets = []
    for f, t in zip(melody_notes, melody_times):
        remaining = max(0.1, phrase_duration - t)
        bell = harmonic_bell(f, min(0.75, remaining), amp=0.3, decay=3.6,
                              harmonics=((1.0, 1.0), (2.0, 0.3), (3.0, 0.14)))
        melody_layers.append(bell)
        melody_offsets.append(n_samples(t))

    sparkle_times = [0.2, 1.2, 2.2, 3.0]
    sparkle_layers = []
    sparkle_offsets = []
    for t in sparkle_times:
        remaining = max(0.05, phrase_duration - t)
        bell = harmonic_bell(2093.00, min(0.3, remaining), amp=0.14, decay=12.0)
        sparkle_layers.append(bell)
        sparkle_offsets.append(n_samples(t))

    all_layers = pad_layers + melody_layers + sparkle_layers
    all_offsets = [0] * len(pad_layers) + melody_offsets + sparkle_offsets
    phrase = mix(all_layers, offsets=all_offsets)
    return _pad_or_trim(phrase, phrase_duration)


def gen_victory_theme_enchanted() -> tuple:
    phrase_duration = 3.4
    repeats = 4  # 13.6s
    return build_looping_theme(gen_victory_enchanted_phrase, phrase_duration, repeats, peak=0.72)


# ---------------------------------------------------------------------------
# 10c. victory_theme_triumphant.wav -- celebratory ascending melody, warm
# chord progression, light rhythmic pulse (soft plucked bell, not a drum).
# ---------------------------------------------------------------------------

def gen_victory_triumphant_phrase(phrase_duration: float) -> list:
    half = phrase_duration / 2.0
    chord_a = [261.63, 329.63, 392.00]   # C4-E4-G4
    chord_b = [293.66, 349.23, 440.00]   # D4-F4-A4
    layers = []
    offsets = []
    for f in chord_a:
        bell = harmonic_bell(f, half, amp=0.14, decay=1.3,
                              harmonics=((1.0, 1.0), (2.0, 0.22)))
        layers.append(bell)
        offsets.append(0)
    for f in chord_b:
        bell = harmonic_bell(f, half, amp=0.14, decay=1.3,
                              harmonics=((1.0, 1.0), (2.0, 0.22)))
        layers.append(bell)
        offsets.append(n_samples(half))

    melody_notes = [523.25, 659.25, 783.99, 1046.50]
    melody_times = [0.0, 0.55, 1.1, 1.7]
    for f, t in zip(melody_notes, melody_times):
        remaining = max(0.1, phrase_duration - t)
        bell = harmonic_bell(f, min(0.85, remaining), amp=0.3, decay=3.0,
                              harmonics=((1.0, 1.0), (2.0, 0.35), (3.0, 0.15)))
        layers.append(bell)
        offsets.append(n_samples(t))

    # Light rhythmic pulse -- a soft plucked low bell on a steady beat,
    # standing in for percussion without any actual drum hit.
    beat = phrase_duration / 4.0
    for i in range(4):
        t = i * beat
        remaining = max(0.05, phrase_duration - t)
        bell = harmonic_bell(130.81, min(beat * 0.5, remaining), amp=0.16, decay=9.0,
                              harmonics=((1.0, 1.0),))
        layers.append(bell)
        offsets.append(n_samples(t))

    phrase = mix(layers, offsets=offsets)
    return _pad_or_trim(phrase, phrase_duration)


def gen_victory_theme_triumphant() -> tuple:
    phrase_duration = 3.6
    repeats = 4  # 14.4s
    return build_looping_theme(gen_victory_triumphant_phrase, phrase_duration, repeats, peak=0.72)


# ---------------------------------------------------------------------------

def main() -> None:
    os.makedirs(SFX_DIR, exist_ok=True)

    sfx = {
        "jump.wav": gen_jump,
        "double_jump.wav": gen_double_jump,
        "double_jump_air.wav": gen_double_jump_air,
        "double_jump_spectral.wav": gen_double_jump_spectral,
        "double_jump_magic.wav": gen_double_jump_magic,
        "double_jump_ghost_burst.wav": gen_double_jump_ghost_burst,
        "portal_enter.wav": gen_portal_enter,
        "ghost_hurt.wav": gen_ghost_hurt,
        "ghost_death.wav": gen_ghost_death,
        "superpower_activate.wav": gen_superpower_activate,
        "pure_orb_collect.wav": gen_pure_orb_collect,
        "victory_chime.wav": gen_victory_chime,
    }
    for filename, gen_fn in sfx.items():
        samples = gen_fn()
        path = os.path.join(SFX_DIR, filename)
        write_wav_mono(path, samples)
        print(f"wrote {path}  ({len(samples) / SR:.3f}s, mono)")

    stereo_themes = {
        "victory_theme.wav": gen_victory_theme,
        "victory_theme_gentle.wav": gen_victory_theme_gentle,
        "victory_theme_enchanted.wav": gen_victory_theme_enchanted,
        "victory_theme_triumphant.wav": gen_victory_theme_triumphant,
        "superpower_theme.wav": gen_superpower_theme,
    }
    stereo_sfx = {
        "sfx/stealth_ambience.wav": gen_stealth_ambience,
    }
    stereo_themes.update(stereo_sfx)
    for filename, gen_fn in stereo_themes.items():
        left, right = gen_fn()
        path = os.path.join(OUT_DIR, filename)
        write_wav_stereo(path, left, right)
        print(f"wrote {path}  ({len(left) / SR:.3f}s, stereo)")


if __name__ == "__main__":
    main()
