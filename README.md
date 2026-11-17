<div align="center">

<img src=".github/assets/Musify-banner.png" alt="Musify Banner" width="100%">

# Musify

**Stream effortlessly with one app — online & offline music, party speaker sync, and collaborative jukebox.**

</div>

---

## Features

- **Local Wi-Fi Synchronized Speaker (Party Mode)**: Connect multiple phones and laptops over local Wi-Fi or hotspot as synchronized group speakers with millisecond-level clock sync and adaptive drift compensation.
- **Collaborative Party Jukebox**: Let guests browse the party queue, search and request tracks, and vote on upcoming songs in real-time. Toggle between DJ Mode (host-only) and Collaborative Mode.
- **Spotify Playlist CSV Import**: Easily import Spotify playlists via CSV with automatic matching, instant statistics breakdown, and one-tap library integration.
- **Online & Offline Playback**: Stream songs online, or download and cache tracks for complete offline listening.
- **Custom Playlists & Queue Management**: Create custom playlists, reorder queues, and manage your music library seamlessly.
- **Built-in Equalizer**: Audio equalizer with customizable presets to optimize your sound experience.
- **Lyrics & SponsorBlock**: Real-time synced lyrics support and automatic SponsorBlock skipping.
- **Ad-Free Experience**: No advertisements, no subscriptions, completely free.
- **Cross-Platform**: Runs on Android, iOS, Windows, macOS, Linux, and Web.
- **Modern Material Design**: Material UI styling with dynamic color support and dark/light themes.

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.24+ recommended)
- Java 17+ and Android SDK (for Android build)
- Visual Studio C++ toolchain (for Windows desktop build)
- Xcode (for iOS and macOS build)

### Building & Running

1. **Clone the repository:**
   ```bash
   git clone https://github.com/athul-athu/Musifyy.git
   cd Musifyy
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run on your device:**
   ```bash
   # Run on connected phone or emulator
   flutter run

   # Run on Windows desktop
   flutter run -d windows
   ```

4. **Run tests:**
   ```bash
   flutter test
   ```

---

## Party Mode & Sync Architecture

Musify includes a built-in local synchronization engine:
- **Monotonic Clock Sync**: Calculates network RTT and clock offset across devices using least-squares linear regression (OLS) to estimate and filter out drift (PPM).
- **Adaptive PI Controller**: Eliminates drift in real-time with continuous micro-speed adjustments (±3%) without audible pitch artifacts.
- **Two-Phase Handshake**: Coordinates play, pause, seek, and song transitions across all connected speaker nodes with millisecond accuracy.

---

## Disclaimer

Musify and its contributors do not host, own, or distribute any copyrighted audio content. The application retrieves audio streams through third-party services for interoperability and personal use. All trademarks, songs, audio files, and metadata remain the property of their respective owners. Users are solely responsible for ensuring their usage complies with local laws and terms of service.
