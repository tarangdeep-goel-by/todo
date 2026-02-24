import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Shared centered loading spinner
class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: AppColors.darkText,
      ),
    );
  }
}
