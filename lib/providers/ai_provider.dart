import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo/services/gemini_service.dart';
import 'package:todo/services/agent_service.dart';
import 'package:todo/providers/task_provider.dart';
import 'package:todo/data/models/agent_intent.dart';

/// Gemini service provider
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

/// Transcription state
class TranscriptionState {
  final String? transcription;
  final bool isLoading;
  final String? error;

  TranscriptionState({
    this.transcription,
    this.isLoading = false,
    this.error,
  });

  TranscriptionState copyWith({
    String? transcription,
    bool? isLoading,
    String? error,
  }) {
    return TranscriptionState(
      transcription: transcription ?? this.transcription,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Transcription state notifier
class TranscriptionStateNotifier extends StateNotifier<TranscriptionState> {
  TranscriptionStateNotifier() : super(TranscriptionState());

  void setLoading() {
    state = state.copyWith(isLoading: true, error: null);
  }

  void setTranscription(String transcription) {
    state = state.copyWith(
      transcription: transcription,
      isLoading: false,
      error: null,
    );
  }

  void setError(String error) {
    state = state.copyWith(isLoading: false, error: error);
  }

  void reset() {
    state = TranscriptionState();
  }
}

/// Transcription state provider
final transcriptionStateProvider =
    StateNotifierProvider<TranscriptionStateNotifier, TranscriptionState>((ref) {
  return TranscriptionStateNotifier();
});

/// Categorization state
class CategorizationState {
  final AICategorizationResponse? categorization;
  final bool isLoading;
  final String? error;

  CategorizationState({
    this.categorization,
    this.isLoading = false,
    this.error,
  });

  CategorizationState copyWith({
    AICategorizationResponse? categorization,
    bool? isLoading,
    String? error,
  }) {
    return CategorizationState(
      categorization: categorization ?? this.categorization,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Categorization state notifier
class CategorizationStateNotifier extends StateNotifier<CategorizationState> {
  CategorizationStateNotifier() : super(CategorizationState());

  void setLoading() {
    state = state.copyWith(isLoading: true, error: null);
  }

  void setCategorization(AICategorizationResponse categorization) {
    state = state.copyWith(
      categorization: categorization,
      isLoading: false,
      error: null,
    );
  }

  void setError(String error) {
    state = state.copyWith(isLoading: false, error: error);
  }

  void reset() {
    state = CategorizationState();
  }
}

/// Categorization state provider
final categorizationStateProvider =
    StateNotifierProvider<CategorizationStateNotifier, CategorizationState>((ref) {
  return CategorizationStateNotifier();
});

/// Agent service provider
final agentServiceProvider = Provider<AgentService>((ref) {
  final geminiService = ref.watch(geminiServiceProvider);
  final taskRepository = ref.watch(taskRepositoryProvider);
  return AgentService(
    geminiService: geminiService,
    taskRepository: taskRepository,
  );
});

/// Agent state
class AgentState {
  final AgentResponse? response;
  final bool isProcessing;
  final String? error;

  AgentState({
    this.response,
    this.isProcessing = false,
    this.error,
  });

  AgentState copyWith({
    AgentResponse? response,
    bool? isProcessing,
    String? error,
  }) {
    return AgentState(
      response: response ?? this.response,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
    );
  }
}

/// Agent state notifier
class AgentStateNotifier extends StateNotifier<AgentState> {
  AgentStateNotifier() : super(AgentState());

  void setProcessing() {
    state = state.copyWith(isProcessing: true, error: null);
  }

  void setResponse(AgentResponse response) {
    state = state.copyWith(
      response: response,
      isProcessing: false,
      error: null,
    );
  }

  void setError(String error) {
    state = state.copyWith(isProcessing: false, error: error);
  }

  void reset() {
    state = AgentState();
  }
}

/// Agent state provider
final agentStateProvider =
    StateNotifierProvider<AgentStateNotifier, AgentState>((ref) {
  return AgentStateNotifier();
});
