import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Smooth animated waveform that reads amplitude data at 60fps.
///
/// Self-contained: owns its own Ticker, reads directly from [amplitudeSource],
/// and triggers repaints via a ChangeNotifier (no widget rebuilds).
class AnimatedWaveform extends StatefulWidget {
  /// Returns the current raw amplitude samples (0.0–1.0).
  final List<double> Function() amplitudeSource;
  final Color color;
  final double height;
  final int barCount;

  const AnimatedWaveform({
    super.key,
    required this.amplitudeSource,
    required this.color,
    this.height = 48,
    this.barCount = 40,
  });

  @override
  State<AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<AnimatedWaveform>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _WaveformNotifier _notifier;

  static const _smoothing = 0.18; // lerp factor per frame — lower = smoother
  static const _minBar = 0.04; // minimum bar height for idle pulse

  @override
  void initState() {
    super.initState();
    _notifier = _WaveformNotifier(widget.barCount, _minBar);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _notifier.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    final raw = widget.amplitudeSource();

    // Map raw samples into barCount target buckets
    if (raw.isNotEmpty) {
      for (int i = 0; i < widget.barCount; i++) {
        final rawIdx = (i * raw.length / widget.barCount).floor();
        final sample = rawIdx < raw.length ? raw[rawIdx] : 0.0;
        _notifier._targetValues[i] = sample.clamp(0.0, 1.0);
      }
    } else {
      for (int i = 0; i < widget.barCount; i++) {
        _notifier._targetValues[i] = _minBar;
      }
    }

    // Smooth toward targets
    bool changed = false;
    for (int i = 0; i < widget.barCount; i++) {
      final target = max(_notifier._targetValues[i], _minBar);
      final prev = _notifier.amplitudes[i];
      final next = prev + (target - prev) * _smoothing;
      if ((next - prev).abs() > 0.001) {
        _notifier.amplitudes[i] = next;
        changed = true;
      }
    }

    if (changed) _notifier.notify();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WaveformBarPainter(
          notifier: _notifier,
          color: widget.color,
        ),
        child: SizedBox(width: double.infinity, height: widget.height),
      ),
    );
  }
}

/// Holds mutable amplitude data and notifies the painter to repaint.
class _WaveformNotifier extends ChangeNotifier {
  final List<double> amplitudes;
  final List<double> _targetValues;

  _WaveformNotifier(int barCount, double minBar)
      : amplitudes = List.filled(barCount, minBar),
        _targetValues = List.filled(barCount, minBar);

  void notify() => notifyListeners();
}

/// Draws centered vertical bars from a list of 0.0–1.0 amplitudes.
/// Repaints are driven by the [_WaveformNotifier] listenable — no shouldRepaint needed.
class _WaveformBarPainter extends CustomPainter {
  final _WaveformNotifier _notifier;
  final Color color;

  _WaveformBarPainter({required _WaveformNotifier notifier, required this.color})
      : _notifier = notifier,
        super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final amplitudes = _notifier.amplitudes;
    if (amplitudes.isEmpty) return;

    final barCount = amplitudes.length;
    final gap = 2.0;
    final barWidth = (size.width - gap * (barCount - 1)) / barCount;
    final centerY = size.height / 2;
    final maxBarHeight = size.height * 0.85;

    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap) + barWidth / 2;
      final h = maxBarHeight * amplitudes[i];
      final halfH = max(h / 2, 1.5); // min 3px total height

      canvas.drawLine(
        Offset(x, centerY - halfH),
        Offset(x, centerY + halfH),
        paint..strokeWidth = barWidth.clamp(2.0, 4.0),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformBarPainter old) => false;
}
