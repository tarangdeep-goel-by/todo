# Todo - Voice-First AI Todo App

A voice-first AI-powered hierarchical todo list app built with Flutter.

## Features

- 🎙️ **Voice Recording**: Record tasks using your voice
- 🤖 **AI Transcription**: Automatic transcription using Google Gemini API
- 🧠 **Smart Categorization**: AI suggests task placement in your hierarchy
- 📊 **Hierarchical Tasks**: Organize tasks in unlimited depth tree structure
- ✅ **Smart Completion**: Intelligent task completion logic
- 🎨 **Material Design 3**: Beautiful, modern UI with smooth animations
- 📱 **Cross-Platform**: Works on iOS and Android

## Tech Stack

- **Framework**: Flutter 3.38+ / Dart 3.x
- **AI**: Google Gemini API (Gemini 2.0 Flash)
- **Database**: Drift (SQLite ORM)
- **State Management**: Riverpod
- **Navigation**: GoRouter
- **Audio**: record package

## Prerequisites

- Flutter SDK 3.38 or higher
- Dart SDK 3.x
- Google Gemini API key ([Get one here](https://ai.google.dev/))
- iOS: Xcode 15+ (for iOS development)
- Android: Android Studio (for Android development)

## Setup

### 1. Install Flutter

If you don't have Flutter installed:

```bash
# macOS (Homebrew)
brew install --cask flutter

# Verify installation
flutter doctor
```

### 2. Clone and Install Dependencies

```bash
cd todo
flutter pub get
```

### 3. Configure Gemini API Key

1. Get your API key from [Google AI Studio](https://ai.google.dev/)
2. Copy the environment template:
   ```bash
   cp lib/config/env.example.dart lib/config/env.dart
   ```
3. Edit `lib/config/env.dart` and replace `YOUR_API_KEY_HERE` with your actual API key

### 4. Generate Database Code

```bash
dart run build_runner build
```

### 5. Run the App

```bash
# iOS
flutter run -d ios

# Android
flutter run -d android

# Or select device interactively
flutter run
```

## Project Structure

```
todo/
├── lib/
│   ├── config/           # App configuration (theme, router, env)
│   ├── data/
│   │   ├── database/     # Drift database and tables
│   │   ├── models/       # Data models (Task, AIPlacement)
│   │   └── repositories/ # Data access layer
│   ├── providers/        # Riverpod providers
│   ├── screens/          # UI screens
│   ├── services/         # Business logic (Gemini, Audio, Permissions)
│   ├── utils/            # Utilities and constants
│   └── widgets/          # Reusable widgets
├── assets/
│   └── audio/            # Audio recordings (gitignored)
└── test/                 # Tests
```

## Usage

### Adding a Task

1. Tap the **+** button
2. Tap the microphone to record
3. Speak your task
4. AI will transcribe and suggest categorization
5. Accept or choose different placement
6. Task is saved!

### Managing Tasks

- **Complete**: Tap checkbox to mark done
- **View Details**: Tap task card
- **Expand/Collapse**: Tap chevron icon (if task has children)
- **Pull to Refresh**: Refresh task list

### Categories

- **Work**: Work-related tasks
- **Personal**: Personal tasks

Tasks can be nested infinitely under any category.

## Architecture

### Database (Drift)

- **Type-safe SQL**: Compile-time query validation
- **DAOs**: Clean data access layer
- **Migrations**: Schema versioning support

### State Management (Riverpod)

- **Providers**: Dependency injection
- **State Notifiers**: Reactive state management
- **Auto-disposal**: Automatic cleanup

### AI Integration

The app uses Google Gemini API for:
1. **Audio Transcription**: Convert speech to text
2. **Task Categorization**: Analyze task content and suggest placement
3. **Context-Aware**: Uses existing task tree for better suggestions

## Development

### Running Tests

```bash
# All tests
flutter test

# Specific test
flutter test test/widget_test.dart
```

### Code Analysis

```bash
flutter analyze
```

### Building for Release

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## Troubleshooting

### "No ProviderScope found"

Make sure `main.dart` wraps the app in `ProviderScope`:

```dart
void main() {
  runApp(const ProviderScope(child: TodoApp()));
}
```

### Microphone Permission Denied

- **iOS**: Check `ios/Runner/Info.plist` has `NSMicrophoneUsageDescription`
- **Android**: Check `android/app/src/main/AndroidManifest.xml` has `RECORD_AUDIO` permission

### Gemini API Errors

- Verify API key is correct in `lib/config/env.dart`
- Check API quota at [Google AI Studio](https://ai.google.dev/)
- Ensure internet connection is stable

### Database Migration Errors

If you change the database schema:

```bash
# Regenerate database code
dart run build_runner build --delete-conflicting-outputs
```

## Future Enhancements

- [ ] Multi-user support with authentication
- [ ] Cloud sync (Supabase integration)
- [ ] Real-time voice input (Gemini Live API)
- [ ] Task search and filters
- [ ] Task editing and reordering
- [ ] Recurring tasks
- [ ] Due date notifications
- [ ] Collaboration features
- [ ] Export/import tasks
- [ ] Analytics dashboard

## License

MIT

## Contributing

Contributions welcome! Please open an issue or submit a PR.

## Author

Tarang Goel - [GitHub](https://github.com/tarangdeep-goel-by)
