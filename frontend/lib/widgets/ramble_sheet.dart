import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/recording_provider.dart';
import '../services/haptic_service.dart';
import 'waveform_painter.dart';
import 'styled_snackbar.dart';

String _sentenceCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Ramble mode states
enum _RamblePhase { recording, processing, reviewing, submitting }

/// Full-screen bottom sheet for voice brain dump.
/// Records speech → extracts multiple tasks → user reviews → submits.
class RambleSheet extends ConsumerStatefulWidget {
  final String? prefilledCategory;

  const RambleSheet({super.key, this.prefilledCategory});

  @override
  ConsumerState<RambleSheet> createState() => _RambleSheetState();
}

class _RambleSheetState extends ConsumerState<RambleSheet> {
  _RamblePhase _phase = _RamblePhase.recording;
  List<BrainDumpTaskProposal> _proposals = [];
  late final Set<int> _selectedIndices;
  String _transcription = '';
  bool _canStopListening = false;
  bool _isStoppingListening = false;

  @override
  void initState() {
    super.initState();
    _selectedIndices = {};
    // Start recording immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRecording();
    });
  }

  @override
  void dispose() {
    // Ensure speech is stopped if sheet is dismissed
    try {
      final speechService = ref.read(speechServiceProvider);
      speechService.stopListening();
    } catch (_) {}
    // Reset recording state
    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
    ref.read(waveformDataProvider.notifier).state = [];
    ref.read(transcriptionTextProvider.notifier).state = '';
    super.dispose();
  }

  // ────────── Recording ──────────

  Future<void> _startRecording() async {
    _canStopListening = false;
    setState(() => _phase = _RamblePhase.recording);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _canStopListening = true;
    });

    try {
      final speechService = ref.read(speechServiceProvider);

      speechService.onResult = (text, isFinal) {
        if (mounted) {
          setState(() => _transcription = text);
          ref.read(transcriptionTextProvider.notifier).state = text;
        }
      };

      speechService.onSoundLevelChange = (level) {
        if (mounted) {
          final current = List<double>.from(ref.read(waveformDataProvider));
          current.add(level);
          if (current.length > 50) current.removeAt(0);
          ref.read(waveformDataProvider.notifier).state = current;
        }
      };

      speechService.onError = (error) {
        if (mounted) {
          setState(() => _phase = _RamblePhase.recording);
          showStyledSnackbar(context,
            message: 'Speech error: $error',
            style: SnackbarStyle.error,
          );
        }
      };

      await speechService.initialize();
      await speechService.startListening();
      ref.read(recordingStateProvider.notifier).state = RecordingState.listening;
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showStyledSnackbar(context,
          message: 'Failed to start listening: $e',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<void> _stopAndProcess() async {
    if (_isStoppingListening || !_canStopListening) return;
    _isStoppingListening = true;
    HapticService.light();

    try {
      final speechService = ref.read(speechServiceProvider);
      await speechService.stopListening();
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;

      final transcription = _transcription.trim();
      if (transcription.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          showStyledSnackbar(context,
            message: 'Nothing heard. Try again.',
            style: SnackbarStyle.info,
          );
        }
        return;
      }

      // Move to processing phase
      setState(() => _phase = _RamblePhase.processing);

      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.processBrainDump(
        transcription: transcription,
        userId: AppConstants.defaultUserId,
        category: widget.prefilledCategory,
      );

      if (!mounted) return;

      if (!response.success || response.tasks.isEmpty) {
        Navigator.pop(context);
        showStyledSnackbar(context,
          message: response.message ?? 'No tasks found. Try again.',
          style: SnackbarStyle.info,
        );
        return;
      }

      // Move to review phase — all tasks pre-selected
      setState(() {
        _proposals = response.tasks;
        _selectedIndices = Set<int>.from(
          List.generate(response.tasks.length, (i) => i),
        );
        _phase = _RamblePhase.reviewing;
      });
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showStyledSnackbar(context,
          message: 'Failed to process: $e',
          style: SnackbarStyle.error,
        );
      }
    } finally {
      _isStoppingListening = false;
    }
  }

  // ────────── Review actions ──────────

  void _toggleTask(int index) {
    HapticService.light();
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _removeTask(int index) {
    HapticService.light();
    setState(() {
      _proposals.removeAt(index);
      // Rebuild selected indices
      _selectedIndices = _selectedIndices
          .where((i) => i < _proposals.length)
          .map((i) => i >= index ? i : i)
          .toSet();
      // Re-select all remaining
      _selectedIndices = Set<int>.from(
        List.generate(_proposals.length, (i) => i),
      );
    });
  }

  Future<void> _submitTasks() async {
    if (_selectedIndices.isEmpty) return;
    HapticService.medium();
    setState(() => _phase = _RamblePhase.submitting);

    final selectedTasks = _selectedIndices
        .map((i) => _proposals[i])
        .toList();

    try {
      final apiService = ref.read(apiServiceProvider);
      final result = await apiService.submitBrainDump(
        userId: AppConstants.defaultUserId,
        tasks: selectedTasks,
      );

      await ref.read(taskStoreProvider.notifier).fetchAll();

      if (!mounted) return;
      Navigator.pop(context);

      showStyledSnackbar(context,
        message: result.message,
        style: SnackbarStyle.success,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _phase = _RamblePhase.reviewing);
        showStyledSnackbar(context,
          message: 'Failed to create tasks: $e',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  // ────────── Build ──────────

  @override
  Widget build(BuildContext context) {
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain = DomainColors.getDomain(
      widget.prefilledCategory ?? 'work', true, paletteMap,
    );

    return PopScope(
      canPop: _phase != _RamblePhase.reviewing || _proposals.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _proposals.isNotEmpty) {
          _showDiscardDialog(domain);
        }
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.darkBg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppSpacing.radiusLg),
            topRight: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDragHandle(),
            _buildHeader(domain),
            Flexible(child: _buildBody(domain)),
            _buildFooter(domain),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.darkText.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(DomainPalette domain) {
    final String title;
    final String subtitle;

    switch (_phase) {
      case _RamblePhase.recording:
        title = 'Listening...';
        subtitle = 'Say everything you need to get done.';
      case _RamblePhase.processing:
        title = 'Processing...';
        subtitle = 'Extracting tasks from your voice.';
      case _RamblePhase.reviewing:
        title = '${_proposals.length} tasks found';
        subtitle = 'Review and select which tasks to create.';
      case _RamblePhase.submitting:
        title = 'Creating tasks...';
        subtitle = 'Saving ${_selectedIndices.length} tasks.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: domain.primary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ramble',
            style: AppTypography.metadataText(
              color: domain.primary.withValues(alpha: 0.8),
            ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: AppTypography.metadataText(color: domain.primary)
                .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.5),
            ).copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(DomainPalette domain) {
    switch (_phase) {
      case _RamblePhase.recording:
        return _buildRecordingBody(domain);
      case _RamblePhase.processing:
      case _RamblePhase.submitting:
        return _buildLoadingBody(domain);
      case _RamblePhase.reviewing:
        return _buildReviewBody(domain);
    }
  }

  Widget _buildRecordingBody(DomainPalette domain) {
    final waveformData = ref.watch(waveformDataProvider);
    final transcription = ref.watch(transcriptionTextProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.xl),
          // Waveform
          CustomPaint(
            painter: WaveformPainter(
              amplitudes: waveformData,
              color: domain.primary,
            ),
            child: const SizedBox(width: double.infinity, height: 48),
          ),
          const SizedBox(height: AppSpacing.md),
          // Live transcription
          Text(
            transcription.isNotEmpty ? transcription : 'Start speaking...',
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(
                alpha: transcription.isNotEmpty ? 0.8 : 0.4,
              ),
            ).copyWith(fontSize: 15),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xl),
          // Stop button
          GestureDetector(
            onTap: _canStopListening ? _stopAndProcess : null,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: domain.primary,
                shape: BoxShape.circle,
                boxShadow: domain.glow != null
                    ? [BoxShadow(color: domain.glow!, blurRadius: 16, spreadRadius: 4)]
                    : null,
              ),
              child: Icon(
                Icons.stop_rounded,
                size: 32,
                color: domain.textOnPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap to stop',
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.4),
            ).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBody(DomainPalette domain) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: domain.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildReviewBody(DomainPalette domain) {
    final paletteMap = ref.watch(domainPalettesProvider);

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      itemCount: _proposals.length,
      itemBuilder: (context, index) {
        final proposal = _proposals[index];
        final isSelected = _selectedIndices.contains(index);
        final taskDomain = DomainColors.getDomain(
          proposal.category, true, paletteMap,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GestureDetector(
            onTap: () => _toggleTask(index),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? taskDomain.surface
                    : AppColors.darkBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: isSelected
                      ? taskDomain.primary.withValues(alpha: 0.4)
                      : AppColors.darkText.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Checkbox
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? taskDomain.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? taskDomain.primary
                            : AppColors.darkText.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check, size: 14,
                            color: taskDomain.textOnPrimary)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Task content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sentenceCase(proposal.content),
                          style: AppTypography.metadataText(
                            color: AppColors.darkText,
                          ).copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            decoration: isSelected
                                ? null
                                : TextDecoration.lineThrough,
                            decorationColor: AppColors.darkText.withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Metadata chips
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _buildChip(
                              _sentenceCase(proposal.category),
                              taskDomain.primary,
                            ),
                            if (proposal.dueDate != null)
                              _buildChip(
                                _formatDate(proposal.dueDate!),
                                AppColors.dueSoon,
                              ),
                            if (proposal.priority != null)
                              _buildChip(
                                _sentenceCase(proposal.priority!),
                                _priorityColor(proposal.priority!),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Delete button
                  GestureDetector(
                    onTap: () => _removeTask(index),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.darkText.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.metadataText(color: color)
            .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildFooter(DomainPalette domain) {
    if (_phase == _RamblePhase.recording ||
        _phase == _RamblePhase.processing ||
        _phase == _RamblePhase.submitting) {
      return const SizedBox(height: AppSpacing.md);
    }

    final selectedCount = _selectedIndices.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      child: Row(
        children: [
          // Record more button
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticService.light();
                _transcription = '';
                ref.read(transcriptionTextProvider.notifier).state = '';
                ref.read(waveformDataProvider.notifier).state = [];
                _startRecording();
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: domain.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic_none_rounded, size: 18, color: domain.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Add more',
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Submit button
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: selectedCount > 0 ? _submitTasks : null,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: selectedCount > 0
                      ? domain.primary
                      : domain.primary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  boxShadow: selectedCount > 0 && domain.glow != null
                      ? [BoxShadow(
                          color: domain.glow!,
                          blurRadius: 12,
                          spreadRadius: 2,
                        )]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Create $selectedCount Task${selectedCount == 1 ? '' : 's'}',
                    style: AppTypography.metadataText(
                      color: selectedCount > 0
                          ? domain.textOnPrimary
                          : domain.textOnPrimary.withValues(alpha: 0.5),
                    ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────── Helpers ──────────

  void _showDiscardDialog(DomainPalette domain) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        title: Text(
          'Unsaved tasks',
          style: AppTypography.metadataText(color: AppColors.darkText)
              .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'You have ${_proposals.length} tasks that haven\'t been saved yet.',
          style: AppTypography.metadataText(
            color: AppColors.darkText.withValues(alpha: 0.7),
          ).copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);  // Close dialog
              Navigator.pop(context);  // Close sheet
            },
            child: Text(
              'Discard',
              style: TextStyle(color: AppColors.deleteAction),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Keep editing',
              style: TextStyle(color: domain.primary),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    }
    return '${date.month}/${date.day}';
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return AppColors.overdue;
      case 'medium':
        return AppColors.dueSoon;
      case 'low':
        return AppColors.completed;
      default:
        return AppColors.darkText;
    }
  }
}
