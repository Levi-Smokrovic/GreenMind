<div align="center">

# 🌱 GreenMind

**AI that doesn't cost the Earth.**

An AI assistant that runs **100% on your device** — no cloud, no data centers, no CO₂ emissions.  
Private, fast, and climate-friendly.

[Try in Browser](https://greenmind-brown.vercel.app/index.html) · [Download APK](https://github.com/Levi-Smokrovic/GreenMind/releases/latest/download/GreenMind.apk) · [Product Page](https://greenmind-brown.vercel.app)

</div>

---

## The Problem

Every time you ask ChatGPT or Gemini a question, massive data centers spin up GPUs that:

- **Consume ~4.32g CO₂ per query** (cloud inference)
- **Use ~25ml of water per query** for cooling
- **Send your private data** to remote servers
- AI data centers are projected to consume **552 TWh by 2026** — more electricity than many countries

## Our Solution

GreenMind runs the AI model **entirely on your device**. No server. No network request. No carbon.

| | Cloud AI (GPT, Gemini...) | 🌱 GreenMind |
|---|---|---|
| CO₂ per query | ~4.32g | **0g** |
| Water usage | ~25ml | **0ml** |
| Privacy | Sent to servers | **Never leaves device** |
| Offline | ❌ Requires internet | **✅ Fully offline** |
| Cost | $20–$200/month | **Free forever** |

## How It Works

GreenMind uses **Qwen 2.5 0.5B** — a state-of-the-art small language model, Q4 quantized to run efficiently on consumer hardware. The model downloads once on first launch (~400MB) and then runs fully offline.

- **Android** — Native ARM64 with [llama.cpp](https://github.com/ggml-org/llama.cpp) via [llamadart](https://pub.dev/packages/llamadart)
- **Web** — Multi-threaded WebAssembly via [Wllama.js](https://github.com/nicepkg/wllama) with SharedArrayBuffer

## Features

- 🧠 **On-device AI** — Qwen 2.5 0.5B runs locally, no cloud needed
- 📱 **Cross-platform** — Android (Flutter) and Web (vanilla JS + WASM)
- 🔐 **100% private** — conversations never leave your device
- 💬 **Chat history** — multiple conversations saved locally
- ⚡ **Hardware accelerated** — multi-threaded WASM in browsers, native ARM64 on Android
- 🌍 **Zero emissions** — no server infrastructure, no carbon footprint
- 💰 **Free forever** — no subscriptions, no API keys, no accounts

## Quick Start

### Web (Browser)

```bash
# Clone the repo
git clone https://github.com/Levi-Smokrovic/GreenMind.git
cd GreenMind

# Start the dev server (COOP/COEP headers required for multi-threaded WASM)
python3 serve.py
# Open http://localhost:8080
```

### Android

Download the APK from [GitHub Releases](https://github.com/Levi-Smokrovic/GreenMind/releases/latest) or build from source:

```bash
flutter build apk --release --target-platform android-arm64
```

### Deploy to Vercel

The repo includes `vercel.json` with COOP/COEP headers pre-configured. Just import the GitHub repo on [vercel.com](https://vercel.com) — no build step needed.

## Tech Stack

| Component | Technology |
|---|---|
| AI Model | Qwen 2.5 0.5B Instruct (Q4_K_M GGUF) |
| Mobile Framework | Flutter 3.38 + Dart |
| LLM Runtime (mobile) | llamadart (llama.cpp native) |
| LLM Runtime (web) | Wllama.js 2.3.7 (llama.cpp → WASM) |
| Chat Persistence | SharedPreferences (mobile), localStorage (web) |
| Hosting | Vercel (static, COOP/COEP headers) |

## Project Structure

```
├── product.html       # Landing page
├── index.html         # Web chat app
├── app.js             # Web chat logic (Wllama.js)
├── style.css          # Web styles
├── sw.js              # Service worker (PWA)
├── serve.py           # Dev server with COOP/COEP headers
├── vercel.json        # Vercel deployment config
├── lib/
│   ├── main.dart      # Flutter app entry
│   ├── chat_screen.dart  # Chat UI + llamadart integration
│   └── theme.dart     # Material 3 green theme
└── android/           # Android build configs
```

## Authors

Built with 💚 by **Levi**, **Neal**, and **Robin**.

## License

Open source. See the [GitHub repository](https://github.com/Levi-Smokrovic/GreenMind) for details.
