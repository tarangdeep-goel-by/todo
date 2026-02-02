# VOKL Frontend - Maximalist Voice-First Todo App

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
Ensure the FastAPI backend is running on `http://localhost:8001` or update the base URL in `lib/config/constants.dart`.

### 3. Run the App
```bash
# Connect Android device or start emulator
flutter devices

# Run on Android
flutter run
```

## Next Steps

1. Test app launch on Android device
3. Implement liquid focus scroll
4. Connect audio recording to push-to-talk button
5. Test backend integration
6. Add animations and polish
