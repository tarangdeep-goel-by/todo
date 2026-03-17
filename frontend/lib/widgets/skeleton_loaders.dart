import 'package:flutter/material.dart';
import '../config/theme.dart';

// ── Shimmer effect ──────────────────────────────────────────────────────

/// Reusable shimmer animation wrapper. No external package needed.
class ShimmerEffect extends StatefulWidget {
  final Widget child;

  const ShimmerEffect({super.key, required this.child});

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0xFF1A1816),
                Color(0xFF2A2622),
                Color(0xFF1A1816),
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A single shimmer bone (rounded rectangle placeholder).
class _Bone extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _Bone({
    required this.width,
    required this.height,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1C1A),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ── Skeleton task row ───────────────────────────────────────────────────

/// Mimics FlatTaskRow layout: accent bar + two text lines + right metadata.
class SkeletonTaskRow extends StatelessWidget {
  const SkeletonTaskRow({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0x0FF0EBE5), width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Accent bar
            const _Bone(width: 4, height: 36, radius: 2),
            const SizedBox(width: 10),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Bone(width: MediaQuery.of(context).size.width * 0.55, height: 14),
                  const SizedBox(height: 6),
                  const _Bone(width: 80, height: 10),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right side: date + priority placeholders
            const Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Bone(width: 48, height: 10),
                SizedBox(height: 6),
                _Bone(width: 36, height: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a list of skeleton task rows.
class SkeletonTaskList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;

  const SkeletonTaskList({
    super.key,
    this.count = 8,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: List.generate(count, (_) => const SkeletonTaskRow()),
      ),
    );
  }
}

// ── Skeleton domain card (ParentNodeView) ───────────────────────────────

/// Mimics the compressed domain card strip.
class SkeletonDomainCardCompressed extends StatelessWidget {
  final double height;

  const SkeletonDomainCardCompressed({super.key, this.height = 56});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1816),
          border: Border(
            left: BorderSide(color: Color(0xFF2A2622), width: 4),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Bone(width: 100, height: 18, radius: 4),
            _Bone(width: 56, height: 12, radius: 4),
          ],
        ),
      ),
    );
  }
}

/// Mimics the focused domain card with task previews inside.
class SkeletonDomainCardFocused extends StatelessWidget {
  final double height;

  const SkeletonDomainCardFocused({super.key, this.height = 300});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1816),
          border: const Border(
            left: BorderSide(color: Color(0xFF2A2622), width: 4),
          ),
          borderRadius: BorderRadius.circular(0),
        ),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Domain name placeholder
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Bone(width: MediaQuery.of(context).size.width * 0.35, height: 32, radius: 6),
                const _Bone(width: 60, height: 14, radius: 4),
              ],
            ),
            const SizedBox(height: 16),
            // Inset task preview area
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.cardInset,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: List.generate(
                    3,
                    (_) => const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          _Bone(width: 4, height: 28, radius: 2),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Bone(width: 160, height: 12),
                                SizedBox(height: 4),
                                _Bone(width: 60, height: 9),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full skeleton for ParentNodeView: 1 focused + compressed cards filling space.
class SkeletonParentNodeView extends StatelessWidget {
  const SkeletonParentNodeView({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        // Approximate: focused takes ~65%, rest split among compressed
        final focusedHeight = totalHeight * 0.65;
        final compressedCount = 4;
        final compressedHeight =
            (totalHeight - focusedHeight) / compressedCount;

        return Column(
          children: [
            SkeletonDomainCardFocused(height: focusedHeight),
            ...List.generate(
              compressedCount,
              (_) => SkeletonDomainCardCompressed(
                height: compressedHeight,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Skeleton calendar grid ──────────────────────────────────────────────

/// Mimics CalendarTaskView layout: month header + weekday row + day grid.
class SkeletonCalendarGrid extends StatelessWidget {
  const SkeletonCalendarGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // Month header
            const Row(
              children: [
                _Bone(width: 130, height: 16, radius: 4),
                Spacer(),
                _Bone(width: 20, height: 16, radius: 4),
                SizedBox(width: 8),
                _Bone(width: 20, height: 16, radius: 4),
              ],
            ),
            const SizedBox(height: 16),
            // Weekday headers
            Row(
              children: List.generate(
                7,
                (_) => const Expanded(
                  child: Center(child: _Bone(width: 24, height: 10, radius: 3)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 5 rows of day cells
            ...List.generate(
              5,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: List.generate(
                    7,
                    (_) => const Expanded(
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: _Bone(width: 20, height: 14, radius: 4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Divider
            Container(height: 1, color: const Color(0x0FF0EBE5)),
            const SizedBox(height: 12),
            // Selected day header
            const _Bone(width: 100, height: 14, radius: 4),
            const SizedBox(height: 16),
            // Placeholder task rows
            ...List.generate(
              3,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SkeletonTaskRow(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton proposal card (RambleScreen) ───────────────────────────────

/// Mimics the brain dump proposal card layout.
class SkeletonProposalCard extends StatelessWidget {
  const SkeletonProposalCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1816),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x15F0EBE5)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action badge + confidence chip
            Row(
              children: [
                _Bone(width: 52, height: 20, radius: 10),
                SizedBox(width: 8),
                _Bone(width: 36, height: 20, radius: 10),
              ],
            ),
            SizedBox(height: 12),
            // Content text lines
            _Bone(width: double.infinity, height: 14),
            SizedBox(height: 6),
            _Bone(width: 200, height: 14),
            SizedBox(height: 12),
            // Category + parent chips
            Row(
              children: [
                _Bone(width: 70, height: 18, radius: 10),
                SizedBox(width: 8),
                _Bone(width: 90, height: 18, radius: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a list of skeleton proposal cards.
class SkeletonProposalList extends StatelessWidget {
  final int count;

  const SkeletonProposalList({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: List.generate(
          count,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i < count - 1 ? 10 : 0),
            child: const SkeletonProposalCard(),
          ),
        ),
      ),
    );
  }
}

// ── Skeleton auth gate (full-screen app shell) ──────────────────────────

/// Full-screen skeleton mimicking the home screen shell during auth loading.
class SkeletonAppShell extends StatelessWidget {
  const SkeletonAppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Column(
        children: [
          // Top bar placeholder
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Bone(width: 100, height: 24, radius: 6),
                Row(
                  children: [
                    _Bone(width: 28, height: 28, radius: 14),
                    SizedBox(width: 12),
                    _Bone(width: 28, height: 28, radius: 14),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Task rows
          const Expanded(
            child: SkeletonTaskList(count: 10),
          ),
        ],
      ),
    );
  }
}
