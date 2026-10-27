import 'dart:convert';

import '../models.dart';

List<String> _strings(dynamic v) =>
    v is List ? [for (final e in v) e.toString()] : const [];

class GuideStep {
  final String id;
  final String question;
  final String check;
  final String yes;
  final String no;

  /// Absent dans le JSON : « Je ne sais pas » suit alors la branche `no`,
  /// qui mène vers la vérification suivante sans conclure trop vite.
  final String? unknown;
  final List<String> parts;
  final List<String> dtc;

  const GuideStep({
    required this.id,
    required this.question,
    required this.check,
    required this.yes,
    required this.no,
    this.unknown,
    this.parts = const [],
    this.dtc = const [],
  });

  String get unknownTarget => unknown ?? no;

  factory GuideStep.fromJson(Map<String, dynamic> j) => GuideStep(
        id: j['id'] as String,
        question: j['q'] as String? ?? '',
        check: j['check'] as String? ?? '',
        yes: j['yes'] as String,
        no: j['no'] as String,
        unknown: j['unknown'] as String?,
        parts: _strings(j['parts']),
        dtc: _strings(j['dtc']),
      );
}

class GuideResult {
  final String id;
  final String title;
  final String text;
  final List<String> parts;
  final List<String> dtc;
  final List<String> views;
  final bool pro;

  const GuideResult({
    required this.id,
    required this.title,
    required this.text,
    this.parts = const [],
    this.dtc = const [],
    this.views = const [],
    this.pro = false,
  });

  factory GuideResult.fromJson(Map<String, dynamic> j) => GuideResult(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        parts: _strings(j['parts']),
        dtc: _strings(j['dtc']),
        views: _strings(j['views']),
        pro: j['pro'] == true,
      );
}

class Guide {
  final String id;
  final String title;
  final String summary;
  final String category;
  final VehicleKind kind;
  final List<String> fuel;
  final int difficulty;
  final List<String> tools;
  final String time;
  final List<String> safety;
  final List<String> stopIf;
  final List<String> requires;
  final List<GuideStep> steps;
  final List<GuideResult> results;

  final Map<String, GuideStep> _steps;
  final Map<String, GuideResult> _results;

  Guide({
    required this.id,
    required this.title,
    this.summary = '',
    this.category = '',
    this.kind = VehicleKind.both,
    this.fuel = const [],
    this.difficulty = 1,
    this.tools = const [],
    this.time = '',
    this.safety = const [],
    this.stopIf = const [],
    this.requires = const [],
    required this.steps,
    required this.results,
  })  : _steps = {for (final s in steps) s.id: s},
        _results = {for (final r in results) r.id: r};

  GuideStep? get first => steps.isEmpty ? null : steps.first;
  GuideStep? step(String id) => _steps[id];
  GuideResult? result(String id) => _results[id];

  factory Guide.fromJson(Map<String, dynamic> j) => Guide(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        category: j['category'] as String? ?? '',
        kind: parseKind(j['kind']),
        fuel: _strings(j['fuel']),
        difficulty: (j['difficulty'] as num?)?.toInt() ?? 1,
        tools: _strings(j['tools']),
        time: j['time'] as String? ?? '',
        safety: _strings(j['safety']),
        stopIf: _strings(j['stopIf']),
        requires: _strings(j['requires']),
        steps: [
          for (final s in (j['steps'] as List? ?? const []))
            GuideStep.fromJson(s as Map<String, dynamic>)
        ],
        results: [
          for (final r in (j['results'] as List? ?? const []))
            GuideResult.fromJson(r as Map<String, dynamic>)
        ],
      );

  /// Sans véhicule, tout est proposé ; sinon on écarte les guides d'un autre
  /// type, d'une autre énergie ou exigeant un équipement absent (FAP).
  bool appliesTo(Vehicle? v) {
    if (v == null) return true;
    if (!kindMatches(kind, v.kind)) return false;
    // Hybride et GPL gardent un moteur essence : mêmes pannes côté thermique.
    final vFuel = const {'hybrid', 'lpg'}.contains(v.fuel) ? 'petrol' : v.fuel;
    if (fuel.isNotEmpty && vFuel.isNotEmpty && !fuel.contains(vFuel)) {
      return false;
    }
    if (requires.contains('dpf') && !v.mayHaveDpf) return false;
    return true;
  }
}

List<Guide> parseGuideList(String raw) => [
      for (final g in jsonDecode(raw) as List)
        Guide.fromJson(g as Map<String, dynamic>)
    ];

const guideCategoryLabels = {
  'start': 'Démarrage',
  'electrical': 'Électricité',
  'engine': 'Moteur',
  'cooling': 'Refroidissement',
  'brakes': 'Freinage',
  'chassis': 'Train roulant',
  'transmission': 'Transmission',
  'comfort': 'Confort',
};

String guideCategoryLabel(String c) => guideCategoryLabels[c] ?? c;
