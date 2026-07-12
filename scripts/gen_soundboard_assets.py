#!/usr/bin/env python3
"""
Generates 4 placeholder soundboard assets (WAV format, 44.1kHz, 16-bit, mono).
Outputs to .superpowers/soundboard/ directory.

Sounds:
- airhorn.wav: stacked square waves with pitch rise + amplitude sustain
- lets-go.wav: two rising sine sweeps back-to-back
- ding.wav: sine tone 1568Hz with exponential decay
- boo.wav: square wave descending (160→110Hz) with decay
"""
import os
import sys
import math
import wave
import struct
from pathlib import Path

SAMPLE_RATE = 44100
BIT_DEPTH = 16
CHANNELS = 1


def sine_wave(freq, duration_s, amplitude=0.7):
    """Generate sine wave samples."""
    num_samples = int(SAMPLE_RATE * duration_s)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        sample = amplitude * math.sin(2 * math.pi * freq * t)
        samples.append(sample)
    return samples


def square_wave(freq, duration_s, amplitude=0.7):
    """Generate square wave samples."""
    num_samples = int(SAMPLE_RATE * duration_s)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        period = SAMPLE_RATE / freq
        phase = (i % period) / period
        sample = amplitude if phase < 0.5 else -amplitude
        samples.append(sample)
    return samples


def frequency_sweep(start_freq, end_freq, duration_s, amplitude=0.7):
    """Generate sine wave sweep from start_freq to end_freq."""
    num_samples = int(SAMPLE_RATE * duration_s)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Linear frequency sweep
        freq = start_freq + (end_freq - start_freq) * (t / duration_s)
        # Integrate frequency to get phase
        phase = 2 * math.pi * (
            start_freq * t + (end_freq - start_freq) * t * t / (2 * duration_s)
        )
        sample = amplitude * math.sin(phase)
        samples.append(sample)
    return samples


def exponential_decay(samples, decay_rate=0.95):
    """Apply exponential decay envelope to samples."""
    result = []
    for i, sample in enumerate(samples):
        decay = decay_rate ** (i / SAMPLE_RATE)
        result.append(sample * decay)
    return result


def normalize_samples(samples, target_level=0.7):
    """Normalize samples to ~70% of full scale."""
    max_val = max(abs(s) for s in samples) if samples else 1.0
    if max_val > 0:
        scale = (target_level * 32767) / (max_val * 32767)
        samples = [s * scale for s in samples]
    return samples


def samples_to_int16(samples):
    """Convert float samples [-1, 1] to int16 PCM."""
    pcm = []
    for sample in samples:
        # Clamp to [-1, 1]
        clamped = max(-1.0, min(1.0, sample))
        # Convert to int16 range
        int_val = int(clamped * 32767)
        pcm.append(int_val)
    return pcm


def write_wav(filepath, samples, sample_rate=SAMPLE_RATE, channels=1, bit_depth=16):
    """Write WAV file with proper headers."""
    pcm = samples_to_int16(samples)

    with wave.open(filepath, 'wb') as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(bit_depth // 8)
        wav_file.setframerate(sample_rate)

        for sample in pcm:
            wav_file.writeframes(struct.pack('<h', sample))


def get_duration_ms(num_samples):
    """Get duration in milliseconds."""
    return int((num_samples / SAMPLE_RATE) * 1000)


def generate_airhorn():
    """Airhorn: stacked square waves with pitch rise + amplitude sustain."""
    # Roughly 1.2s total
    base_duration = 1.2

    # Stacked square waves at ~440Hz, 445Hz, 880Hz
    # Slow pitch rise over the duration
    samples = []
    num_samples = int(SAMPLE_RATE * base_duration)

    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Base frequencies with slow rise
        f1 = 440 + (50 * (t / base_duration))  # 440 -> 490 Hz
        f2 = 445 + (50 * (t / base_duration))  # 445 -> 495 Hz
        f3 = 880 + (100 * (t / base_duration))  # 880 -> 980 Hz

        # Generate square waves
        period1 = SAMPLE_RATE / f1
        phase1 = (i % period1) / period1
        sq1 = 0.3 if phase1 < 0.5 else -0.3

        period2 = SAMPLE_RATE / f2
        phase2 = (i % period2) / period2
        sq2 = 0.3 if phase2 < 0.5 else -0.3

        period3 = SAMPLE_RATE / f3
        phase3 = (i % period3) / period3
        sq3 = 0.2 if phase3 < 0.5 else -0.2

        sample = sq1 + sq2 + sq3
        samples.append(sample)

    samples = normalize_samples(samples, target_level=0.7)
    return samples


def generate_lets_go():
    """Let's go: two rising sine sweeps back-to-back."""
    # Two rising sweeps: 300→600Hz and 400→800Hz, each ~0.4s
    sweep1 = frequency_sweep(300, 600, 0.4, amplitude=0.7)
    sweep2 = frequency_sweep(400, 800, 0.4, amplitude=0.7)

    samples = sweep1 + sweep2
    samples = normalize_samples(samples, target_level=0.7)
    return samples


def generate_ding():
    """Ding: sine 1568Hz with exponential decay (~1.0s)."""
    duration = 1.0
    samples = sine_wave(1568, duration, amplitude=0.7)
    samples = exponential_decay(samples, decay_rate=0.98)
    samples = normalize_samples(samples, target_level=0.7)
    return samples


def generate_boo():
    """Boo: square wave descending (160→110Hz) with decay (~1.0s)."""
    duration = 1.0
    num_samples = int(SAMPLE_RATE * duration)
    samples = []

    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Descending frequency: 160 -> 110 Hz
        freq = 160 - (50 * (t / duration))

        # Square wave
        period = SAMPLE_RATE / freq
        phase = (i % period) / period
        sample = 0.5 if phase < 0.5 else -0.5

        # Exponential decay
        decay = 0.98 ** (i / SAMPLE_RATE)
        sample = sample * decay
        samples.append(sample)

    samples = normalize_samples(samples, target_level=0.7)
    return samples


def main():
    output_dir = Path(__file__).parent.parent / '.superpowers' / 'soundboard'
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Generating soundboard assets to {output_dir}")

    # Generate and write each sound
    sounds = [
        ('airhorn.wav', generate_airhorn, 'Airhorn'),
        ('lets-go.wav', generate_lets_go, "Let's go"),
        ('ding.wav', generate_ding, 'Ding'),
        ('boo.wav', generate_boo, 'Boo'),
    ]

    for filename, generator, display_name in sounds:
        filepath = output_dir / filename
        print(f"  Generating {filename}...", end=' ')
        samples = generator()
        duration_ms = get_duration_ms(len(samples))
        write_wav(str(filepath), samples)
        print(f"OK {duration_ms}ms")

    print("Done!")


if __name__ == '__main__':
    main()
