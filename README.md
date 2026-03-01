# Ask Bhumchu

**A conversational companion for kids — powered entirely on-device by Apple Intelligence.**

Bhumchu is a virtual pet that doesn’t just repeat what you say: kids can **ask questions** and Bhumchu **answers out loud** using the device’s built-in language model. No servers, no accounts, no data leaving the device — just a friendly character that listens and responds.

---

## The Problem

Apps like Talking Tom made virtual pets fun, but they never really *talked back*. Kids would ask questions and get nothing but an echo. Bhumchu closes that gap: a companion that actually **understands and answers** in a safe, private way.

---

## Features

- **Talk to Bhumchu** — Type any question in the bar; Bhumchu answers using on-device Apple Intelligence and speaks the response.
- **Care for Bhumchu** — Feed, play, put to sleep, and tap to tickle. Each action has its own short video and feedback.
- **Hear a story** — Tap the book button; Bhumchu tells a short story and reads it aloud.
- **Stats that matter** — Hunger, happiness, and sleep are shown as rings around the care buttons and decay over time so kids learn to come back and care for their pet.
- **First-time experience** — Short intro screens about Bhumchu, then an in-app tutorial that points to each button so new users know exactly what to do.
- **Fully on-device** — Uses Foundation Models and AVSpeechSynthesizer; no cloud, no API keys, no privacy concerns.

---

## Screenshots

<p align="center">
  <img src="https://github.com/user-attachments/assets/da7009b6-d551-4092-b589-86388b3019d3" width="280" alt="Simulator Screenshot - iPhone 17 Pro Max - 23 08 40" />
  <img src="https://github.com/user-attachments/assets/58456e8e-2e97-4e63-a4ac-dc1a8017fbab" width="280" alt="Simulator Screenshot - iPhone 17 Pro Max - 23 15 37" />
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/a12ecdd3-a299-49f8-9318-265afea89e9c" width="280" alt="Simulator Screenshot - iPhone 17 Pro Max - 23 08 11" />
  <img src="https://github.com/user-attachments/assets/f410e247-4791-4d8f-b1be-ab7747b837de" width="280" alt="Simulator Screenshot - iPhone 17 Pro Max - 15 58 23" />
</p>

---

## Requirements

- **Xcode** (Swift 6)
- **iOS 26** (or later) with **Apple Intelligence** enabled
- **Swift Package** — open the `Bhumchu.swiftpm` folder in Xcode or open the parent folder and select the package

---

## Tech Stack

| Area | Technology |
|------|------------|
| **UI** | SwiftUI, Liquid Glass (`.glassEffect`) |
| **Conversation** | Foundation Models (on-device), `LanguageModelSession` |
| **Speech** | AVSpeechSynthesizer (on-device TTS) |
| **Video** | AVPlayer / AVQueuePlayer, looping and one-shot clips |
| **Assets** | Animated GIF splash (ImageIO), PNG thought clouds, MP4 character videos |

---

## Project Structure

```
AskBhumchu/
├── README.md
└── Bhumchu.swiftpm/
    ├── Package.swift          # App target, resources
    ├── ContentView.swift       # Main UI, videos, tutorial, chat
    ├── MyApp.swift            # App entry
    ├── Assets.xcassets        # App icon
    ├── Ask.gif                # Splash screen
    ├── cloud/                 # Thought-bubble frames (cloud1–9)
    ├── bhumchuintro.mp4       # Intro video
    ├── bhumchutalk.mp4        # Talking state
    ├── bhumchuplay.mp4        # Playing
    ├── bhumchuread.mp4        # Reading story
    ├── bhumchusleeping.mp4   # Sleeping
    ├── bhumchueat.mp4        # Eating
    └── bhumchutickle.mp4     # Tickle reaction
```

---

## How to Run

1. Clone the repo:  
   `git clone git@github.com:bhanumeet/AskBhumchu.git`
2. Open `Bhumchu.swiftpm` in Xcode (or open the `AskBhumchu` folder and choose the package).
3. Select an iOS 26 simulator or device with Apple Intelligence.
4. Build and run (⌘R).

---

## License

This project is for the Swift Student Challenge. See the repository for license details.

---

## Author

**bhanumeet** — [GitHub](https://github.com/bhanumeet)
