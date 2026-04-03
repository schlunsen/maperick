# Web Presenter

An interactive, narrated presentation framework built with HTML, CSS, and Three.js. No build step required.

Give an AI agent your idea, point it at this repo, and let it build you a stunning animated presentation — complete with narration, background music, and WebGL visuals.

## Features

- **Animated Slides** — Smooth CSS transitions with phased element animations
- **Audio Narration** — Per-slide MP3 narration with Web Audio API reverb
- **Background Music** — Looping background track with automatic ducking
- **Three.js Background** — Animated network topology with hex grid, ripples, and data streams
- **Touch & Keyboard** — Arrow keys, space, swipe gestures, and click navigation
- **Auto-advance** — Slides advance automatically when narration ends
- **Progress Indicators** — Dot navigation, slide counter, and audio progress bar
- **Multiple Layouts** — Title, center, two-column, dashboard, and more
- **Dark Theme** — Terminal-inspired design with CSS custom properties
- **Zero Dependencies** — No npm, no build step. Just HTML files.
- **Studio Tools** — Built-in creator & editor powered by LLMs (Claude, OpenAI, DeepSeek, Ollama, etc.)

## How to Use This Project

The idea is simple: **clone this repo, get a HuggingFace API key, and let an AI agent build your presentation.**

### 1. Clone the repo

```bash
git clone https://github.com/schlunsen/web-presenter.git
cd web-presenter
```

### 2. Get a HuggingFace API key

You need an `HF_TOKEN` for generating narration audio and images.

1. Create a free account at [huggingface.co](https://huggingface.co)
2. Go to [Settings > Access Tokens](https://huggingface.co/settings/tokens)
3. Create a new token with **read** access
4. Export it in your shell:

```bash
export HF_TOKEN="hf_your_token_here"
```

### 3. Let the agent run wild

Point your favourite AI coding agent (Claude Code, Cursor, Copilot, Aider, etc.) at this project and tell it what presentation you want. For example:

> "Create a 10-slide presentation about the history of space exploration. Make it dramatic and inspiring. Generate narration audio and images."

The agent can:

- **Edit `index.html`** — Write your slide content using the built-in layout system
- **Edit `generate-assets.py`** — Update the `NARRATIONS` dict with your slide scripts and `IMAGE_PROMPTS` with your image descriptions
- **Run `python3 generate-assets.py all`** — Generate TTS narration (via Edge TTS) and images (via HuggingFace FLUX)
- **Run `python3 clone-voice.py`** — Clone a voice from a sample (optional, requires ffmpeg)
- **Tweak styles in `presentation-styles.css`** — Customise colours, fonts, and animations

That's it. The agent handles the content, the scripts handle asset generation, and you get a polished presentation.

### 4. Preview your presentation

```bash
python3 -m http.server 8000
# Open http://localhost:8000
```

Or use the task runner:

```bash
just open    # serve + open browser
just live    # live-reload (requires: npm i -g live-server)
```

## Using the Studio (Browser-based)

Web Presenter also includes browser-based tools for creating and editing presentations with LLM assistance:

- **Creator** (`creator.html`) — A questionnaire that generates a full slide deck via LLM
- **Editor** (`editor.html`) — Per-slide HTML editor with LLM chat for refinements

To use these, you'll need an LLM API key (Anthropic, OpenAI, DeepSeek, etc.) which you enter directly in the browser. The key is stored in localStorage and never sent to any server other than the LLM provider.

```bash
just create   # open the creator
just edit     # open the editor
```

## Python Dependencies

The asset generation scripts need a few pip packages:

```bash
pip install edge-tts huggingface_hub requests
```

- `edge-tts` — Free Microsoft Edge TTS for narration
- `huggingface_hub` — Image generation via FLUX.1-schnell
- `requests` — HTTP calls

Optional, for voice cloning:

```bash
brew install ffmpeg   # or apt install ffmpeg
```

## Project Structure

```
web-presenter/
├── index.html                 # Your presentation (edit this!)
├── generate-assets.py         # TTS + image generation script
├── clone-voice.py             # Voice cloning script
├── justfile                   # Task runner commands
│
├── engine/                    # Core presentation engine
│   ├── presentation-script.js # Navigation, animations, audio
│   ├── presentation-styles.css# Slide styles and layouts
│   ├── presentation-bg.js     # Three.js animated background
│   └── three.min.js           # Three.js library
│
├── studio/                    # Browser-based creator & editor
│   ├── llm-client.js          # Multi-provider LLM client
│   ├── creator.js             # Questionnaire → slides pipeline
│   ├── editor.js              # Per-slide editor with LLM chat
│   ├── asset-generator.js     # HF TTS + image generation
│   └── slide-templates.js     # System prompts and templates
│
├── presentation-audio/        # Generated MP3 narration + music
└── presentation-images/       # Generated slide images
```

## Customization Reference

### Slide Layouts

Each slide is a `<section class="slide">` element. Available layout classes:

- `slide-title-layout` — Centered title with icon
- `slide-center-layout` — Centered content
- `slide-two-col` — Two-column grid
- `slide-two-col-reverse` — Reversed two-column

### Audio Narration

Place MP3 files in `presentation-audio/`:
- `slide-01.mp3` through `slide-NN.mp3` for per-slide narration
- `bg-music.mp3` for background music

### Theming

Edit CSS custom properties in `engine/presentation-styles.css`:

```css
:root {
  --bg: #0a0a0f;
  --cyan: #67e8f9;
  --purple: #a78bfa;
  --text: #e8e8e8;
}
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Arrow Right / Space | Next slide |
| Arrow Left | Previous slide |
| A | Toggle narration |
| M | Toggle music |

## Deploy to GitHub Pages

1. Push to a GitHub repository
2. Go to Settings > Pages
3. Set source to "main" branch, root directory
4. Your presentation is live!

## License

MIT
