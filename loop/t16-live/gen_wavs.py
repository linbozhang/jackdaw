#!/usr/bin/env python3
"""Generate the template's fixture audio: small, loopable, self-explanatory.

T16 template ships three tiny wav files so a fresh project has something to
play with zero user assets. Regenerate with:
    python3 gen_wavs.py <output-dir>
"""
import math
import struct
import sys
import wave

RATE = 22050


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
        )
        w.writeframes(frames)


def bgm(seconds=2.0):
    """A soft two-note pad, periodic over its length so Loop is seamless."""
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        # 220 Hz + 275 Hz: integer cycle counts over 2 s (440 and 550), so the
        # waveform joins itself when the loop wraps.
        s = 0.22 * math.sin(2 * math.pi * 220 * t) + 0.16 * math.sin(2 * math.pi * 275 * t)
        out.append(s)
    return out


def blip(seconds=0.12):
    """A short UI-ish tone with an exponential decay."""
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 28.0)
        out.append(0.5 * env * math.sin(2 * math.pi * 880 * t))
    return out


def ambient(seconds=3.0):
    """A low drone for the spatial scene sound, periodic over its length."""
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.2 * math.sin(2 * math.pi * 110 * t) + 0.1 * math.sin(2 * math.pi * 147 * t)
        out.append(s)
    return out


if __name__ == "__main__":
    dest = sys.argv[1]
    write_wav(f"{dest}/bgm.wav", bgm())
    write_wav(f"{dest}/blip.wav", blip())
    write_wav(f"{dest}/ambient.wav", ambient())
    print("wrote bgm.wav blip.wav ambient.wav to", dest)
