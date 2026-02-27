import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Smooth animated waveform that reads amplitude data at 60fps.
///
/// Self-contained: owns its own Ticker, reads directly from [amplitudeSource],
/// and isolates repaints via RepaintBoundary. Parent widget never rebuilds.
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
  late final List<double> _displayValues;
  late final List<double> _targetValues;

  static const _smoothing = 0.18; // lerp factor per frame — lower = smoother
  static const _minBar = 0.04; // minimum bar height for idle pulse

  @override
  void initState() {
    super.initState();
    _displayValues = List.filled(widget.barCount, _minBar);
    _targetValues = List.filled(widget.barCount, _minBar);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    final raw = widget.amplitudeSource();

    // Map raw samples into barCount target buckets
    if (raw.isNotEmpty) {
      for (int i = 0; i < widget.barCount; i++) {
        // Map bar index to raw sample index
        final rawIdx = (i * raw.length / widget.barCount).floor();
        final sample = rawIdx < raw.length ? raw[rawIdx] : 0.0;
        _targetValues[i] = sample.clamp(0.0, 1.0);
      }
    } else {
      for (int i = 0; i < widget.barCount; i++) {
        _targetValues[i] = _minBar;
      }
    }

    // Smooth toward targets
    bool changed = false;
    for (int i = 0; i < widget.barCount; i++) {
      final target = max(_targetValues[i], _minBar);
      final prev = _displayValues[i];
      final next = prev + (target - prev) * _smoothing;
      if ((next - prev).abs() > 0.001) {
        _displayValues[i] = next;
        changed = true;
      }
    }

    if (changed) {
      // Trigger repaint without rebuilding widget tree
      (context as Element).markNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WaveformBarPainter(
          amplitudes: _displayValues,
          color: widget.color,
        ),
        child: SizedBox(width: double.infinity, height: widget.height),
      ),
    );
  }
}

/// Draws centered vertical bars from a list of 0.0–1.0 amplitudes.
class _WaveformBarPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;

  _WaveformBarPainter({required this.amplitudes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
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
  bool shouldRepaint(_WaveformBarPainter old) => true;
}
