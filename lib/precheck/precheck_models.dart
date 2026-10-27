import 'dart:convert';

import '../models.dart';

enum PrecheckStatus { unchecked, ok, todo }

const precheckLevels = ['mineure', 'majeure', 'critique'];

/// 1 mineure, 2 majeure, 3 critique : même échelle que `EmvColors.severity`.
int precheckLevelRank(String level) => precheckLevels.indexOf(level) + 1;

class PrecheckFunction {
  final String id;
  final String name;
  final String intro;

  const PrecheckFunction(
      {required this.id, required this.name, this.intro = ''});
}

class PrecheckLevel {
  final String id;
  final String name;
  final String text;

  const PrecheckLevel({required this.id, required this.name, this.text = ''});
}

class PrecheckPoint {
  final String id;
  final String function;
  final VehicleKind kind;
  final String title;
  final String check;
  final String level;
  final String advice;
  final String? part;
  final String? guide;
  final String? light;
  final List<String> fuel;

  const PrecheckPoint({
    required this.id,
    required this.function,
    required this.kind,
    required this.title,
    required this.check,
    required this.level,
    required this.advice,
    this.part,
    this.guide,
    this.light,
    this.fuel = const [],
  });

  factory PrecheckPoint.fromJson(Map<String, dynamic> j) => PrecheckPoint(
        id: j['id'] as String,
        function: j['function'] as String,
        kind: parseKind(j['kind']),
        title: j['title'] as String,
        check: j['check'] as String? ?? '',
        level: j['level'] as String,
        advice: j['advice'] as String? ?? '',
        part: j['part'] as String?,
        guide: j['guide'] as String?,
        light: j['light'] as String?,
        fuel: [for (final f in (j['fuel'] as List? ?? const [])) '$f'],
      );

  int get rank => precheckLevelRank(level);

  /// Aucun carburant listé = tous ; les hybrides diesel comptent comme diesel.
  bool appliesTo(Vehicle? v) {
    if (v == null) return true;
    if (!kindMatches(kind, v.kind)) return false;
    if (fuel.isEmpty || fuel.contains(v.fuel)) return true;
    return v.isDiesel && fuel.contains('diesel');
  }
}

class PrecheckData {
  final String disclaimer;
  final List<PrecheckFunction> functions;
  final List<PrecheckLevel> levels;
  final List<PrecheckPoint> points;

  const PrecheckData({
    required this.disclaimer,
    required this.functions,
    required this.levels,
    required this.points,
  });

  factory PrecheckData.fromJson(Map<String, dynamic> j) => PrecheckData(
        disclaimer: j['disclaimer'] as String? ?? '',
        functions: [
          for (final f in j['functions'] as List)
            PrecheckFunction(
              id: f['id'] as String,
              name: f['name'] as String,
              intro: f['intro'] as String? ?? '',
            ),
        ],
        levels: [
          for (final l in j['levels'] as List)
            PrecheckLevel(
              id: l['id'] as String,
              name: l['name'] as String,
              text: l['text'] as String? ?? '',
            ),
        ],
        points: [
          for (final p in j['points'] as List)
            PrecheckPoint.fromJson(p as Map<String, dynamic>),
        ],
      );

  List<PrecheckPoint> pointsFor(Vehicle? v) =>
      [for (final p in points) if (p.appliesTo(v)) p];

  PrecheckLevel? level(String id) {
    for (final l in levels) {
      if (l.id == id) return l;
    }
    return null;
  }
}

PrecheckData parsePrecheck(String raw) =>
    PrecheckData.fromJson(jsonDecode(raw) as Map<String, dynamic>);

/// Synthèse d'un véhicule : points « à voir » par niveau, OK, non vérifiés.
class PrecheckSummary {
  final int total;
  final int ok;
  final Map<String, int> todoByLevel;

  const PrecheckSummary(
      {required this.total, required this.ok, required this.todoByLevel});

  factory PrecheckSummary.of(
      List<PrecheckPoint> points, PrecheckStatus Function(String id) status) {
    var ok = 0;
    final todo = {for (final l in precheckLevels) l: 0};
    for (final p in points) {
      switch (status(p.id)) {
        case PrecheckStatus.ok:
          ok++;
        case PrecheckStatus.todo:
          todo[p.level] = (todo[p.level] ?? 0) + 1;
        case PrecheckStatus.unchecked:
          break;
      }
    }
    return PrecheckSummary(total: points.length, ok: ok, todoByLevel: todo);
  }

  int get todo => todoByLevel.values.fold(0, (a, b) => a + b);
  int get unchecked => total - ok - todo;
}

/// Contenu de la section PDF : synthèse + points « à voir », critiques d'abord.
class PrecheckReport {
  final PrecheckSummary summary;
  final List<({String function, PrecheckPoint point})> todo;

  const PrecheckReport({required this.summary, required this.todo});

  factory PrecheckReport.of(PrecheckData data, Vehicle? v,
      PrecheckStatus Function(String id) status) {
    final points = data.pointsFor(v);
    final names = {for (final f in data.functions) f.id: f.name};
    final todo = [
      for (final p in points)
        if (status(p.id) == PrecheckStatus.todo)
          (function: names[p.function] ?? p.function, point: p)
    ]..sort((a, b) => b.point.rank.compareTo(a.point.rank));
    return PrecheckReport(
        summary: PrecheckSummary.of(points, status), todo: todo);
  }

  bool get isEmpty => summary.ok == 0 && summary.todo == 0;
}
