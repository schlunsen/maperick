#!/usr/bin/env python3
"""Generate TTS narration (Edge TTS) and images (HuggingFace) for the Maperick presentation."""

import asyncio
import os
import sys

AUDIO_DIR = "presentation-audio"
IMAGE_DIR = "presentation-images"

os.makedirs(AUDIO_DIR, exist_ok=True)
os.makedirs(IMAGE_DIR, exist_ok=True)

# ── Maperick Slide Narrations ──
# Presenter A (slides 1-4): Energetic, introducing the problem and solution
# Presenter B (slides 5-8): Technical, demonstrating features and getting started
NARRATIONS = {
    1: "Welcome to Maperick! The network visualization tool that shows you exactly where your data is going. Have you ever wondered which countries your computer is talking to right now? Maperick answers that question in real time, plotting every TCP connection on a beautiful world map.",
    2: "Every day, your computer makes hundreds of network connections. But IP addresses don't tell you the physical location. Standard tools show raw data, not insights. And network analysis requires expertise you shouldn't need. This is the challenge we set out to solve.",
    3: "Introducing Maperick! A lightweight tool that resolves every outgoing TCP connection to a geographic location and plots it on an ASCII world map, right in your terminal. Real-time tracking, automatic GeoIP resolution, and zero configuration required.",
    4: "The terminal UI is built with Ratatui for a smooth, responsive experience. You get three views: a world map showing all connections, a server view with location data, and a process view grouping connections by running application. Everything updates in real time.",
    5: "For macOS users, we built a native menu bar app with a stunning 3D globe visualization. Built with SwiftUI and SceneKit, it lives in your menu bar and shows your connections with beautiful arcs across an interactive globe. Plus persistent history and statistics.",
    6: "Under the hood, Maperick is built with modern technology. The terminal app uses Rust for high performance and cross-platform support. The Mac app uses SwiftUI with SceneKit for native 3D rendering. Both share the same GeoIP lookup engine.",
    7: "Location data comes from MaxMind GeoLite2, the industry standard for IP geolocation. The database is automatically downloaded and cached on first run. Connections flow through four stages: detection, IP lookup, geolocation, and map display.",
    8: "Ready to get started? Clone the repository and run with Cargo. Or download the Mac app from GitHub releases. Maperick is open source under the MIT license. Visit github.com/schlunsen/maperick to start visualizing your network today!",
}

# Per-presenter voices
# Presenter A (slides 1-4): Warm, friendly female voice
# Presenter B (slides 5-8): Confident male voice
VOICES = {
    "presenter_a": {"voice": "en-US-JennyNeural", "rate": "+0%", "pitch": "+0Hz"},
    "presenter_b": {"voice": "en-US-AndrewNeural", "rate": "-5%", "pitch": "+0Hz"},
}

def get_voice_for_slide(slide_num):
    """Return the voice config dict for a given slide number (1-based)."""
    if slide_num <= 4:
        return VOICES["presenter_a"]
    return VOICES["presenter_b"]


# ── Generate TTS audio via Edge TTS ──
async def generate_tts(slide_num, text):
    """Generate TTS using Microsoft Edge TTS (free, high quality)."""
    import edge_tts

    vcfg = get_voice_for_slide(slide_num)
    voice, rate, pitch = vcfg["voice"], vcfg["rate"], vcfg["pitch"]
    print(f"  [TTS] Slide {slide_num:02d}: generating ({voice}, rate={rate}, pitch={pitch})...")
    outpath = os.path.join(AUDIO_DIR, f"slide-{slide_num:02d}.mp3")
    try:
        communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
        await communicate.save(outpath)
        size_kb = os.path.getsize(outpath) / 1024
        print(f"  [TTS] Slide {slide_num:02d}: OK ({size_kb:.0f} KB)")
        return True
    except Exception as e:
        print(f"  [TTS] Slide {slide_num:02d}: FAILED - {e}")
        return False


async def generate_all_tts():
    """Generate TTS for all slides sequentially."""
    for slide_num, text in NARRATIONS.items():
        await generate_tts(slide_num, text)


# ── Generate images via HuggingFace ──
IMAGE_PROMPTS = {
    "slide-05-macapp": "3D holographic globe floating in dark space with glowing cyan and magenta network connection arcs between continents, futuristic macOS interface, dark theme, glass and neon aesthetics, high quality render",
    "slide-01-hero": "abstract network visualization with glowing nodes on a dark world map, cyan and magenta colors, tech aesthetic, particles and data streams, minimalist, 4k render",
}


def generate_image(name, prompt):
    """Generate image using FLUX.1-schnell via HuggingFace."""
    from huggingface_hub import InferenceClient

    HF_TOKEN = os.environ.get("HF_TOKEN", "")
    client = InferenceClient(token=HF_TOKEN)

    print(f"  [IMG] {name}: generating...")
    try:
        image = client.text_to_image(
            prompt,
            model="black-forest-labs/FLUX.1-schnell",
            width=1024,
            height=576,
        )
        outpath = os.path.join(IMAGE_DIR, f"{name}.png")
        image.save(outpath)
        size_kb = os.path.getsize(outpath) / 1024
        print(f"  [IMG] {name}: OK ({size_kb:.0f} KB)")
        return True
    except Exception as e:
        print(f"  [IMG] {name}: FAILED - {e}")
        return False


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"

    if mode in ("all", "tts"):
        print("\n=== Generating TTS narration (Edge TTS) ===")
        asyncio.run(generate_all_tts())

    if mode in ("all", "images"):
        print("\n=== Generating images (HuggingFace FLUX) ===")
        for name, prompt in IMAGE_PROMPTS.items():
            generate_image(name, prompt)

    print("\n=== Done ===")
