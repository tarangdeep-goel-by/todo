import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/api_response.dart';
import '../models/task.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/recording_provider.dart';
import '../services/haptic_service.dart';
import '../services/ramble_websocket_service.dart';
import '../widgets/waveform_painter.dart';
import '../widgets/styled_snackbar.dart';
import '../widgets/task_parent_picker.dart';
import '../utils/string_extensions.dart';
import '../services/app_logger.dart';
import '../services/tracker/tracker.dart';
import '../services/tracker/tracker_keys.dart';

/// Ramble mode phases
enum _RamblePhase { recording, editing, processing, reviewing }

/// Full-screen route for voice brain dump.
/// Streams audio -> Gemini transcribes -> user edits -> brain dump extracts proposals -> user reviews -> submit.
class RambleScreen extends ConsumerStatefulWidget {
  final String? prefilledCategory;
  final String? prefilledParentId;
  final String? prefilledParentTitle;

  /// When provided, skip recording/editing and jump straight to proposal review.
  /// Used by keyboard input flow: text → brain dump API → proposals → review here.
  final List<BrainDumpTaskProposal>? initialProposals;
  final String? initialTranscript;

  const RambleScreen({
    super.key,
    this.prefilledCategory,
    this.prefilledParentId,
    this.prefilledParentTitle,
    this.initialProposals,
    this.initialTranscript,
  });

  @override
  ConsumerState<RambleScreen> createState() => _RambleScreenState();
}

class _RambleScreenState extends ConsumerState<RambleScreen> {
  final _logger = AppLogger.instance;
  _RamblePhase _phase = _RamblePhase.recording;
  bool _canStopListening = false;
  bool _isStoppingListening = false;
  bool _isPaused = false;

  final _transcriptController = TextEditingController();
  final _transcriptFocusNode = FocusNode();

  // Streaming subscriptions
  StreamSubscription<String>? _transcriptionSub;
  StreamSubscription<String>? _finalTranscriptSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<List<int>>? _audioStreamSub;
  StreamSubscription<int>? _timerSub;
  StreamSubscription<RambleConnectionState>? _connectionSub;
  int? _timeRemaining; // null = no timer received yet
  RambleConnectionState _connectionState = RambleConnectionState.disconnected;

  // Reviewing state
  List<BrainDumpTaskProposal> _proposals = [];
  List<BrainDumpTaskProposal> _existingProposals = [];
  final Set<String> _deselectedIds = {};
  final Set<String> _expandedAlternates = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    Tracker.instance.screenView(screen: 'ramble');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transcriptionTextProvider.notifier).state = '';
      ref.read(waveformDataProvider.notifier).state = [];

      // Keyboard flow: skip recording, jump to review
      if (widget.initialProposals != null) {
        setState(() {
          _proposals = widget.initialProposals!;
          _existingProposals = _proposals.where((p) => p.action != 'add').toList();
          _transcriptController.text = widget.initialTranscript ?? '';
          _phase = _RamblePhase.reviewing;
        });
        return;
      }

      _startRecording();
    });
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _transcriptController.dispose();
    _transcriptFocusNode.dispose();
    super.dispose();
  }

  void _resetProviders() {
    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
    ref.read(waveformDataProvider.notifier).state = [];
    ref.read(transcriptionTextProvider.notifier).state = '';
  }

  void _cancelSubscriptions() {
    _transcriptionSub?.cancel();
    _finalTranscriptSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _audioStreamSub?.cancel();
    _timerSub?.cancel();
    _connectionSub?.cancel();
    _transcriptionSub = null;
    _finalTranscriptSub = null;
    _statusSub = null;
    _errorSub = null;
    _audioStreamSub = null;
    _timerSub = null;
    _connectionSub = null;
  }

  // ────────── Close handling ──────────

  Future<bool> _onWillPop() async {
    if (_phase == _RamblePhase.reviewing && _proposals.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.darkBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          title: Text(
            'You have unsaved tasks',
            style: AppTypography.metadataText(color: AppColors.darkText)
                .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: Text(
            '${_proposals.length - _deselectedIds.length} task(s) will be lost.',
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.6),
            ).copyWith(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Keep editing',
                style: AppTypography.metadataText(
                  color: AppColors.darkText.withValues(alpha: 0.7),
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Discard',
                style: AppTypography.metadataText(
                  color: AppColors.deleteAction,
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      if (discard != true) return false;
    }
    _resetProviders();
    return true;
  }

  void _close() async {
    if (await _onWillPop()) {
      if (mounted) Navigator.pop(context);
    }
  }

  // ────────── Recording (WebSocket streaming) ──────────

  Future<void> _startRecording() async {
    _logger.info('ramble.start', logger: 'RambleScreen');
    _canStopListening = false;
    setState(() => _phase = _RamblePhase.recording);

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _canStopListening = true;
    });

    try {
      final audioService = ref.read(audioServiceProvider);
      final rambleWs = ref.read(rambleWebSocketProvider);

      _logger.debug('ws.connect', logger: 'RambleScreen');
      await rambleWs.connect();

      _transcriptionSub = rambleWs.transcriptionStream.listen((text) {
        if (mounted && _phase == _RamblePhase.recording) {
          ref.read(transcriptionTextProvider.notifier).state = text;
        }
      });

      _finalTranscriptSub = rambleWs.finalTranscriptStream.listen((text) {
        if (mounted) {
          _logger.info('ramble.transcript', logger: 'RambleScreen', data: {'length': text.length});
          _transcriptController.text = text;
        }
      });

      _errorSub = rambleWs.errorStream.listen((error) {
        _logger.error('ws.error', logger: 'RambleScreen', data: {'error': error});
        if (mounted && _phase == _RamblePhase.recording) {
          showStyledSnackbar(context,
            message: 'Voice connection interrupted. Try again.',
            style: SnackbarStyle.error,
          );
        }
      });

      _statusSub = rambleWs.statusStream.listen((status) {
        _logger.debug('ramble.status', logger: 'RambleScreen', data: {'status': status});
        if (status == 'timeout' && mounted && _phase == _RamblePhase.recording) {
          // Session timed out — auto-transition to editing
          _stopAndEdit();
        }
      });

      _timerSub = rambleWs.timeRemainingStream.listen((seconds) {
        if (mounted) {
          setState(() {
            _timeRemaining = seconds;
          });
        }
      });

      _connectionSub = rambleWs.connectionStateStream.listen((state) {
        if (mounted) {
          setState(() => _connectionState = state);
          // When disconnected during recording, stay in recording phase
          // so the user can tap the reconnect button (or stop to edit).
          if (state == RambleConnectionState.disconnected &&
              _phase == _RamblePhase.recording) {
            showStyledSnackbar(context,
              message: 'Connection lost — tap reconnect or stop to edit.',
              style: SnackbarStyle.info,
            );
          }
        }
      });

      _logger.debug('ramble.start', logger: 'RambleScreen', data: {'step': 'audio_stream'});
      final audioStream = await audioService.startStream();

      _audioStreamSub = audioStream.listen((pcmChunk) {
        final base64Data = base64Encode(Uint8List.fromList(pcmChunk));
        rambleWs.sendAudioChunk(base64Data);
      });

      ref.read(recordingStateProvider.notifier).state = RecordingState.listening;
      _logger.info('ramble.start', logger: 'RambleScreen', data: {'success': true});
    } catch (e) {
      _logger.error('ramble.start', logger: 'RambleScreen', data: {'error': e.toString()});
      if (mounted) {
        _resetProviders();
        Navigator.pop(context);
        showStyledSnackbar(context,
          message: 'Couldn\'t start recording. Check your microphone.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<void> _stopAndEdit() async {
    _logger.info('ramble.stop', logger: 'RambleScreen');
    if (_isStoppingListening || !_canStopListening) return;
    if (_phase != _RamblePhase.recording) return;
    _isStoppingListening = true;
    HapticService.light();

    try {
      if (!_isPaused) {
        await _audioStreamSub?.cancel();
        _audioStreamSub = null;

        final audioService = ref.read(audioServiceProvider);
        await audioService.stopStream();
      }
      _isPaused = false;
      _logger.debug('ramble.stop', logger: 'RambleScreen', data: {'step': 'audio_stopped'});

      final rambleWs = ref.read(rambleWebSocketProvider);
      final finalTranscript = await rambleWs.stop();
      _logger.info('ramble.stop', logger: 'RambleScreen', data: {'transcript_length': finalTranscript?.length ?? 0});

      _cancelSubscriptions();
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;

      final transcript = (finalTranscript ?? _transcriptController.text).trim();
      if (transcript.isEmpty) {
        if (mounted) {
          _resetProviders();
          Navigator.pop(context);
          showStyledSnackbar(context,
            message: 'Didn\'t catch anything. Hold and speak clearly.',
            style: SnackbarStyle.info,
          );
        }
        return;
      }

      _logger.info('ramble.stop', logger: 'RambleScreen', data: {'phase': 'editing', 'length': transcript.length});
      setState(() => _phase = _RamblePhase.editing);
    } catch (e) {
      _logger.error('ramble.stop', logger: 'RambleScreen', data: {'error': e.toString()});
      if (mounted) {
        _resetProviders();
        Navigator.pop(context);
        showStyledSnackbar(context,
          message: 'Something went wrong. Try again.',
          style: SnackbarStyle.error,
        );
      }
    } finally {
      _isStoppingListening = false;
    }
  }

  // ────────── Pause / Resume ──────────

  Future<void> _pauseRecording() async {
    if (_isPaused || _phase != _RamblePhase.recording) return;
    _logger.debug('ramble.pause', logger: 'RambleScreen');
    HapticService.light();

    // Stop sending audio but keep WebSocket open
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;

    final audioService = ref.read(audioServiceProvider);
    await audioService.stopStream();

    setState(() => _isPaused = true);
    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
    _logger.debug('ramble.pause', logger: 'RambleScreen', data: {'success': true});
  }

  Future<void> _resumeRecording() async {
    if (!_isPaused || _phase != _RamblePhase.recording) return;
    _logger.debug('ramble.resume', logger: 'RambleScreen');
    HapticService.light();

    try {
      final audioService = ref.read(audioServiceProvider);
      final rambleWs = ref.read(rambleWebSocketProvider);

      final audioStream = await audioService.startStream();
      _audioStreamSub = audioStream.listen((pcmChunk) {
        final base64Data = base64Encode(Uint8List.fromList(pcmChunk));
        rambleWs.sendAudioChunk(base64Data);
      });

      setState(() => _isPaused = false);
      ref.read(recordingStateProvider.notifier).state = RecordingState.listening;
      _logger.debug('ramble.resume', logger: 'RambleScreen', data: {'success': true});
    } catch (e) {
      _logger.error('ramble.resume', logger: 'RambleScreen', data: {'error': e.toString()});
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Couldn\'t resume recording. Try again.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  void _togglePause() {
    if (_isPaused) {
      _resumeRecording();
    } else {
      _pauseRecording();
    }
  }

  void _handleReconnect() {
    final rambleWs = ref.read(rambleWebSocketProvider);
    rambleWs.manualReconnect();
    HapticService.light();
  }

  // ────────── Processing (Brain Dump) ──────────

  Future<void> _processBrainDump() async {
    final text = _transcriptController.text.trim();
    if (text.isEmpty) return;

    HapticService.medium();
    _transcriptFocusNode.unfocus();
    setState(() => _phase = _RamblePhase.processing);

    try {
      final apiService = ref.read(apiServiceProvider);
      _logger.info('braindump.process', logger: 'RambleScreen', data: {'transcript_length': text.length});
      final response = await apiService.processBrainDump(
        transcription: text,
        category: widget.prefilledCategory,
        parentId: widget.prefilledParentId,
      );

      _logger.info('braindump.process', logger: 'RambleScreen', data: {'proposal_count': response.tasks.length});
      for (final t in response.tasks) {
        _logger.debug('braindump.action', logger: 'RambleScreen', data: {'action': t.action, 'category': t.category, 'matched_id': t.matchedTaskId});
      }

      if (mounted) {
        var tasks = response.tasks;

        // Fallback: if Gemini returned nothing, create a single ADD proposal
        // from the raw transcript so the user can still add what they said.
        if (tasks.isEmpty) {
          tasks = [
            BrainDumpTaskProposal(
              id: 'fallback-${DateTime.now().millisecondsSinceEpoch}',
              action: 'add',
              content: text,
              category: widget.prefilledCategory ?? 'home',
              parentId: widget.prefilledParentId,
            ),
          ];
        }

        setState(() {
          if (_existingProposals.isNotEmpty) {
            _proposals = [..._existingProposals, ...tasks];
            _existingProposals = [];
          } else {
            _proposals = tasks;
          }
          _deselectedIds.clear();
          _phase = _RamblePhase.reviewing;
        });
        Tracker.instance.impression(component: 'proposal_cards', screen: 'ramble', itemCount: _proposals.length);
      }
    } catch (e) {
      _logger.error('braindump.process', logger: 'RambleScreen', data: {'error': e.toString()});
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Couldn\'t process your input. Try again.',
          style: SnackbarStyle.error,
        );
        setState(() => _phase = _RamblePhase.editing);
      }
    }
  }

  // ────────── Reviewing ──────────

  Future<void> _submitProposals() async {
    final selected = _proposals
        .where((p) => !_deselectedIds.contains(p.id))
        .toList();
    if (selected.isEmpty) return;

    _logger.info('braindump.submit', logger: 'RambleScreen', data: {'task_count': selected.length});
    for (final t in selected) {
      _logger.debug('braindump.action', logger: 'RambleScreen', data: {'action': t.action, 'matched_id': t.matchedTaskId});
    }

    HapticService.medium();
    setState(() => _isSubmitting = true);

    try {
      final apiService = ref.read(apiServiceProvider);
      _logger.debug('braindump.submit', logger: 'RambleScreen', data: {'step': 'api_call'});
      final stopwatch = Stopwatch()..start();
      final response = await apiService.submitBrainDump(
        tasks: selected,
      );
      _logger.info('braindump.submit', logger: 'RambleScreen', data: {'step': 'api_done', 'duration_ms': stopwatch.elapsedMilliseconds});

      _logger.debug('braindump.submit', logger: 'RambleScreen', data: {'step': 'fetch_all'});
      await ref.read(taskStoreProvider.notifier).fetchAll();
      _logger.info('braindump.submit', logger: 'RambleScreen', data: {'step': 'fetch_done', 'duration_ms': stopwatch.elapsedMilliseconds});

      if (mounted) {
        Tracker.instance.outcome(type: 'tasks_created_batch', count: selected.length, method: 'voice');
        _resetProviders();
        Navigator.pop(context, (
          success: true,
          message: response.message,
        ));
      }
    } catch (e, stack) {
      _logger.error('braindump.submit', logger: 'RambleScreen', data: {'error': e.toString(), 'stack': stack.toString()});
      if (mounted) {
        setState(() => _isSubmitting = false);
        showStyledSnackbar(context,
          message: 'Couldn\'t save tasks. Check your connection.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  /// Resolve the L1 (root) ancestor task name for a proposal.
  /// For ADD: walks up from parentId. For COMPLETE/EDIT/DELETE/MOVE: walks up
  /// from the matched task itself. Returns null if no parent found.
  String? _resolveL1ParentName(BrainDumpTaskProposal proposal) {
    final tasks = ref.read(taskStoreProvider).tasks;
    // Determine starting task ID based on action
    String? startId;
    if (proposal.action == 'add') {
      startId = proposal.parentId;
    } else {
      // For complete/edit/delete/move — start from the matched task
      startId = proposal.matchedTaskId;
    }
    if (startId == null) return null;
    // Walk up to L1 root
    String? currentId = startId;
    String? rootName;
    final visited = <String>{};
    while (currentId != null && !visited.contains(currentId)) {
      visited.add(currentId);
      final task = tasks[currentId];
      if (task == null) break;
      rootName = task.sentenceTitle;
      currentId = task.parentId;
    }
    return rootName;
  }

  void _toggleProposal(String id) {
    setState(() {
      if (_deselectedIds.contains(id)) {
        _deselectedIds.remove(id);
      } else {
        _deselectedIds.add(id);
      }
    });
  }

  void _editProposal(BrainDumpTaskProposal proposal) async {
    HapticService.medium();

    // If alternates exist, show disambiguation picker first
    if (proposal.alternateMatches != null &&
        proposal.alternateMatches!.isNotEmpty) {
      final picked = await _showDisambiguationPicker(proposal);
      if (picked != null) {
        setState(() {
          final idx = _proposals.indexWhere((p) => p.id == proposal.id);
          if (idx != -1) _proposals[idx] = picked;
        });
        return;
      }
      // User dismissed picker — fall through to normal edit sheet
    }

    if (!mounted) return;
    final paletteMap = ref.read(domainPalettesProvider);
    final edited = await showModalBottomSheet<BrainDumpTaskProposal>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProposalEditSheet(
        proposal: proposal,
        paletteMap: paletteMap,
      ),
    );
    if (edited != null) {
      setState(() {
        final idx = _proposals.indexWhere((p) => p.id == edited.id);
        if (idx != -1) _proposals[idx] = edited;
      });
    }
  }

  Future<BrainDumpTaskProposal?> _showDisambiguationPicker(
    BrainDumpTaskProposal proposal,
  ) async {
    // Build list: current match + alternatives
    final currentMatch = {
      'id': proposal.matchedTaskId ?? '',
      'title': proposal.content,
      'category': proposal.category,
    };
    final allMatches = [currentMatch, ...proposal.alternateMatches!];

    final paletteMap = ref.read(domainPalettesProvider);

    return showModalBottomSheet<BrainDumpTaskProposal>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm,
                ),
                child: Text(
                  proposal.action == 'edit' &&
                          proposal.changes != null &&
                          proposal.changes!.containsKey('parent_id')
                      ? 'Which task to move?'
                      : proposal.action == 'edit'
                          ? 'Which task to edit?'
                          : proposal.action == 'complete'
                              ? 'Which task to complete?'
                              : proposal.action == 'delete'
                                  ? 'Which task to delete?'
                                  : 'Which task did you mean?',
                  style: AppTypography.metadataText(color: AppColors.darkText)
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              ...allMatches.asMap().entries.map((entry) {
                final idx = entry.key;
                final match = entry.value;
                final matchDomain = DomainColors.getDomain(
                  match['category'] ?? 'career', true, paletteMap,
                );
                final isCurrent = idx == 0;
                return ListTile(
                  leading: Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: matchDomain.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  title: Text(
                    match['title'] ?? '',
                    style: AppTypography.metadataText(
                      color: isCurrent
                          ? matchDomain.primary
                          : AppColors.darkText,
                    ).copyWith(
                      fontSize: 14,
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Builder(builder: (_) {
                    // Resolve L1 parent name from matched task ID
                    final taskId = match['id'] ?? '';
                    final tasks = ref.read(taskStoreProvider).tasks;
                    String? l1Name;
                    String? cid = taskId;
                    final visited = <String>{};
                    while (cid != null && cid.isNotEmpty && !visited.contains(cid)) {
                      visited.add(cid);
                      final t = tasks[cid];
                      if (t == null) break;
                      l1Name = t.sentenceTitle;
                      cid = t.parentId;
                    }
                    final label = l1Name ??
                        (match['category'] ?? '').toString().toUpperCase();
                    return Text(
                      label + (isCurrent ? '  (current)' : ''),
                      style: AppTypography.metadataText(
                        color: AppColors.darkText.withValues(alpha: 0.5),
                      ).copyWith(fontSize: 11),
                    );
                  }),
                  onTap: () {
                    final updated = BrainDumpTaskProposal(
                      id: proposal.id,
                      action: proposal.action,
                      content: match['title'] ?? proposal.content,
                      description: proposal.description,
                      category: match['category'] ?? proposal.category,
                      dueDate: proposal.dueDate,
                      priority: proposal.priority,
                      parentId: proposal.parentId,
                      labels: proposal.labels,
                      changes: proposal.changes,
                      matchedTaskId: match['id'],
                      confidence: proposal.confidence,
                      tags: proposal.tags,
                      estimatedHours: proposal.estimatedHours,
                      alternateMatches: null, // Clear after selection
                    );
                    Navigator.pop(ctx, updated);
                  },
                );
              }),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        );
      },
    );
  }

  void _recordMore() {
    HapticService.light();
    // Save current proposals so they can be merged with new ones
    _existingProposals = [..._proposals];
    _transcriptController.clear();
    _deselectedIds.clear();
    _isPaused = false;
    _timeRemaining = null;
    ref.read(transcriptionTextProvider.notifier).state = '';
    ref.read(waveformDataProvider.notifier).state = [];
    setState(() => _phase = _RamblePhase.recording);
    _startRecording();
  }

  void _goBackToEditing() {
    HapticService.light();
    // Transcript is preserved in _transcriptController — user can edit and re-extract
    setState(() => _phase = _RamblePhase.editing);
  }

  void _reRecord() {
    HapticService.light();
    _transcriptController.clear();
    _proposals = [];
    _existingProposals = [];
    _deselectedIds.clear();
    _isPaused = false;
    _timeRemaining = null;
    ref.read(transcriptionTextProvider.notifier).state = '';
    ref.read(waveformDataProvider.notifier).state = [];
    _startRecording();
  }

  // ────────── Build ──────────

  @override
  Widget build(BuildContext context) {
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain = DomainColors.getDomain(
      widget.prefilledCategory ?? 'career', true, paletteMap,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onWillPop()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(domain),
              _buildHeader(domain),
              Expanded(child: _buildBody(domain)),
              _buildFooter(domain),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(DomainPalette domain) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm, AppSpacing.sm, AppSpacing.lg, 0,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _close,
            icon: Icon(
              Icons.close_rounded,
              color: AppColors.darkText.withValues(alpha: 0.6),
              size: 24,
            ),
          ),
          Text(
            'Ramble',
            style: AppTypography.metadataText(
              color: domain.primary.withValues(alpha: 0.8),
            ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (_phase == _RamblePhase.recording) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (_connectionState) {
                  RambleConnectionState.connected => Colors.green,
                  RambleConnectionState.reconnecting => Colors.orange,
                  _ => AppColors.darkText.withValues(alpha: 0.3),
                },
              ),
            ),
            if (_connectionState == RambleConnectionState.reconnecting)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  'Reconnecting...',
                  style: AppTypography.metadataText(
                    color: Colors.orange.withValues(alpha: 0.8),
                  ).copyWith(fontSize: 11),
                ),
              ),
            if (_connectionState == RambleConnectionState.disconnected)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  'Disconnected',
                  style: AppTypography.metadataText(
                    color: AppColors.darkText.withValues(alpha: 0.5),
                  ).copyWith(fontSize: 11),
                ),
              ),
          ],
          const Spacer(),
          if (_timeRemaining != null && _phase == _RamblePhase.recording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _timeRemaining! <= 60
                    ? AppColors.deleteAction.withValues(alpha: 0.15)
                    : AppColors.darkText.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                '${(_timeRemaining! ~/ 60).toString().padLeft(1, '0')}:${(_timeRemaining! % 60).toString().padLeft(2, '0')}',
                style: AppTypography.metadataText(
                  color: _timeRemaining! <= 60
                      ? AppColors.deleteAction
                      : AppColors.darkText.withValues(alpha: 0.5),
                ).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(DomainPalette domain) {
    final String title;
    final String subtitle;

    switch (_phase) {
      case _RamblePhase.recording:
        title = _isPaused ? 'Paused' : 'Listening...';
        subtitle = _isPaused
            ? 'Tap resume to continue speaking.'
            : 'Say everything you need to get done.';
      case _RamblePhase.editing:
        title = 'Edit transcript';
        subtitle = 'Review and correct before sending.';
      case _RamblePhase.processing:
        title = 'Processing...';
        subtitle = 'Extracting tasks from your ramble.';
      case _RamblePhase.reviewing:
        title = 'Review tasks';
        subtitle = 'Tap to edit, long-press to toggle.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm,
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
          if (widget.prefilledParentTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              'Adding subtasks to: ${widget.prefilledParentTitle}',
              style: AppTypography.metadataText(
                color: domain.primary.withValues(alpha: 0.6),
              ).copyWith(fontSize: 12, fontStyle: FontStyle.italic),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(DomainPalette domain) {
    switch (_phase) {
      case _RamblePhase.recording:
        return _buildRecordingBody(domain);
      case _RamblePhase.editing:
        return _buildEditingBody(domain);
      case _RamblePhase.processing:
        return _buildLoadingBody(domain);
      case _RamblePhase.reviewing:
        return _buildReviewingBody(domain);
    }
  }

  Widget _buildRecordingBody(DomainPalette domain) {
    final transcription = ref.watch(transcriptionTextProvider);
    final audioService = ref.read(audioServiceProvider);

    return Column(
      children: [
        // Waveform strip at top
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm,
          ),
          child: AnimatedWaveform(
            amplitudeSource: () => audioService.waveformData,
            color: domain.primary,
            height: 48,
          ),
        ),
        // Scrollable transcription area fills remaining space
        Expanded(
          child: SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                transcription.isNotEmpty ? transcription : 'Start speaking...',
                style: AppTypography.metadataText(
                  color: AppColors.darkText.withValues(
                    alpha: transcription.isNotEmpty ? 0.8 : 0.4,
                  ),
                ).copyWith(fontSize: 16, height: 1.5),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditingBody(DomainPalette domain) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: TextField(
        controller: _transcriptController,
        focusNode: _transcriptFocusNode,
        maxLines: null,
        minLines: 4,
        style: AppTypography.metadataText(color: AppColors.darkText)
            .copyWith(fontSize: 15, height: 1.5),
        decoration: InputDecoration(
          hintText: 'Your transcript will appear here...',
          hintStyle: AppTypography.metadataText(
            color: AppColors.darkText.withValues(alpha: 0.3),
          ).copyWith(fontSize: 15),
          filled: true,
          fillColor: AppColors.darkText.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            borderSide: BorderSide(
              color: domain.primary.withValues(alpha: 0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            borderSide: BorderSide(
              color: domain.primary.withValues(alpha: 0.2),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            borderSide: BorderSide(
              color: domain.primary.withValues(alpha: 0.6),
            ),
          ),
          contentPadding: const EdgeInsets.all(AppSpacing.md),
        ),
      ),
    );
  }

  Widget _buildLoadingBody(DomainPalette domain) {
    return Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: domain.primary,
        ),
      ),
    );
  }

  Widget _buildReviewingBody(DomainPalette domain) {
    if (_proposals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_off_rounded,
              size: 48,
              color: AppColors.darkText.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No tasks detected',
              style: AppTypography.metadataText(
                color: AppColors.darkText.withValues(alpha: 0.6),
              ).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Try re-recording with more detail',
              style: AppTypography.metadataText(
                color: AppColors.tertiaryText,
              ).copyWith(fontSize: 13),
            ),
          ],
        ),
      );
    }

    final paletteMap = ref.watch(domainPalettesProvider);

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _proposals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final proposal = _proposals[index];
        final isSelected = !_deselectedIds.contains(proposal.id);
        final cardDomain = DomainColors.getDomain(
          proposal.category, true, paletteMap,
        );
        return _buildProposalCard(proposal, isSelected, cardDomain);
      },
    );
  }

  Widget _buildProposalCard(
    BrainDumpTaskProposal proposal,
    bool isSelected,
    DomainPalette domain,
  ) {
    // Use before→after layout for edit actions with changes
    final isEditAction = proposal.action == 'edit' &&
        proposal.changes != null &&
        proposal.changes!.isNotEmpty;

    if (isEditAction) {
      return _buildEditProposalCard(proposal, isSelected, domain);
    }
    return _buildSimpleProposalCard(proposal, isSelected, domain);
  }

  /// Before → After card for edit/move proposals
  Widget _buildEditProposalCard(
    BrainDumpTaskProposal proposal,
    bool isSelected,
    DomainPalette domain,
  ) {
    final tasks = ref.read(taskStoreProvider).tasks;
    final matchedTask = proposal.matchedTaskId != null
        ? tasks[proposal.matchedTaskId]
        : null;
    final changes = proposal.changes!;
    final paletteMap = ref.read(domainPalettesProvider);

    // Resolve "before" parent name
    String? beforeParentName;
    if (matchedTask?.parentId != null) {
      beforeParentName = tasks[matchedTask!.parentId]?.title;
    }

    // Resolve "after" parent name for reparent
    String? afterParentName;
    if (changes.containsKey('parent_id')) {
      final newParentId = changes['parent_id'] as String?;
      if (newParentId == null) {
        afterParentName = 'Top level';
      } else {
        afterParentName = tasks[newParentId]?.title ?? 'Unknown';
      }
    }

    // Determine after category domain for coloring
    final afterCategory = changes['category'] as String? ?? proposal.category;
    final afterDomain = DomainColors.getDomain(afterCategory, true, paletteMap);

    return GestureDetector(
      onTap: () => _editProposal(proposal),
      onLongPress: () => _toggleProposal(proposal.id),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isSelected ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: domain.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: domain.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: action label + checkbox
              Row(
                children: [
                  _buildChip(
                    _actionLabel(proposal.action),
                    _actionColor(proposal.action, domain),
                  ),
                  if (proposal.confidence != null) ...[
                    const SizedBox(width: 6),
                    _buildChip(
                      '${(proposal.confidence! * 100).round()}%',
                      _confidenceColor(proposal.confidence!),
                    ),
                  ],
                  if (proposal.alternateMatches != null &&
                      proposal.alternateMatches!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildChip(
                      '\u26A0 ${proposal.alternateMatches!.length + 1} matches',
                      AppColors.dueSoon,
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _toggleProposal(proposal.id),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? domain.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: domain.primary.withValues(
                              alpha: isSelected ? 1.0 : 0.4,
                            ),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: domain.textOnPrimary,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Before → After layout (vertical)
              _buildBeforeAfterMini(
                label: 'BEFORE',
                title: matchedTask?.title ?? proposal.content,
                category: matchedTask?.category ?? proposal.category,
                priority: matchedTask?.priority,
                parentName: beforeParentName,
                dueDate: matchedTask?.dueDate,
                domain: domain,
                dimmed: true,
              ),
              // Arrow
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 18,
                    color: domain.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
              // AFTER mini-card (highlight changes)
              _buildAfterMini(
                beforeTask: matchedTask,
                changes: changes,
                proposal: proposal,
                afterParentName: afterParentName,
                domain: afterDomain,
              ),
              if (proposal.alternateMatches != null &&
                  proposal.alternateMatches!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildAlternateMatchesSection(proposal, domain),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Mini-card showing task state (used for "before" side)
  Widget _buildBeforeAfterMini({
    required String label,
    required String title,
    required String category,
    String? priority,
    String? parentName,
    DateTime? dueDate,
    required DomainPalette domain,
    bool dimmed = false,
  }) {
    final alpha = dimmed ? 0.5 : 1.0;
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.cardInset,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: domain.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label + context line
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.darkText.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 6),
            // Parent context (prominent for moves)
            if (parentName != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 12,
                    color: AppColors.darkText.withValues(alpha: 0.3 * alpha),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'in $parentName',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkText.withValues(alpha: 0.4 * alpha),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(
              title,
              style: AppTypography.metadataText(
                color: domain.primary.withValues(alpha: alpha),
              ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                _buildMiniChip(
                  category[0].toUpperCase() + category.substring(1),
                  domain.primary.withValues(alpha: alpha),
                ),
                if (priority != null && priority != 'none')
                  _buildMiniChip(
                    priority[0].toUpperCase() + priority.substring(1),
                    _priorityColor(priority).withValues(alpha: alpha),
                  ),
                if (dueDate != null)
                  _buildMiniChip(
                    DateFormat('MMM d').format(dueDate),
                    domain.primary.withValues(alpha: 0.6 * alpha),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "After" mini-card — shows changed state with highlights
  Widget _buildAfterMini({
    required Task? beforeTask,
    required Map<String, dynamic> changes,
    required BrainDumpTaskProposal proposal,
    String? afterParentName,
    required DomainPalette domain,
  }) {
    // Compute the "after" state: overlay changes on before
    final afterTitle = changes['title'] as String? ??
        beforeTask?.title ?? proposal.content;
    final afterCategory = changes['category'] as String? ??
        beforeTask?.category ?? proposal.category;
    final afterPriority = changes['priority'] as String? ??
        beforeTask?.priority;
    final afterDueDate = changes.containsKey('due_date')
        ? (changes['due_date'] != null
            ? DateTime.tryParse(changes['due_date'] as String)
            : null)
        : beforeTask?.dueDate;

    // Track which fields changed for highlighting
    final titleChanged = changes.containsKey('title');
    final categoryChanged = changes.containsKey('category');
    final priorityChanged = changes.containsKey('priority');
    final dueDateChanged = changes.containsKey('due_date');
    final parentChanged = changes.containsKey('parent_id');

    // For non-move edits, resolve the unchanged parent for context
    String? unchangedParentName;
    if (!parentChanged && beforeTask?.parentId != null) {
      final tasks = ref.read(taskStoreProvider).tasks;
      unchangedParentName = tasks[beforeTask!.parentId]?.title;
    }

    // Show parent context: either the new parent (highlighted) or the unchanged parent
    final showParentName = parentChanged ? afterParentName : unchangedParentName;

    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.cardInset,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: domain.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AFTER',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: domain.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            // Parent context (highlighted if changed)
            if (showParentName != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 12,
                    color: parentChanged
                        ? domain.primary
                        : AppColors.darkText.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'in $showParentName',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: parentChanged ? FontWeight.w700 : FontWeight.w500,
                        color: parentChanged
                            ? domain.primary
                            : AppColors.darkText.withValues(alpha: 0.4),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(
              afterTitle,
              style: AppTypography.metadataText(
                color: titleChanged
                    ? domain.primary
                    : domain.primary.withValues(alpha: 0.5),
              ).copyWith(
                fontSize: 13,
                fontWeight: titleChanged ? FontWeight.w700 : FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                _buildMiniChip(
                  afterCategory[0].toUpperCase() + afterCategory.substring(1),
                  categoryChanged
                      ? domain.primary
                      : domain.primary.withValues(alpha: 0.5),
                  highlight: categoryChanged,
                ),
                if (afterPriority != null && afterPriority != 'none')
                  _buildMiniChip(
                    afterPriority[0].toUpperCase() + afterPriority.substring(1),
                    priorityChanged
                        ? _priorityColor(afterPriority)
                        : _priorityColor(afterPriority).withValues(alpha: 0.5),
                    highlight: priorityChanged,
                  ),
                if (afterDueDate != null)
                  _buildMiniChip(
                    DateFormat('MMM d').format(afterDueDate),
                    dueDateChanged
                        ? domain.primary
                        : domain.primary.withValues(alpha: 0.5),
                    highlight: dueDateChanged,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Smaller chip for before/after mini-cards
  Widget _buildMiniChip(String label, Color color, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight
            ? color.withValues(alpha: 0.2)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: highlight
            ? Border.all(color: color.withValues(alpha: 0.4), width: 1)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Simple card for add/complete/delete proposals (unchanged layout)
  Widget _buildSimpleProposalCard(
    BrainDumpTaskProposal proposal,
    bool isSelected,
    DomainPalette domain,
  ) {
    final l1Name = _resolveL1ParentName(proposal);
    return GestureDetector(
      onTap: () => _editProposal(proposal),
      onLongPress: () => _toggleProposal(proposal.id),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isSelected ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: domain.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: domain.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left accent bar
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: proposal.action == 'delete'
                      ? AppColors.deleteAction
                      : domain.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.content,
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildChip(
                          _actionLabel(proposal.action),
                          _actionColor(proposal.action, domain),
                        ),
                        _buildChip(
                          l1Name ??
                              (proposal.category[0].toUpperCase() +
                                  proposal.category.substring(1)),
                          domain.primary,
                        ),
                        if (proposal.priority != null &&
                            proposal.priority != 'none')
                          _buildChip(
                            proposal.priority![0].toUpperCase() +
                                proposal.priority!.substring(1),
                            _priorityColor(proposal.priority!),
                          ),
                        if (proposal.dueDate != null)
                          _buildChip(
                            DateFormat('MMM d').format(proposal.dueDate!),
                            domain.primary.withValues(alpha: 0.7),
                          ),
                        if (proposal.confidence != null)
                          _buildChip(
                            '${(proposal.confidence! * 100).round()}%',
                            _confidenceColor(proposal.confidence!),
                          ),
                        if (proposal.alternateMatches != null &&
                            proposal.alternateMatches!.isNotEmpty)
                          _buildChip(
                            '\u26A0 ${proposal.alternateMatches!.length + 1} matches',
                            AppColors.dueSoon,
                          ),
                      ],
                    ),
                    if (proposal.alternateMatches != null &&
                        proposal.alternateMatches!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildAlternateMatchesSection(proposal, domain),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Checkbox — tap to toggle selection
              GestureDetector(
                onTap: () => _toggleProposal(proposal.id),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? domain.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: domain.primary.withValues(
                          alpha: isSelected ? 1.0 : 0.4,
                        ),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: domain.textOnPrimary,
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.metadataText(color: color)
            .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= 0.8) return AppColors.completed;
    if (confidence >= 0.6) return AppColors.dueSoon;
    return AppColors.deleteAction;
  }

  Widget _buildAlternateMatchesSection(
    BrainDumpTaskProposal proposal,
    DomainPalette domain,
  ) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final expanded = _expandedAlternates.contains(proposal.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setLocalState(() {
                  if (expanded) {
                    _expandedAlternates.remove(proposal.id);
                  } else {
                    _expandedAlternates.add(proposal.id);
                  }
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 12,
                    color: AppColors.dueSoon,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Other matches (${proposal.alternateMatches!.length})',
                    style: AppTypography.metadataText(
                      color: AppColors.dueSoon,
                    ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: AppColors.dueSoon,
                  ),
                ],
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 4),
              ...proposal.alternateMatches!.map((match) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 2),
                  child: Text(
                    '\u2022 ${match['title'] ?? 'Unknown'} (${match['category'] ?? ''})',
                    style: AppTypography.metadataText(
                      color: AppColors.darkText.withValues(alpha: 0.5),
                    ).copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  String _actionLabel(String action) {
    return switch (action) {
      'complete' => 'Complete',
      'edit' => 'Edit',
      'delete' => 'Delete',
      _ => 'Add',
    };
  }

  Color _actionColor(String action, DomainPalette domain) {
    return switch (action) {
      'complete' => AppColors.completed,
      'edit' => AppColors.dueSoon,
      'delete' => AppColors.deleteAction,
      _ => domain.primary,
    };
  }

  Color _priorityColor(String priority) {
    return switch (priority.toLowerCase()) {
      'high' => AppColors.priorityHigh,
      'medium' => AppColors.priorityMedium,
      'low' => AppColors.priorityLow,
      _ => AppColors.darkText.withValues(alpha: 0.5),
    };
  }

  Widget _buildFooter(DomainPalette domain) => switch (_phase) {
    _RamblePhase.recording => _buildRecordingFooter(domain),
    _RamblePhase.processing => const SizedBox(height: AppSpacing.md),
    _RamblePhase.editing => _buildEditingFooter(domain),
    _RamblePhase.reviewing => _buildReviewingFooter(domain),
  };

  Widget _buildRecordingFooter(DomainPalette domain) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.lg,
        top: AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pause / Resume button
              Semantics(
                button: true,
                label: 'Pause recording',
                child: GestureDetector(
                  onTap: _canStopListening ? _togglePause : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isPaused
                          ? domain.primary.withValues(alpha: 0.15)
                          : AppColors.darkText.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: domain.primary.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Icon(
                      _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 24,
                      color: domain.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Stop button
              Semantics(
                button: true,
                label: 'Stop recording',
                child: GestureDetector(
                  key: TK.stopButton,
                  onTap: _canStopListening ? _stopAndEdit : null,
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
              ),
            ],
          ),
          if (_connectionState == RambleConnectionState.disconnected) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              button: true,
              label: 'Reconnect',
              child: GestureDetector(
                onTap: _handleReconnect,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: domain.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: domain.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 16, color: domain.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Reconnect',
                        style: AppTypography.metadataText(
                          color: domain.primary,
                        ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            _connectionState == RambleConnectionState.disconnected
                ? 'Disconnected — reconnect or stop to edit'
                : _isPaused ? 'Paused — tap play to resume' : 'Tap to stop',
            style: AppTypography.metadataText(
              color: AppColors.tertiaryText,
            ).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEditingFooter(DomainPalette domain) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _reRecord,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: domain.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic_none_rounded, size: 18, color: domain.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Re-record',
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _processBrainDump,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: domain.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  boxShadow: domain.glow != null
                      ? [BoxShadow(
                          color: domain.glow!,
                          blurRadius: 12,
                          spreadRadius: 2,
                        )]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Send',
                    style: AppTypography.metadataText(
                      color: domain.textOnPrimary,
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

  Widget _buildReviewingFooter(DomainPalette domain) {
    final selectedCount = _proposals.length - _deselectedIds.length;
    final canSubmit = selectedCount > 0 && !_isSubmitting;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      child: Row(
        children: [
          // Re-extract button (pencil icon, circle)
          GestureDetector(
            onTap: _goBackToEditing,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: domain.primary.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(Icons.edit_rounded, size: 20, color: domain.primary),
            ),
          ),
          const SizedBox(width: 10),
          // Record more button (mic icon, circle)
          GestureDetector(
            onTap: _recordMore,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: domain.primary.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(Icons.mic_none_rounded, size: 20, color: domain.primary),
            ),
          ),
          const SizedBox(width: 10),
          // Confirm button (expanded)
          Expanded(
            child: GestureDetector(
              key: TK.submitButton,
              onTap: canSubmit ? _submitProposals : null,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: canSubmit ? 1.0 : 0.4,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: domain.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    boxShadow: domain.glow != null && canSubmit
                        ? [BoxShadow(
                            color: domain.glow!,
                            blurRadius: 12,
                            spreadRadius: 2,
                          )]
                        : null,
                  ),
                  child: Center(
                    child: _isSubmitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: domain.textOnPrimary,
                            ),
                          )
                        : Text(
                            'Confirm $selectedCount Action${selectedCount == 1 ? '' : 's'}',
                            style: AppTypography.metadataText(
                              color: domain.textOnPrimary,
                            ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────── Proposal Edit Sheet ──────────

class _ProposalEditSheet extends ConsumerStatefulWidget {
  final BrainDumpTaskProposal proposal;
  final Map<String, DomainPalette> paletteMap;

  const _ProposalEditSheet({
    required this.proposal,
    required this.paletteMap,
  });

  @override
  ConsumerState<_ProposalEditSheet> createState() => _ProposalEditSheetState();
}

class _ProposalEditSheetState extends ConsumerState<_ProposalEditSheet> {
  late final TextEditingController _titleController;
  late final PageController _pageController;
  late String _action;
  late String _category;
  late String _priority;
  DateTime? _dueDate;
  String? _matchedTaskId;
  String? _targetParentId;
  String? _targetContent;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.proposal.content);
    _pageController = PageController();
    _action = widget.proposal.action;
    _category = widget.proposal.category;
    _priority = widget.proposal.priority ?? 'none';
    _dueDate = widget.proposal.dueDate;
    _matchedTaskId = widget.proposal.matchedTaskId;
    // Extract reparent target from changes.parent_id if present
    final changes = widget.proposal.changes;
    _targetParentId = changes != null && changes.containsKey('parent_id')
        ? changes['parent_id'] as String?
        : null;
    _targetContent = null; // Will be resolved by parent picker
  }

  @override
  void dispose() {
    _titleController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    // Clear irrelevant fields when action changes
    final isAdd = _action == 'add';
    final isEdit = _action == 'edit';

    // Build changes map — merge existing changes with reparent if applicable
    Map<String, dynamic>? editChanges;
    if (isEdit) {
      editChanges = Map<String, dynamic>.from(widget.proposal.changes ?? {});
      // If user set a reparent target via parent picker, add to changes
      if (_targetParentId != null || _targetContent != null) {
        editChanges['parent_id'] = _targetParentId;
      }
    }

    final edited = BrainDumpTaskProposal(
      id: widget.proposal.id,
      action: _action,
      content: title,
      description: widget.proposal.description,
      category: _category,
      dueDate: _dueDate,
      priority: _priority == 'none' ? null : _priority,
      parentId: isAdd ? widget.proposal.parentId : null,
      labels: widget.proposal.labels,
      changes: editChanges,
      matchedTaskId: isAdd ? null : _matchedTaskId,
    );
    Navigator.pop(context, edited);
  }

  void _openParentPicker() {
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: AppAnimations.easeOutCubic,
    );
  }

  void _onParentSelected(ParentPickerResult result) {
    setState(() {
      _targetParentId = result.taskId;
      _targetContent = result.taskTitle;
      if (result.category != _category) {
        _category = result.category;
      }
    });
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 300),
      curve: AppAnimations.easeOutCubic,
    );
  }

  Future<void> _pickDate() async {
    final domain = DomainColors.getDomain(_category, true, widget.paletteMap);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: domain.primary,
              surface: AppColors.darkBg,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _flipMoveDirection() {
    HapticService.light();
    setState(() {
      // Swap source (title + matchedTaskId) with destination (targetContent + targetParentId)
      final oldTitle = _titleController.text;
      final oldMatchedId = _matchedTaskId;

      _titleController.text = _targetContent ?? '';
      _matchedTaskId = _targetParentId;

      _targetContent = oldTitle;
      _targetParentId = oldMatchedId;
    });
  }

  Widget _buildMoveToRow(DomainPalette domain) {
    final targetLabel = _targetContent != null
        ? _targetContent!.capitalize
        : 'Top level';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Move to',
                style: AppTypography.metadataText(
                  color: AppColors.darkText.withValues(alpha: 0.5),
                ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _flipMoveDirection,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_vert_rounded, size: 14, color: domain.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Flip',
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _openParentPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: domain.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: domain.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.drive_file_move_outline, size: 16, color: domain.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      targetLabel,
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: domain.primary.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final domain = DomainColors.getDomain(_category, true, widget.paletteMap);
    final categories = widget.paletteMap.keys.toList();
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight = MediaQuery.of(context).size.height * 0.75;

    return Container(
      height: sheetHeight,
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
        border: Border(
          top: BorderSide(color: domain.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Page 0: Edit form
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.darkText.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm,
                  ),
                  child: Text(
                    'Edit proposal',
                    style: AppTypography.metadataText(color: AppColors.darkText)
                        .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),

                // Action type chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Action',
                        style: AppTypography.metadataText(
                          color: AppColors.darkText.withValues(alpha: 0.5),
                        ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _ChipSelector(
                        items: const ['add', 'complete', 'edit', 'delete'],
                        selected: _action,
                        onSelect: (a) => setState(() => _action = a),
                        colorFn: _actionChipColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Title field (read-only for complete/delete — these act on existing tasks)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: TextField(
                    controller: _titleController,
                    readOnly: _action != 'add' && _action != 'edit',
                    style: AppTypography.metadataText(color: AppColors.darkText)
                        .copyWith(fontSize: 15, height: 1.4),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      labelStyle: AppTypography.metadataText(
                        color: AppColors.darkText.withValues(alpha: 0.5),
                      ).copyWith(fontSize: 13),
                      filled: true,
                      fillColor: AppColors.darkText.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        borderSide: BorderSide(
                          color: domain.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        borderSide: BorderSide(
                          color: domain.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        borderSide: BorderSide(
                          color: domain.primary.withValues(alpha: 0.6),
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(AppSpacing.md),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Category chips (editable for add/edit, locked for complete/delete)
                IgnorePointer(
                  ignoring: _action != 'add' && _action != 'edit',
                  child: Opacity(
                    opacity: (_action == 'add' || _action == 'edit') ? 1.0 : 0.5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Category',
                            style: AppTypography.metadataText(
                              color: AppColors.darkText.withValues(alpha: 0.5),
                            ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          _ChipSelector(
                            items: categories,
                            selected: _category,
                            onSelect: (cat) => setState(() => _category = cat),
                            colorFn: (cat) => DomainColors.getDomain(
                              cat, true, widget.paletteMap,
                            ).primary,
                            selectedTextColorFn: (cat) => DomainColors.getDomain(
                              cat, true, widget.paletteMap,
                            ).textOnPrimary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Reparent row (for edit actions with parent_id change)
                if (_action == 'edit' && (_targetParentId != null || _targetContent != null))
                  _buildMoveToRow(domain),

                if (_action == 'edit' && (_targetParentId != null || _targetContent != null))
                  const SizedBox(height: AppSpacing.md),

                // Priority chips (locked for complete/delete)
                if (_action == 'add' || _action == 'edit')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Priority',
                        style: AppTypography.metadataText(
                          color: AppColors.darkText.withValues(alpha: 0.5),
                        ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _ChipSelector(
                        items: const ['none', 'low', 'medium', 'high'],
                        selected: _priority,
                        onSelect: (p) => setState(() => _priority = p),
                        colorFn: _priorityChipColor,
                      ),
                    ],
                  ),
                ),

                if (_action == 'add' || _action == 'edit')
                const SizedBox(height: AppSpacing.md),

                // Due date (only for add/edit)
                if (_action == 'add' || _action == 'edit')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Due date',
                        style: AppTypography.metadataText(
                          color: AppColors.darkText.withValues(alpha: 0.5),
                        ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickDate,
                        onLongPress: () => setState(() => _dueDate = null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: domain.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: domain.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: domain.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _dueDate != null
                                    ? DateFormat('MMM d').format(_dueDate!)
                                    : 'No date',
                                style: AppTypography.metadataText(
                                  color: domain.primary,
                                ).copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_dueDate != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Long-press to clear',
                            style: AppTypography.metadataText(
                              color: AppColors.tertiaryText,
                            ).copyWith(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Footer buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg,
                    MediaQuery.of(context).padding.bottom + AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                              border: Border.all(
                                color: AppColors.darkText.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Cancel',
                                style: AppTypography.metadataText(
                                  color: AppColors.darkText.withValues(alpha: 0.7),
                                ).copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _save,
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: domain.primary,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Save',
                                style: AppTypography.metadataText(
                                  color: domain.textOnPrimary,
                                ).copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Page 1: Parent picker
          TaskParentPicker(
            currentParentId: _targetParentId,
            excludeTaskId: widget.proposal.matchedTaskId,
            onBack: () => _pageController.animateToPage(
              0,
              duration: const Duration(milliseconds: 300),
              curve: AppAnimations.easeOutCubic,
            ),
            onSelect: _onParentSelected,
          ),
        ],
      ),
    );
  }

  Color _priorityChipColor(String priority) {
    return switch (priority) {
      'high' => AppColors.priorityHigh,
      'medium' => AppColors.priorityMedium,
      'low' => AppColors.priorityLow,
      _ => AppColors.darkText.withValues(alpha: 0.5),
    };
  }

  Color _actionChipColor(String action) {
    return switch (action) {
      'complete' => AppColors.completed,
      'edit' => AppColors.dueSoon,
      'delete' => AppColors.deleteAction,
      'move' => AppColors.dueSoon,
      _ => AppColors.darkText.withValues(alpha: 0.7),
    };
  }
}

/// Reusable chip selector for action/category/priority pickers.
class _ChipSelector extends StatelessWidget {
  final List<String> items;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Color Function(String) colorFn;
  final Color Function(String)? selectedTextColorFn;

  const _ChipSelector({
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.colorFn,
    this.selectedTextColorFn,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final isSelected = item == selected;
        final color = colorFn(item);
        final selectedTextColor = selectedTextColorFn?.call(item) ?? Colors.white;
        return GestureDetector(
          onTap: () => onSelect(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? color : color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withValues(alpha: isSelected ? 1.0 : 0.3),
              ),
            ),
            child: Text(
              item.capitalize,
              style: AppTypography.metadataText(
                color: isSelected ? selectedTextColor : color,
              ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }).toList(),
    );
  }
}
