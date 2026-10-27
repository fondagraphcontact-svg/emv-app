import '../data.dart';
import '../models.dart';
import 'plate_lookup.dart';
import 'vin_decoder.dart';

/// What we know about the vehicle from a plate or a VIN, before matching it
/// against vehicles.json.
class VehicleQuery {
  final String make;
  final String model;
  final int? year;
  final String engine;
  final String fuel;
  final VehicleKind? kind;

  const VehicleQuery({
    required this.make,
    this.model = '',
    this.year,
    this.engine = '',
    this.fuel = '',
    this.kind,
  });

  factory VehicleQuery.fromPlate(PlateInfo p) => VehicleQuery(
      make: p.make, model: p.model, year: p.year, engine: p.engine, fuel: p.fuel);

  factory VehicleQuery.fromVin(VinInfo v) =>
      VehicleQuery(make: v.make ?? '', year: v.year, kind: v.wmi?.kind);
}

class VehicleCandidate {
  final Vehicle vehicle;
  final double score;

  const VehicleCandidate(this.vehicle, this.score);
}

class MatchResult {
  /// Best candidates first; several when the engine cannot be told apart.
  final List<VehicleCandidate> candidates;

  /// vehicles.json make name, null when the make is not in EMV.
  final String? make;

  const MatchResult(this.candidates, {this.make});

  bool get isEmpty => candidates.isEmpty;
  Vehicle? get single => candidates.length == 1 ? candidates.first.vehicle : null;
  List<Vehicle> get vehicles => [for (final c in candidates) c.vehicle];
}

const _makeAliases = {
  'vw': 'volkswagen',
  'mercedes': 'mercedes benz',
  'mercedes amg': 'mercedes benz',
  'daimler': 'mercedes benz',
  'citroen ds': 'ds',
  'ds automobiles': 'ds',
  'alfa': 'alfa romeo',
  'bmw motorrad': 'bmw motorrad',
  'harley': 'harley davidson',
  'mini bmw': 'mini',
  'smart mcc': 'smart',
  'vauxhall': 'opel',
};

/// Maps provider fuel labels (SIV "GO", "ES", "DIESEL", "ESSENCE"...) to the
/// vehicles.json vocabulary; empty when unknown.
String canonicalFuel(String raw) {
  final f = normalize(raw);
  bool has(String k) => f.contains(k);
  if (f.isEmpty) return '';
  if (_sivHybrid.contains(f) || has('hybrid')) return 'hybrid';
  if (f == 'el' || has('electri')) return 'electric';
  if (f == 'go' || has('diesel') || has('gazole') || has('gasoil')) {
    return 'diesel';
  }
  if (f == 'gp' || has('gpl') || has('lpg')) return 'lpg';
  if (f == 'es' || has('essence') || has('petrol') || has('gasoline')) {
    return 'petrol';
  }
  return '';
}

const _sivHybrid = {'ee', 'gl', 'ol', 'pe', 'ne', 'fl'};

/// The vehicles.json make whose normalised name best fits [raw].
String? resolveMake(AppData data, String raw, {VehicleKind? kind}) {
  var q = normalize(raw);
  if (q.isEmpty) return null;
  q = _makeAliases[q] ?? q;
  String? best;
  var bestLen = 0;
  for (final m in data.makes) {
    if (!kindMatches(m.kind, kind)) continue;
    final n = normalize(m.name);
    final hit = n == q || q.startsWith('$n ') || n.startsWith('$q ');
    if (!hit) continue;
    // Exact name first, then the longest name ("bmw motorrad" over "bmw").
    final len = n == q ? 1000 : n.length;
    if (len > bestLen) {
      best = m.name;
      bestLen = len;
    }
  }
  return best;
}

final _displacement = RegExp(r'\b(\d)[.,](\d)\b');
final _power = RegExp(r'\b(\d{2,3})\b');

List<String> _words(String s) =>
    normalize(s).split(' ').where((w) => w.isNotEmpty).toList();

// Words that only describe trim or body, never the model name.
const _modelNoise = {
  'sw', 'break', 'berline', 'coupe', 'cabriolet', 'phase', 'ph', 'estate',
  'grandtour', 'sport', 'tourer', 'van', 'societe', 'ctte',
};

double _score(Vehicle v, VehicleQuery q, String fuel) {
  var score = 0.0;
  final modelWords = _words(v.model);
  final queryModel = [
    for (final w in _words(q.model))
      if (!_modelNoise.contains(w)) w
  ];
  if (queryModel.isNotEmpty) {
    final hits = queryModel.where(modelWords.contains).length;
    if (hits == 0) return double.negativeInfinity;
    score += 3.0 * hits / queryModel.length;
  }

  if (q.year != null && v.yearFrom != null) {
    final to = v.yearTo ?? 9999;
    if (q.year! >= v.yearFrom! && q.year! <= to) {
      score += 3;
    } else {
      final gap = q.year! < v.yearFrom! ? v.yearFrom! - q.year! : q.year! - to;
      score -= gap.clamp(1, 5).toDouble() + 1;
    }
  }

  if (fuel.isNotEmpty && v.fuel.isNotEmpty) {
    score += fuel == v.fuel ? 2 : -4;
  }

  final engine = normalize(q.engine);
  if (engine.isNotEmpty) {
    final vEngine = normalize(v.engine);
    final d = _displacement.firstMatch(engine);
    if (d != null) {
      final cc = '${d.group(1)}.${d.group(2)}';
      score += containsToken(vEngine, cc) ? 2 : -2;
    }
    final powers = [
      for (final m in _power.allMatches(engine.replaceAll(_displacement, ' ')))
        m.group(1)!
    ];
    if (powers.isNotEmpty) {
      score += powers.any((p) => containsToken(vEngine, p)) ? 2 : -1;
    }
    final vWords = _words(v.engine);
    final noDpf = engine.contains('sans fap') || engine.contains('sans dpf');
    for (final w in _words(q.engine)) {
      if (noDpf && (w == 'fap' || w == 'dpf')) continue;
      if (w.length >= 3 && !RegExp(r'^\d').hasMatch(w) && vWords.contains(w)) {
        score += 0.5;
      }
    }
    if (noDpf) {
      if (v.dpf == true || vWords.contains('fap')) score -= 1;
      if (v.dpf == false) score += 0.5;
    }
    if (v.code.isNotEmpty && containsToken(engine, normalize(v.code))) {
      score += 3;
    }
  }
  return score;
}

/// Fuzzy match of plate or VIN data against vehicles.json. Returns the
/// top-scoring vehicles (ties kept so the user can pick the engine), at most
/// [limit].
MatchResult matchVehicles(AppData data, VehicleQuery q, {int limit = 20}) {
  final make = resolveMake(data, q.make, kind: q.kind) ??
      (q.kind == null ? null : resolveMake(data, q.make));
  if (make == null) return const MatchResult([]);
  final fuel = canonicalFuel(q.fuel);
  final scored = <VehicleCandidate>[
    for (final v in data.searchVehicles(normalize(make),
        kind: q.kind, limit: 1 << 30))
      if (v.make == make)
        if (_score(v, q, fuel) case final s when s.isFinite) VehicleCandidate(v, s)
  ]..sort((a, b) => b.score.compareTo(a.score));
  if (scored.isEmpty) return MatchResult(const [], make: make);
  final top = scored.first.score;
  final best = [
    for (final c in scored)
      if (c.score >= top - 0.25) c
  ];
  return MatchResult(best.take(limit).toList(), make: make);
}
