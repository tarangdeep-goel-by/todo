import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/recording_provider.dart';
import '../utils/agent_response_handler.dart';

/// Overlay pill for typing and processing states (sits above bottom nav)
class PttInputOverlay extends ConsumerStatefulWidget {
  const PttInputOverlay({super.key});

  @override
  ConsumerState<PttInputOverlay> createState() => _PttInputOverlayState();
}

class _PttInputOverlayState extends ConsumerState<PttInputOverlay> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingStateProvider);

    if (recordingState == RecordingState.idle ||
        recordingState == RecordingState.listening) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isProcessing = recordingState == RecordingState.processing;

    final width = isProcessing ? AppSpacing.ctaActiveWidth : screenWidth - 48;
    final height =
        isProcessing ? AppSpacing.ctaActiveHeight : AppSpacing.ctaIdleHeight;

    final idleText = AppColors.darkBg;
    final activeBg = DomainColors.workDark.primary;
    final activeText = DomainColors.workDark.textOnPrimary;
    final bgColor = isProcessing ? activeBg : AppColors.darkText;

    return Center(
      child: AnimatedContainer(
        duration: AppAnimations.ctaExpand,
        curve: AppAnimations.easeOutQuint,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        clipBehavior: Clip.antiAlias,
        child: isProcessing
            ? _buildProcessingContent(activeText)
            : _buildTypingContent(idleText),
      ),
    );
  }

  Widget _buildProcessingContent(Color activeText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedOpacity(
            opacity: 0.5 + (0.5 * ((index + 1) % 3) / 2),
            duration: const Duration(milliseconds: 500),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: activeText,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTypingContent(Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: _cancelTyping,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          // Text field
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              autofocus: true,
              style: AppTypography.ctaLabelText(color: textColor),
              decoration: InputDecoration(
                hintText: 'What do you want to do?',
                hintStyle: AppTypography.ctaLabelText(
                  color: textColor.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onSubmitted: (_) => _submitText(),
              textInputAction: TextInputAction.send,
            ),
          ),
          // Send button
          GestureDetector(
            onTap: _submitText,
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                size: 18,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === Actions ===

  Future<void> _submitText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _cancelTyping();
      return;
    }

    _focusNode.unfocus();
    _textController.clear();

    await _processCommand(text);
  }

  void _cancelTyping() {
    _focusNode.unfocus();
    _textController.clear();
    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
  }

  Future<void> _processCommand(String text) async {
    ref.read(recordingStateProvider.notifier).state = RecordingState.processing;

    await processAndHandleAgentResponse(
      context: context,
      ref: ref,
      text: text,
    );

    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
  }
}
