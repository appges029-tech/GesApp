import 'package:flutter/material.dart';

import '../../core/security/pattern_policy.dart';

/// Finger-drawn 3x3 pattern widget, never persists a gesture or draws it
/// outside the current screen. Android-like intermediate-dot interpolation.
class PatternInput extends StatefulWidget {
  const PatternInput({super.key, required this.onComplete, this.enabled = true});
  final ValueChanged<List<int>> onComplete;
  final bool enabled;

  @override
  State<PatternInput> createState() => _PatternInputState();
}

class _PatternInputState extends State<PatternInput> {
  final List<int> _selected = [];
  Offset? _cursor;
  Size _size = const Size(260, 260);

  Offset _center(int i) => Offset(
    (i % 3 + 1) * _size.width / 4,
    (i ~/ 3 + 1) * _size.height / 4,
  );

  void _track(Offset point) {
    if (!widget.enabled) return;
    final threshold = _size.shortestSide / 8;
    for (var i = 0; i < 9; i++) {
      if ((_center(i) - point).distance <= threshold &&
          !_selected.contains(i)) {
        final next = PatternPolicy.normalize([..._selected, i]);
        setState(() {
          _selected
            ..clear()
            ..addAll(next);
        });
        break;
      }
    }
    setState(() => _cursor = point);
  }

  void _finish() {
    if (!widget.enabled) return;
    final result = List<int>.unmodifiable(_selected);
    setState(() {
      _selected.clear();
      _cursor = null;
    });
    if (result.isNotEmpty) widget.onComplete(result);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = constraints.maxWidth.clamp(160.0, 280.0).toDouble();
      _size = Size.square(side);
      return Center(
        child: Semantics(
          label: 'Dessinez votre schéma de sécurité à neuf points',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.enabled ? (details) => _track(details.localPosition) : null,
            onPanUpdate: widget.enabled ? (details) => _track(details.localPosition) : null,
            onPanEnd: widget.enabled ? (_) => _finish() : null,
            onPanCancel: _finish,
            child: CustomPaint(
              size: _size,
              painter: _PatternPainter(
                chosen: _selected,
                cursor: _cursor,
                color: Theme.of(context).colorScheme.primary,
                neutral: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter({
    required this.chosen,
    required this.cursor,
    required this.color,
    required this.neutral,
  });
  final List<int> chosen;
  final Offset? cursor;
  final Color color, neutral;

  @override
  void paint(Canvas canvas, Size size) {
    Offset center(int i) => Offset(
      (i % 3 + 1) * size.width / 4,
      (i ~/ 3 + 1) * size.height / 4,
    );
    if (chosen.isNotEmpty) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(center(chosen.first).dx, center(chosen.first).dy);
      for (final i in chosen.skip(1)) {
        path.lineTo(center(i).dx, center(i).dy);
      }
      if (cursor != null) path.lineTo(cursor!.dx, cursor!.dy);
      canvas.drawPath(path, paint);
    }
    for (var i = 0; i < 9; i++) {
      final selected = chosen.contains(i);
      canvas.drawCircle(center(i), selected ? 13 : 11, Paint()
        ..color = selected ? color : neutral.withValues(alpha: .25));
      canvas.drawCircle(center(i), selected ? 5 : 4, Paint()
        ..color = selected ? Colors.white : neutral);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.cursor != cursor || old.color != color ||
      old.neutral != neutral || !_same(old.chosen, chosen);

  bool _same(List<int> a, List<int> b) =>
      a.length == b.length && List.generate(a.length, (i) => i)
          .every((i) => a[i] == b[i]);
}
