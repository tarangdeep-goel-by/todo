import 'package:integration_test/integration_test.dart';

// Import flow test files — each defines its own main() with testWidgets
// Run individual flows:
//   flutter test integration_test/flows/create_task_test.dart -d emulator --dart-define=TEST_MODE=true
// Or run all:
//   flutter test integration_test/ -d emulator --dart-define=TEST_MODE=true

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Individual flow files are self-contained — run them directly
}
