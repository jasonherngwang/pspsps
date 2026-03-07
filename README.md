<p align="center">
  <img src="pspsps.png" width="280" alt="pspsps logo" />
</p>

<p align="center">
  <strong>Local voice-to-text for macOS</strong><br>
  Parakeet or WhisperKit + Qwen3.5 post-processing
</p>

---

## pspsps 😸

- **ASR engines**: [Parakeet TDT](https://github.com/FluidInference/FluidAudio) or [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- **Push-to-talk or toggle mode**: configurable hotkey
- **Optional LLM cleanup**: route transcripts through a local [Ollama](https://ollama.ai) model like Qwen3.5 to fix punctuation and remove filler words (slow and not necessary IMO)

## Setup

```bash
git clone https://github.com/your-username/pspsps.git
cd pspsps
open pspsps.xcodeproj
```

Build and run in Xcode (`⌘R`). On first launch, the onboarding flow will:

1. Download Parakeet (default, ~480 MB) or WhisperKit (~600 MB)
2. Grant Accessibility to type transcribed text into other apps
3. Grant Microphone to capture audio

## Development

```bash
# Debug build + run
./build_dev.sh

# Release build + run
./build_and_run.sh

# Run tests
xcodebuild test -project pspsps.xcodeproj -scheme pspsps -destination 'platform=macOS'
```
