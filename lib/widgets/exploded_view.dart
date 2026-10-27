import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../models.dart';
import '../theme.dart';

class ParsedPart {
  final ViewPart part;
  final Path path;
  final Rect bounds;

  ParsedPart(this.part, this.path) : bounds = path.getBounds();
}

List<ParsedPart> parseViewParts(ExplodedView view) {
  final out = <ParsedPart>[];
  for (final p in view.parts) {
    try {
      out.add(ParsedPart(p, parseSvgPathData(p.path)..fillType = PathFillType.evenOdd));
    } catch (e) {
      debugPrint('Tracé invalide ${view.id}/${p.slug} : $e');
    }
  }
  return out;
}

List<(Path, Color?)> parseGuides(ExplodedView view) => [
      for (final g in view.guides)
        if (_tryParse(g.d) case final p?) (p, g.color),
    ];

Path? _tryParse(String d) {
  try {
    return parseSvgPathData(d);
  } catch (_) {
    return null;
  }
}

/// [point] is in view coordinates. Topmost part (drawn last) wins; open or
/// thin shapes fall back to their slightly inflated bounding box.
String? hitTestParts(List<ParsedPart> parts, Offset point,
    {double tolerance = 8}) {
  for (final p in parts.reversed) {
    if (p.path.contains(point)) return p.part.slug;
  }
  ParsedPart? best;
  for (final p in parts) {
    if (!p.bounds.inflate(tolerance).contains(point)) continue;
    if (best == null || _area(p.bounds) < _area(best.bounds)) best = p;
  }
  return best?.part.slug;
}

double _area(Rect r) => r.width * r.height;

class ExplodedViewWidget extends StatefulWidget {
  final ExplodedView view;
  final String? selected;
  final Set<String> highlighted;
  final ValueChanged<String?> onPartTap;

  const ExplodedViewWidget({
    super.key,
    required this.view,
    required this.onPartTap,
    this.selected,
    this.highlighted = const {},
  });

  @override
  State<ExplodedViewWidget> createState() => _ExplodedViewWidgetState();
}

class _ExplodedViewWidgetState extends State<ExplodedViewWidget> {
  final _controller = TransformationController();
  late List<ParsedPart> _parts;
  late List<(Path, Color?)> _guides;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant ExplodedViewWidget old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) {
      _parse();
      _controller.value = Matrix4.identity();
    }
  }

  void _parse() {
    _parts = parseViewParts(widget.view);
    _guides = parseGuides(widget.view);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    return LayoutBuilder(builder: (context, c) {
      final scale = [
        c.maxWidth / view.width,
        c.maxHeight / view.height,
      ].reduce((a, b) => a < b ? a : b);
      final size = Size(view.width * scale, view.height * scale);
      return InteractiveViewer(
        transformationController: _controller,
        minScale: 0.5,
        maxScale: 6,
        boundaryMargin: const EdgeInsets.all(200),
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) =>
                widget.onPartTap(hitTestParts(_parts, d.localPosition / scale)),
            child: CustomPaint(
              size: size,
              painter: ExplodedViewPainter(
                view: view,
                parts: _parts,
                guides: _guides,
                selected: widget.selected,
                highlighted: widget.highlighted,
              ),
            ),
          ),
        ),
      );
    });
  }
}

class ExplodedViewPainter extends CustomPainter {
  final ExplodedView view;
  final List<ParsedPart> parts;
  final List<(Path, Color?)> guides;
  final String? selected;
  final Set<String> highlighted;

  ExplodedViewPainter({
    required this.view,
    required this.parts,
    required this.guides,
    required this.selected,
    required this.highlighted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / view.width;
    canvas.save();
    canvas.scale(scale);
    final unit = view.width / 1000;

    // Fond "papier bleu d'architecte" : bleu profond + quadrillage fin.
    final w = view.width.toDouble();
    final h = view.height.toDouble();
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = EmvColors.background);
    final minor = Paint()
      ..color = EmvColors.grid.withValues(alpha: 0.35)
      ..strokeWidth = 0.6 * unit;
    final major = Paint()
      ..color = EmvColors.grid.withValues(alpha: 0.7)
      ..strokeWidth = 1.0 * unit;
    for (double x = 0; x <= w; x += 25 * unit) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), (x / unit) % 100 == 0 ? major : minor);
    }
    for (double y = 0; y <= h; y += 25 * unit) {
      canvas.drawLine(Offset(0, y), Offset(w, y), (y / unit) % 100 == 0 ? major : minor);
    }

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = EmvColors.guide
      ..strokeWidth = 1.2 * unit;
    for (final (path, color) in guides) {
      if (color == null) {
        _dashed(canvas, path, guidePaint, 8 * unit, 6 * unit);
      } else {
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = color
              ..strokeWidth = 2.4 * unit
              ..strokeCap = StrokeCap.round);
      }
    }

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final p in parts) {
      final slug = p.part.slug;
      final isSelected = slug == selected;
      final isHighlighted = highlighted.contains(slug);
      final color = p.part.color;
      final active = isSelected || isHighlighted;
      fill.color = isSelected
          ? EmvColors.accent.withValues(alpha: 0.55)
          : isHighlighted
              ? EmvColors.accent.withValues(alpha: 0.28)
              : color?.withValues(alpha: 0.85) ??
                  EmvColors.partFill.withValues(alpha: 0.55);
      stroke
        ..color = active
            ? EmvColors.accent
            : color ?? EmvColors.partStroke
        ..strokeWidth =
            (isSelected ? 3.2 : isHighlighted ? 2.4 : color != null ? 2.4 : 1.6) *
                unit;
      if (p.part.isClosed) canvas.drawPath(p.path, fill);
      canvas.drawPath(p.path, stroke);
    }

    for (final p in parts) {
      final slug = p.part.slug;
      if (slug == selected) continue;
      _label(canvas, p, highlighted.contains(slug), false, unit);
    }
    final sel = parts.where((p) => p.part.slug == selected);
    if (sel.isNotEmpty) _label(canvas, sel.first, true, true, unit);
    canvas.restore();
  }

  void _label(
      Canvas canvas, ParsedPart p, bool accent, bool emphasized, double unit) {
    final text = p.part.label.isEmpty ? p.part.slug : p.part.label;
    final at = p.part.labelAt ?? p.bounds.center;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: emphasized
              ? Colors.black
              : accent
                  ? EmvColors.accent
                  : EmvColors.label,
          fontSize: (emphasized ? 20 : 15) * unit,
          fontWeight: emphasized || accent ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 260 * unit);
    final topLeft = at - Offset(tp.width / 2, tp.height / 2);
    final box = (topLeft & tp.size).inflate(5 * unit);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(6 * unit)),
      Paint()
        ..color = emphasized
            ? EmvColors.accent
            : EmvColors.background.withValues(alpha: 0.72),
    );
    tp.paint(canvas, topLeft);
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant ExplodedViewPainter old) =>
      old.view != view ||
      old.parts != parts ||
      old.selected != selected ||
      !setEquals(old.highlighted, highlighted);
}

/// Vignette d'une vue : les pièces dessinées en miniature (sans libellés ni
/// quadrillage), cadrées sur leur emprise. Sert de "logo" dans les listes.
class ViewThumbnail extends StatelessWidget {
  final ExplodedView view;
  final double size;
  final Set<String> highlighted;

  const ViewThumbnail({
    super.key,
    required this.view,
    this.size = 56,
    this.highlighted = const {},
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: EmvColors.background,
        child: CustomPaint(
          painter: _ThumbnailPainter(parseViewParts(view), highlighted),
        ),
      ),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  final List<ParsedPart> parts;
  final Set<String> highlighted;
  _ThumbnailPainter(this.parts, this.highlighted);

  @override
  void paint(Canvas canvas, Size size) {
    if (parts.isEmpty) return;
    var bounds = parts.first.bounds;
    for (final p in parts.skip(1)) {
      bounds = bounds.expandToInclude(p.bounds);
    }
    if (bounds.isEmpty) return;
    const pad = 4.0;
    final scale = [
      (size.width - 2 * pad) / bounds.width,
      (size.height - 2 * pad) / bounds.height,
    ].reduce((a, b) => a < b ? a : b);
    final dx = (size.width - bounds.width * scale) / 2 - bounds.left * scale;
    final dy = (size.height - bounds.height * scale) / 2 - bounds.top * scale;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.2 / scale;
    for (final p in parts) {
      final hot = highlighted.contains(p.part.slug);
      final c = p.part.color;
      fill.color = hot
          ? EmvColors.accent.withValues(alpha: 0.7)
          : (c ?? EmvColors.partFill).withValues(alpha: 0.75);
      stroke.color = hot ? EmvColors.accent : (c ?? EmvColors.partStroke);
      if (p.part.isClosed) canvas.drawPath(p.path, fill);
      canvas.drawPath(p.path, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ThumbnailPainter old) =>
      old.parts != parts || old.highlighted != highlighted;
}
