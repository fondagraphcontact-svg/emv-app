import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';

import '../theme.dart';
import 'light_models.dart';

class LightStroke {
  final Path path;
  final double width;
  final bool fill;

  const LightStroke(this.path, this.width, this.fill);
}

final _pathTag = RegExp(r'<path\s([^>]*?)/?>');

String? _attr(String attrs, String name) =>
    RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(attrs)?.group(1);

/// Reads the EMV pictogram subset written by tools/lights/build.py: a
/// 100 × 100 viewBox of `<path d stroke-width [fill]>` elements.
List<LightStroke> parseLightSvg(String svg) {
  final out = <LightStroke>[];
  for (final m in _pathTag.allMatches(svg)) {
    final attrs = m.group(1)!;
    final d = _attr(attrs, 'd');
    if (d == null) continue;
    try {
      out.add(LightStroke(
        parseSvgPathData(d),
        double.tryParse(_attr(attrs, 'stroke-width') ?? '') ?? 5,
        _attr(attrs, 'fill') != null && _attr(attrs, 'fill') != 'none',
      ));
    } catch (e) {
      debugPrint('Pictogramme invalide : $e');
    }
  }
  return out;
}

final _cache = <String, Future<List<LightStroke>>>{};
final _loaded = <String, List<LightStroke>>{};

Future<List<LightStroke>> loadLightStrokes(String asset,
        [AssetBundle? bundle]) =>
    _cache[asset] ??= (bundle ?? rootBundle)
        .loadString(asset)
        .then((raw) => _loaded[asset] = parseLightSvg(raw))
        .catchError((Object _) => const <LightStroke>[]);

class LightPictogramPainter extends CustomPainter {
  final List<LightStroke> strokes;
  final Color color;

  LightPictogramPainter(this.strokes, {this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * k) / 2, (size.height - 100 * k) / 2);
    canvas.scale(k);
    for (final s in strokes) {
      final paint = Paint()
        ..color = color
        ..isAntiAlias = true;
      if (s.fill) {
        paint.style = PaintingStyle.fill;
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
      }
      canvas.drawPath(s.path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LightPictogramPainter old) =>
      old.strokes != strokes || old.color != color;
}

/// White blueprint strokes on a badge tinted with the light's colour.
class LightIcon extends StatelessWidget {
  final DashboardLight light;
  final double size;

  const LightIcon({super.key, required this.light, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final c = lightColor(light.color);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: 0.10), EmvColors.surface),
        border: Border.all(color: c, width: size > 80 ? 3 : 2),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: FutureBuilder<List<LightStroke>>(
        initialData: _loaded[light.iconAsset],
        future: loadLightStrokes(light.iconAsset),
        builder: (context, snap) => CustomPaint(
          painter: LightPictogramPainter(snap.data ?? const []),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class UrgencyBadge extends StatelessWidget {
  final int urgency;

  const UrgencyBadge({super.key, required this.urgency});

  static Color colorFor(int u) => switch (u) {
        >= 3 => const Color(0xFFE5484D),
        2 => const Color(0xFFFF8A00),
        _ => const Color(0xFF3DBE6B),
      };

  static IconData iconFor(int u) => switch (u) {
        >= 3 => Icons.front_hand,
        2 => Icons.build_circle_outlined,
        _ => Icons.check_circle_outline,
      };

  @override
  Widget build(BuildContext context) {
    final c = colorFor(urgency);
    return Container(
      key: Key('urgency-$urgency'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(iconFor(urgency), color: c, size: 20),
        const SizedBox(width: 8),
        Text(urgencyLabels[urgency] ?? '',
            style: TextStyle(color: c, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
