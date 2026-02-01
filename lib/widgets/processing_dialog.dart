import 'package:flutter/material.dart';

/// Dialog shown while processing voice commands
class ProcessingDialog extends StatelessWidget {
  final String message;

  const ProcessingDialog({
    super.key,
    this.message = 'Processing your command...',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}
