# VOKL Frontend - Maximalist Voice-First Todo App

> Historical, as of 2026-02-02 (Phase 1; the app has since been renamed Amble). Current state: see [README.md](../README.md) and [docs/NOTES.md](../docs/NOTES.md). The Status and Next Steps sections below describe that early state.

Flutter mobile app implementing the VOKL design brief for voice-first task management.

## Status

**Phase 1 Complete**: Foundation & Core UI
- ✅ Project setup (Flutter 3.38+, Android + iOS targets)
- ✅ Design system (OKLCH colors, typography, spacing)
- ✅ Theme system (light/dark modes for 5 domains)
- ✅ Base app structure (Riverpod state management)
- ✅ Parent Node View (domain cards)
- ✅ Flat Task View (all tasks list)
- ✅ Push-to-Talk button UI
- ✅ Waveform visualization
- ✅ View toggle (Node/Flat)
- ✅ Backend API client (Dio)
- ✅ Audio service (record package)

**Pending**:
- ⏳ Liquid focus scroll animation
- ⏳ Card expand/contract animation
- ⏳ Grain texture overlays
- ⏳ Enhanced shadows
- ⏳ View transition animations (fracture/cluster)
- ⏳ Audio recording integration
- ⏳ Backend integration testing
- ⏳ Empty states, error handling
- ⏳ Accessibility (screen readers, reduce motion)

## Setup

### 1. Install Dependencies
```bash
cd frontend
flutter pub get
```

### 2. Backend Setup
Ensure the FastAPI backend is running (`cd ../backend && docker compose up --build`, API on port 8001). The app reads its base URL from `--dart-define=API_BASE_URL=...` (`lib/config/environment.dart`), defaulting to `http://10.0.2.2:8001/api` (the Android emulator's address for the host).

### 3. Run the App
```bash
# Connect Android device or start emulator
flutter devices

# Run on Android (use your machine's LAN IP on a physical device)
flutter run --dart-define=API_BASE_URL=http://<lan-ip>:8001/api
```

## Next Steps

1. Test app launch on Android device
3. Implement liquid focus scroll
4. Connect audio recording to push-to-talk button
5. Test backend integration
6. Add animations and polish
