import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../utils/string_extensions.dart';
import 'styled_snackbar.dart';

/// Bottom sheet for resolving question-type agent responses.
/// Shows color-coded task options or category creation confirmation.
class QuestionBottomSheet extends ConsumerStatefulWidget {
  final AgentResponse response;

  const QuestionBottomSheet({super.key, required this.response});

  @override
  ConsumerState<QuestionBottomSheet> createState() =>
      _QuestionBottomSheetState();
}

class _QuestionBottomSheetState extends ConsumerState<QuestionBottomSheet> {
  String? _loadingId;

  Map<String, dynamic> get _data => widget.response.data ?? {};
  String get _action => _data['action'] as String? ?? '';
  List<dynamic> get _matches => _data['matches'] as List<dynamic>? ?? [];

  /// Shared resolve-action flow: set loading → API call → fetchAll → pop → handle result.
  Future<void> _resolveAction({
    required String loadingId,
    required Future<AgentResponse> Function() apiCall,
  }) async {
    setState(() => _loadingId = loadingId);
    try {
      final result = await apiCall();
      await ref.read(taskStoreProvider.notifier).fetchAll();

      if (!mounted) return;
      Navigator.pop(context);

      if (result.type == 'question' && result.data != null) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => QuestionBottomSheet(response: result),
        );
      } else {
        showStyledSnackbar(context,
          message: result.message,
          style: SnackbarStyle.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingId = null);
        showStyledSnackbar(context,
          message: 'Failed: $e',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<void> _onMatchTap(Map<String, dynamic> match) async {
    if (_loadingId != null) return;
    HapticService.light();
    final apiService = ref.read(apiServiceProvider);
    await _resolveAction(
      loadingId: match['id'] as String,
      apiCall: () => apiService.resolveQuestion(
        userId: AppConstants.defaultUserId,
        action: _action,
        selectedTaskId: match['id'] as String,
        data: _data,
      ),
    );
  }

  Future<void> _onCreateCategory() async {
    if (_loadingId != null) return;
    HapticService.medium();
    final apiService = ref.read(apiServiceProvider);
    await _resolveAction(
      loadingId: 'confirm',
      apiCall: () => apiService.resolveQuestion(
        userId: AppConstants.defaultUserId,
        action: 'create_category',
        data: _data,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSpacing.radiusLg),
          topRight: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
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

          // Header message
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md,
            ),
            child: Text(
              widget.response.message,
              style: AppTypography.metadataText(color: AppColors.darkText)
                  .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),

          // Body
          if (_action == 'create_category')
            _buildCreateCategoryBody()
          else if (_action == 'select_category')
            _buildSelectCategoryBody()
          else
            _buildMatchListBody(),

          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.md),
        ],
      ),
    );
  }

  Widget _buildMatchListBody() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: _matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final match = _matches[index] as Map<String, dynamic>;
        final id = match['id'] as String;
        final title = match['title'] as String;
        final category = match['category'] as String? ?? 'work';
        final domain = DomainColors.getDomain(category, true, ref.read(domainPalettesProvider));
        final isLoading = _loadingId == id;

        return GestureDetector(
          onTap: () => _onMatchTap(match),
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
              children: [
                // Left accent bar
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: domain.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                // Title
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.metadataText(color: domain.primary)
                        .copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Loading spinner or arrow
                if (isLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: domain.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    color: domain.primary.withValues(alpha: 0.5),
                    size: 20,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onSelectCategory(String category) async {
    if (_loadingId != null) return;
    HapticService.medium();
    final apiService = ref.read(apiServiceProvider);
    await _resolveAction(
      loadingId: category,
      apiCall: () => apiService.resolveQuestion(
        userId: AppConstants.defaultUserId,
        action: 'select_category',
        data: {..._data, 'selected_category': category},
      ),
    );
  }

  Widget _buildSelectCategoryBody() {
    final categories = (_data['current_categories'] as List<dynamic>?)
            ?.cast<String>() ??
        [];
    final paletteMap = ref.read(domainPalettesProvider);

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final domain = DomainColors.getDomain(cat, true, paletteMap);
        final isLoading = _loadingId == cat;

        return GestureDetector(
          onTap: () => _onSelectCategory(cat),
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
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: domain.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cat.capitalize,
                    style: AppTypography.metadataText(color: domain.primary)
                        .copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: domain.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    color: domain.primary.withValues(alpha: 0.5),
                    size: 20,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateCategoryBody() {
    final suggestedCategory = _data['suggested_category'] as String? ?? '';
    final domain = DomainColors.getDomain(suggestedCategory, true, ref.read(domainPalettesProvider));
    final isLoading = _loadingId == 'confirm';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          // Cancel
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticService.light();
                Navigator.pop(context);
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: AppColors.darkText.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: AppTypography.metadataText(color: AppColors.darkText)
                        .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Confirm
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _onCreateCategory,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: domain.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  boxShadow: [
                    if (domain.glow != null)
                      BoxShadow(
                        color: domain.glow!,
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: Center(
                  child: isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: domain.textOnPrimary,
                          ),
                        )
                      : Text(
                          'Create ${suggestedCategory.isNotEmpty ? suggestedCategory.capitalize : "category"}',
                          style: AppTypography.metadataText(
                            color: domain.textOnPrimary,
                          ).copyWith(fontSize: 15, fontWeight: FontWeight.w700),
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
