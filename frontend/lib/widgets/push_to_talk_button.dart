import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/recording_provider.dart';
import '../services/haptic_service.dart';
import '../utils/agent_response_handler.dart';
import 'ramble_sheet.dart';

/// Dual-mode input pill: tap for keyboard, long-press for ramble voice
class PushToTalkButton extends ConsumerStatefulWidget {
  const PushToTalkButton({super.key});

  @override
  ConsumerState<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends ConsumerState<PushToTalkButton> {
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

    final isProcessing = recordingState == RecordingState.processing;
    final isTyping = recordingState == RecordingState.typing;

    final screenWidth = MediaQuery.of(context).size.width;

    // Dimensions based on state
    double width;
    double height;
    if (isTyping) {
      width = screenWidth - 48;
      height = AppSpacing.ctaIdleHeight;
    } else if (isProcessing) {
      width = AppSpacing.ctaActiveWidth;
      height = AppSpacing.ctaActiveHeight;
    } else {
      // idle
      width = AppSpacing.ctaIdleWidth;
      height = AppSpacing.ctaIdleHeight;
    }

    // Colors
    final idleBg = AppColors.darkText;
    final idleText = AppColors.darkBg;
    final activeBg = DomainColors.workDark.primary;
    final activeText = DomainColors.workDark.textOnPrimary;
    final bgColor = isProcessing ? activeBg : idleBg;

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
        child: _buildContent(
          recordingState,
          idleText,
          activeText,
        ),
      ),
    );
  }

  Widget _buildContent(
    RecordingState state,
    Color idleText,
    Color activeText,
  ) {
    switch (state) {
      case RecordingState.idle:
      case RecordingState.listening:
        return _buildIdleContent(idleText);
      case RecordingState.processing:
        return _buildProcessingContent(activeText);
      case RecordingState.typing:
        return _buildTypingContent(idleText);
    }
  }

  Widget _buildIdleContent(Color textColor) {
    return GestureDetector(
      onTap: _activateKeyboard,
      onLongPress: _launchRamble,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_alt_outlined, size: 16, color: textColor),
            const SizedBox(width: 8),
            Text('Type or hold to talk',
                style: AppTypography.ctaLabelText(color: textColor)),
          ],
        ),
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

  void _activateKeyboard() {
    HapticService.light();
    ref.read(recordingStateProvider.notifier).state = RecordingState.typing;
  }

  void _launchRamble() {
    HapticService.medium();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => const RambleSheet(),
    );
  }

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
    _resetState();
  }

  Future<void> _processCommand(String text) async {
    ref.read(recordingStateProvider.notifier).state = RecordingState.processing;

    await processAndHandleAgentResponse(
      context: context,
      ref: ref,
      text: text,
    );

    _resetState();
  }

  void _resetState() {
    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
  }
}
