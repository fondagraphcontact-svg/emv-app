import 'dart:convert';

enum BotActionType { openView, openViewId, openDtc, openPart, selectVehicle, openGuide, openLight, openPrecheck }

class BotAction {
  final String label;
  final BotActionType type;
  final String payload;
  final VehicleEntry? vehicle;

  const BotAction(this.label, this.type, this.payload, {this.vehicle});

  @override
  String toString() => 'BotAction(${type.name}, $payload)';
}

class BotReply {
  final String text;
  final List<String> checks;
  final List<BotAction> actions;
  final String? safety;
  final List<String> suggestions;
  final String? intentId;
  final String? dtcCode;
  final String? partSlug;
  final List<VehicleEntry> vehicles;
  final VehicleCtx? ctx;

  const BotReply({
    required this.text,
    this.checks = const [],
    this.actions = const [],
    this.safety,
    this.suggestions = const [],
    this.intentId,
    this.dtcCode,
    this.partSlug,
    this.vehicles = const [],
    this.ctx,
  });

  VehicleEntry? get detectedVehicle => vehicles.isEmpty ? null : vehicles.first;
}

class VehicleCtx {
  final String? fuel;
  final String? family;
  final bool? dpf;
  final String? make;
  final String? model;
  final String? engine;
  final String? kind;

  const VehicleCtx({this.fuel, this.family, this.dpf, this.make, this.model, this.engine, this.kind});

  factory VehicleCtx.fromEntry(VehicleEntry v) => VehicleCtx(
      fuel: v.fuel, family: v.family, dpf: v.dpf, make: v.make, model: v.model, engine: v.engine, kind: v.kind);

  String? get effectiveKind {
    if (kind != null) return kind;
    final f = family;
    if (f == null) return null;
    return (f.startsWith('moto') || f.startsWith('scooter')) ? 'moto' : 'car';
  }

  bool get dieselEngine => fuel == 'diesel' || (family?.startsWith('diesel') ?? false);

  // Diesel hybrids report fuel 'hybrid' but must be handled as diesel + electric.
  bool fuelMatches(Iterable<String> allowed) {
    if (fuel == 'hybrid' && dieselEngine) {
      return allowed.isEmpty || allowed.any(const {'diesel', 'hybrid', 'electric'}.contains);
    }
    return fuelCompatible(fuel, allowed);
  }

  // null = the engine may have a DPF but the data does not say.
  bool? get hasDpf {
    if (dpf != null) return dpf;
    if (dieselEngine) return null;
    if (fuel == null && family == null && effectiveKind != 'moto') return null;
    return false;
  }

  String get label {
    final name = [make, model, engine].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final tags = <String>[];
    if (fuel != null) tags.add(botFuelLabel(fuel!));
    if (dieselEngine && dpf != null) tags.add(dpf! ? 'avec FAP' : 'sans FAP');
    if (tags.isEmpty) return name;
    return name.isEmpty ? tags.join(', ') : '$name (${tags.join(', ')})';
  }
}

class VehicleEntry {
  final String make;
  final String model;
  final String engine;
  final String kind;
  final String fuel;
  final String family;
  final bool? dpf;
  final String? code;
  final int? yearFrom;
  final int? yearTo;

  const VehicleEntry({
    required this.make,
    required this.model,
    required this.engine,
    required this.fuel,
    required this.family,
    this.kind = 'car',
    this.dpf,
    this.code,
    this.yearFrom,
    this.yearTo,
  });

  String get id => '$make|$model|$engine';
  String get label => '$make $model $engine';

  static List<VehicleEntry> listFromJson(Map<String, dynamic> json) {
    final out = <VehicleEntry>[];
    for (final m in (json['makes'] as List? ?? const [])) {
      final make = m as Map<String, dynamic>;
      for (final mo in (make['models'] as List? ?? const [])) {
        final model = mo as Map<String, dynamic>;
        final years = (model['years'] as List?)?.cast<num>();
        for (final e in (model['engines'] as List? ?? const [])) {
          final eng = e as Map<String, dynamic>;
          out.add(VehicleEntry(
            make: make['name'] as String,
            model: model['name'] as String,
            engine: eng['name'] as String,
            kind: (model['kind'] ?? make['kind'] ?? 'car') as String,
            fuel: (eng['fuel'] ?? 'petrol') as String,
            family: (eng['family'] ?? '') as String,
            dpf: eng['dpf'] as bool?,
            code: eng['code'] as String?,
            yearFrom: years != null && years.isNotEmpty ? years.first.toInt() : null,
            yearTo: years != null && years.length > 1 ? years[1].toInt() : null,
          ));
        }
      }
    }
    return out;
  }
}

class PartInfo {
  final String slug;
  final String name;
  final String role;
  final String wear;
  final List<String> dtc;
  final String section;
  final String group;
  final String groupKind;
  final List<String> fuel;
  final String? kind;

  const PartInfo({
    required this.slug,
    required this.name,
    this.role = '',
    this.wear = '',
    this.dtc = const [],
    this.section = '',
    this.group = '',
    this.groupKind = 'both',
    this.fuel = const [],
    this.kind,
  });

  static List<PartInfo> listFromTree(List<dynamic> tree) {
    final out = <PartInfo>[];
    for (final s in tree) {
      final sec = s as Map<String, dynamic>;
      for (final c in (sec['children'] as List? ?? const [])) {
        final sub = c as Map<String, dynamic>;
        for (final p in (sub['parts'] as List? ?? const [])) {
          final part = p as Map<String, dynamic>;
          out.add(PartInfo(
            slug: part['slug'] as String,
            name: part['name'] as String,
            role: (part['role'] ?? '') as String,
            wear: (part['wear'] ?? '') as String,
            dtc: _strings(part['dtc']),
            section: sub['slug'] as String,
            group: sec['slug'] as String,
            groupKind: (sec['kind'] ?? 'both') as String,
            fuel: _strings(part['fuel']),
            kind: part['kind'] as String?,
          ));
        }
      }
    }
    return out;
  }
}

class DtcInfo {
  final String code;
  final String title;
  final String system;
  final List<String> symptoms;
  final List<String> causes;
  final List<String> diagnostic;
  final List<String> parts;
  final List<String> fuel;
  final int severity;

  const DtcInfo({
    required this.code,
    required this.title,
    this.system = '',
    this.symptoms = const [],
    this.causes = const [],
    this.diagnostic = const [],
    this.parts = const [],
    this.fuel = const [],
    this.severity = 1,
  });

  factory DtcInfo.fromJson(Map<String, dynamic> j) => DtcInfo(
        code: (j['code'] as String).toUpperCase(),
        title: (j['title'] ?? '') as String,
        system: (j['system'] ?? '') as String,
        symptoms: _strings(j['symptoms']),
        causes: _strings(j['causes']),
        diagnostic: _strings(j['diagnostic']),
        parts: _strings(j['parts']),
        fuel: _strings(j['fuel']),
        severity: (j['severity'] as num?)?.toInt() ?? 1,
      );
}

class KbIntent {
  final String id;
  final List<String> patterns;
  final List<String> negatedPatterns;
  final List<String> fuel;
  final String? kind;
  final List<String> requires;
  final double priority;
  final String answer;
  final List<String> checks;
  final String? safety;
  final List<String> parts;
  final List<String> dtc;
  final List<String> views;
  final String section;
  final String? guide;

  /// `guide` peut aussi être un objet `{"diesel": id, "petrol": id}` quand le
  /// guide dépend de l'énergie du véhicule.
  final Map<String, String> guideByFuel;

  const KbIntent({
    required this.id,
    required this.patterns,
    required this.answer,
    this.negatedPatterns = const [],
    this.fuel = const [],
    this.kind,
    this.requires = const [],
    this.priority = 0,
    this.checks = const [],
    this.safety,
    this.parts = const [],
    this.dtc = const [],
    this.views = const [],
    this.section = '',
    this.guide,
    this.guideByFuel = const {},
  });

  String? guideFor(String? fuel) =>
      guide ?? guideByFuel[fuel == 'hybrid' || fuel == 'lpg' ? 'petrol' : fuel];

  factory KbIntent.fromJson(Map<String, dynamic> j) => KbIntent(
        id: j['id'] as String,
        patterns: _strings(j['patterns']),
        negatedPatterns: _strings(j['negated_patterns']),
        fuel: _strings(j['fuel']),
        kind: j['kind'] as String?,
        requires: _strings(j['requires']),
        priority: (j['priority'] as num?)?.toDouble() ?? 0,
        answer: (j['answer'] ?? '') as String,
        checks: _strings(j['checks']),
        safety: j['safety'] as String?,
        parts: _strings(j['parts']),
        dtc: _strings(j['dtc']).map((c) => c.toUpperCase()).toList(),
        views: _strings(j['views']),
        section: (j['section'] ?? '') as String,
        guide: j['guide'] is String ? j['guide'] as String : null,
        guideByFuel: j['guide'] is Map
            ? {for (final e in (j['guide'] as Map).entries) '${e.key}': '${e.value}'}
            : const {},
      );
}

List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];

String botFuelLabel(String fuel) =>
    const {
      'petrol': 'essence',
      'diesel': 'diesel',
      'hybrid': 'hybride',
      'electric': 'électrique',
      'lpg': 'GPL',
    }[fuel] ??
    fuel;

bool fuelCompatible(String? ctxFuel, Iterable<String> allowed) {
  if (ctxFuel == null || allowed.isEmpty) return true;
  for (final a in allowed) {
    if (a == ctxFuel) return true;
    if (a == 'petrol' && (ctxFuel == 'hybrid' || ctxFuel == 'lpg')) return true;
    if (a == 'electric' && ctxFuel == 'hybrid') return true;
  }
  return false;
}

class TextTools {
  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'œ': 'oe', 'æ': 'ae', 'ß': 'ss',
  };

  static final _decimal = RegExp(r'(\d)[.,](\d)');
  static final _nonWord = RegExp('[^a-z0-9\u0001]+');
  static final _displacementGlued = RegExp(r'(\d\.\d)([a-z])');
  static final _digit = RegExp(r'\d');

  static String normalize(String input) {
    final sb = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      sb.write(_accents[ch] ?? ch);
    }
    var s = sb.toString().replaceAllMapped(_decimal, (m) => '${m[1]}\u0001${m[2]}');
    s = s.replaceAll(_nonWord, ' ').replaceAll('\u0001', '.');
    s = s.replaceAllMapped(_displacementGlued, (m) => '${m[1]} ${m[2]}');
    return s.trim();
  }

  static const stopwords = {
    'le', 'la', 'les', 'l', 'd', 'de', 'du', 'des', 'un', 'une', 'et', 'a', 'au', 'aux', 'en',
    'ma', 'mon', 'mes', 'ta', 'ton', 'tes', 'sa', 'son', 'ses', 'notre', 'votre', 'vos', 'nos', 'leur',
    'il', 'elle', 'ils', 'elles', 'on', 'je', 'j', 'tu', 'vous', 'nous', 'me', 'm', 'te', 't', 'se', 's',
    'y', 'est', 'ai', 'as', 'avez', 'ont', 'suis', 'sont', 'etre', 'avoir', 'ce', 'c', 'cet', 'cette',
    'ces', 'ca', 'qui', 'que', 'qu', 'quoi', 'pourquoi', 'dans', 'sur', 'pour', 'par', 'avec', 'ou',
    'mais', 'donc', 'car', 'ne', 'n', 'pas', 'plus', 'tres', 'bien', 'peu', 'fait', 'faire', 'alors',
    'aussi', 'toujours', 'parfois', 'depuis', 'encore', 'tout', 'tous', 'voiture', 'vehicule', 'auto',
    'bagnole', 'svp', 'stp', 'quelle', 'quel', 'quels', 'quelles',
  };

  static String stem(String t) {
    if (t.length <= 3 || t.contains(_digit)) return t;
    var s = t;
    if (s.endsWith('s') || s.endsWith('x')) s = s.substring(0, s.length - 1);
    if (s.length > 5 && s.endsWith('ent')) s = s.substring(0, s.length - 2);
    if (s.length > 5 && (s.endsWith('er') || s.endsWith('ez'))) s = s.substring(0, s.length - 2);
    while (s.length > 3 && s.endsWith('e')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static List<String> words(String input) {
    final n = normalize(input);
    return n.isEmpty ? const [] : n.split(' ');
  }

  static List<String> tokens(String input) =>
      words(input).where((w) => !stopwords.contains(w)).map(stem).toList();

  static const negationWords = {'ne', 'n', 'pas', 'plus', 'jamais', 'sans', 'aucun', 'aucune', 'rien'};
  static const _negationClosers = {'pas', 'plus', 'jamais', 'rien', 'point', 'guere', 'aucun', 'aucune'};
  static const _forwardNegators = {'sans', 'aucun', 'aucune', 'aucuns', 'aucunes'};
  static const _partitive = {'de', 'd', 'du', 'des'};
  static const _clauseConnectors = {'mais', 'et', 'puis'};
  static final _clauseSeparator = RegExp(r'[;!?:\n]|(?<!\d)[.,]|[.,](?!\d)');

  /// Tokens of [input] (as [tokens]) with, for each, whether it is negated in its clause.
  static ({List<String> tokens, List<bool> negated}) analyze(String input) {
    final toks = <String>[];
    final neg = <bool>[];
    var clause = <String>[];
    void flush() {
      final flags = _negationScope(clause);
      for (var i = 0; i < clause.length; i++) {
        if (stopwords.contains(clause[i])) continue;
        toks.add(stem(clause[i]));
        neg.add(flags[i]);
      }
      clause = <String>[];
    }

    for (final part in input.split(_clauseSeparator)) {
      for (final w in words(part)) {
        if (_clauseConnectors.contains(w)) {
          flush();
        } else {
          clause.add(w);
        }
      }
      flush();
    }
    return (tokens: toks, negated: neg);
  }

  // "ne X pas" negates X (or the next content words after a bare copula: "n'est pas à plat");
  // "pas de X", "sans X", "aucun X" and a clause-initial "plus de X" negate the next two content words;
  // a bare "X pas" (spoken French) negates the preceding content word.
  static List<bool> _negationScope(List<String> w) {
    final neg = List<bool>.filled(w.length, false);
    bool content(int k) => !stopwords.contains(w[k]) && !negationWords.contains(w[k]);
    void forward(int from) {
      var n = 0;
      for (var k = from; k < w.length && n < 2; k++) {
        if (negationWords.contains(w[k])) break;
        if (content(k)) {
          neg[k] = true;
          n++;
        }
      }
    }

    var i = 0;
    while (i < w.length) {
      final x = w[i];
      if (x == 'ne' || x == 'n') {
        var j = i + 1;
        while (j < w.length && !_negationClosers.contains(w[j])) {
          j++;
        }
        if (j < w.length) {
          var verb = false;
          for (var k = i + 1; k < j; k++) {
            neg[k] = true;
            if (content(k)) verb = true;
          }
          if (!verb || _forwardNegators.contains(w[j]) || (j + 1 < w.length && _partitive.contains(w[j + 1]))) {
            forward(j + 1);
          }
          i = j + 1;
          continue;
        }
      } else if (x == 'pas' || x == 'jamais' || x == 'plus') {
        var prev = i - 1;
        while (prev >= 0 && !content(prev)) {
          prev--;
        }
        final partitive = i + 1 < w.length && _partitive.contains(w[i + 1]);
        if (x == 'plus') {
          if (partitive && prev < 0) forward(i + 1);
        } else if (partitive || prev < 0) {
          forward(i + 1);
        } else {
          neg[prev] = true;
        }
      } else if (_forwardNegators.contains(x)) {
        forward(i + 1);
      }
      i++;
    }
    return neg;
  }

  static int levenshtein(String a, String b, int max) {
    if ((a.length - b.length).abs() > max) return max + 1;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      var rowMin = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > max) return max + 1;
      prev = cur;
    }
    return prev[b.length];
  }

  // Real words one typo apart that must never be confused ("voyant moteur" ≠ "volant moteur").
  static const _falseFriends = {'voyant', 'volant'};

  static bool fuzzyEq(String a, String b) {
    if (a == b) return true;
    if (_falseFriends.contains(a) && _falseFriends.contains(b)) return false;
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    if (shorter.length < 5 || shorter.contains(_digit)) return false;
    if (longer.startsWith(shorter)) return true;
    final max = shorter.length >= 9 ? 2 : 1;
    return levenshtein(a, b, max) <= max;
  }
}

class _Pattern {
  final List<String> tokens;
  final List<bool> negated;
  final double weight;
  _Pattern._(this.tokens, this.negated) : weight = tokens.fold(0.0, (s, t) => s + (t.length >= 3 ? 1.0 : 0.5));
  factory _Pattern(String raw) {
    final a = TextTools.analyze(raw);
    return _Pattern._(a.tokens, a.negated);
  }
}

class _ScoredIntent {
  final KbIntent intent;
  final double raw;
  final double score;
  _ScoredIntent(this.intent, this.raw, this.score);
}

class _PartPhrase {
  final List<String> tokens;
  final List<String> slugs;
  _PartPhrase(this.tokens, this.slugs);
}

class _ModelKey {
  final List<String> makeTokens;
  final String main;
  final List<String> rest;
  final List<VehicleEntry> engines;
  _ModelKey(this.makeTokens, this.main, this.rest, this.engines);
}

class _VehicleDetection {
  final List<VehicleEntry> candidates;
  final bool engineMatched;
  _VehicleDetection(this.candidates, this.engineMatched);
}

class ChatbotEngine {
  final List<KbIntent> intents;
  final Map<String, PartInfo> parts;
  final Map<String, DtcInfo> dtcs;
  final List<VehicleEntry> vehicles;

  Map<String, List<({String id, String name, String kind})>> lightsByIntent = {};

  final Map<String, List<_Pattern>> _patterns = {};
  final Map<String, List<_Pattern>> _negatedPatterns = {};
  final List<_PartPhrase> _partPhrases = [];
  final List<_ModelKey> _models = [];

  static const minScore = 1.0;

  static const fallbackSuggestions = [
    'Voyant moteur allumé',
    'Ne démarre pas',
    'Batterie à plat',
    'Perte de puissance',
    'Surchauffe moteur',
    'Fumée noire',
  ];

  static const viewLabels = {
    'fuse-box-generic': 'Boîte à fusibles',
    'wiring-starting': 'Schéma démarrage',
    'wiring-charging': 'Schéma charge',
    'wiring-lighting': 'Schéma éclairage',
    'wiring-fuel-pump': 'Schéma pompe à carburant',
    'wiring-cooling-fan': 'Schéma motoventilateur',
    'wiring-ignition-petrol': 'Schéma allumage',
    'wiring-glow-plugs-diesel': 'Schéma préchauffage',
    'wiring-abs': 'Schéma ABS',
    'wiring-horn-wipers': 'Schéma klaxon / essuie-glaces',
    'wiring-moto-charging': 'Schéma charge moto',
    'wiring-moto-starting': 'Schéma démarrage moto',
  };

  static const partAliases = <String, List<String>>{
    'bougie': ['spark-plug', 'glow-plug'],
    'bougie prechauffage': ['glow-plug'],
    'egr': ['egr-valve'],
    'debitmetre': ['maf-sensor'],
    'debimetre': ['maf-sensor'],
    'capteur pmh': ['crankshaft-position-sensor'],
    'pmh': ['crankshaft-position-sensor'],
    'ventilo': ['cooling-fan'],
    'ventilateur': ['cooling-fan'],
    'turbo': ['turbocharger'],
    'durite turbo': ['intercooler-hose'],
    'fusible': ['fuse-ato'],
    'klaxon': ['horn'],
    'phare': ['headlamp'],
    'pneu': ['tyre'],
    'roulement': ['wheel-bearing'],
    'embrayage': ['clutch-disc'],
    'bimasse': ['dual-mass-flywheel'],
    'sonde lambda': ['lambda-sensor-upstream'],
    'pot catalytique': ['catalytic-converter'],
    'pompe injection': ['high-pressure-pump'],
    'pompe hp': ['high-pressure-pump'],
    'compresseur clim': ['ac-compressor'],
    'filtre pollen': ['cabin-filter'],
    'abs': ['abs-module'],
    'calculateur': ['ecu'],
    'ecu': ['ecu'],
    'chaine moto': ['drive-chain'],
    'kit chaine': ['drive-chain'],
    'kit distribution': ['timing-belt'],
    'adblue': ['adblue-injector'],
    'spi fourche': ['fork-seal'],
    'cardan': ['driveshaft'],
    'plaquette': ['brake-pad'],
    'disque frein': ['brake-disc'],
    'filtre gasoil': ['fuel-filter'],
    'filtre gazole': ['fuel-filter'],
    'filtre essence': ['fuel-filter'],
  };

  static const _petrolOnlyParts = {'spark-plug', 'ignition-coil', 'spark-plug-wire', 'cdi-unit', 'secondary-air-pump'};
  static const _dieselOnlyParts = {
    'glow-plug', 'glow-plug-control-unit', 'dpf', 'dpf-pressure-sensor', 'scr-catalyst', 'adblue-injector', 'nox-sensor'
  };
  static const _dpfParts = {'dpf', 'dpf-pressure-sensor'};
  static const _petrolSections = {'petrol-system', 'carburation', 'ignition-system'};
  static const _dieselSections = {'diesel-system'};
  static const _hvSections = {'hv-components'};
  static const _combustionGroups = {'engine', 'air-intake', 'fuel', 'ignition', 'exhaust'};
  static const _combustionSections = {'clutch', 'timing'};
  static const _motoSections = {'suspension-moto', 'final-drive-moto'};
  static const _motoParts = {'wet-clutch-pack', 'stator', 'rectifier-regulator', 'regulator-rectifier', 'cdi-unit'};
  static const _dpfCodes = {'P2002', 'P2003', 'P242F'};

  static const _commonModelWords = {
    'up', 'ka', 'one', 'express', 'master', 'partner', 'expert', 'boxer', 'ami', 'rapid', 'espace',
    'trafic', 'combo', 'spring', 'jogger', 'superb', 'leon', 'adam', 'logan', 'puma', 'focus', 'life',
    'city', 'line', 'sport', 'classic', 'cross', 'tour', 'ds',
  };
  static const _roman = {'i': '1', 'ii': '2', 'iii': '3', 'iv': '4', 'v': '5', 'vi': '6', 'vii': '7', 'viii': '8'};

  static final dtcRegex = RegExp(r'(?<![A-Z0-9])[PBCU][0-9A-F]{4}(?![A-Z0-9])');

  ChatbotEngine({
    required this.intents,
    List<PartInfo> parts = const [],
    List<DtcInfo> dtcs = const [],
    this.vehicles = const [],
  })  : parts = {for (final p in parts) p.slug: p},
        dtcs = {for (final d in dtcs) d.code: d} {
    for (final i in intents) {
      _patterns[i.id] = [for (final p in i.patterns) _Pattern(p)].where((p) => p.tokens.isNotEmpty).toList();
      _negatedPatterns[i.id] =
          [for (final p in i.negatedPatterns) _Pattern(p)].where((p) => p.tokens.isNotEmpty).toList();
    }
    _buildPartIndex();
    _buildVehicleIndex();
  }

  factory ChatbotEngine.fromJson({
    required List<dynamic> kb,
    List<dynamic>? tree,
    List<dynamic>? dtc,
    Map<String, dynamic>? vehicles,
  }) =>
      ChatbotEngine(
        intents: [for (final k in kb) KbIntent.fromJson(k as Map<String, dynamic>)],
        parts: tree == null ? const [] : PartInfo.listFromTree(tree),
        dtcs: [for (final d in dtc ?? const []) DtcInfo.fromJson(d as Map<String, dynamic>)],
        vehicles: vehicles == null ? const [] : VehicleEntry.listFromJson(vehicles),
      );

  factory ChatbotEngine.fromJsonStrings({
    required String kb,
    String? tree,
    String? dtc,
    String? vehicles,
  }) =>
      ChatbotEngine.fromJson(
        kb: jsonDecode(kb) as List<dynamic>,
        tree: tree == null ? null : jsonDecode(tree) as List<dynamic>,
        dtc: dtc == null ? null : jsonDecode(dtc) as List<dynamic>,
        vehicles: vehicles == null ? null : jsonDecode(vehicles) as Map<String, dynamic>,
      );

  void _buildPartIndex() {
    final byPhrase = <String, Set<String>>{};
    void add(String phrase, String slug) {
      final t = TextTools.tokens(phrase);
      if (t.isEmpty) return;
      byPhrase.putIfAbsent(t.join(' '), () => <String>{}).add(slug);
    }

    const ignoredParenthetical = {'moto', 'orange', 'abs', 'ato'};
    final paren = RegExp(r'\(([^)]*)\)');
    for (final p in parts.values) {
      final base = p.name.replaceAll(paren, ' ');
      add(base.replaceAll('/', ' '), p.slug);
      if (base.contains('/')) {
        for (final side in base.split('/')) {
          if (side.trim().length >= 6) add(side, p.slug);
        }
      }
      for (final m in paren.allMatches(p.name)) {
        final w = TextTools.words(m[1]!);
        if (w.length == 1 && !ignoredParenthetical.contains(w.first)) add(m[1]!, p.slug);
      }
    }
    partAliases.forEach((alias, slugs) {
      for (final s in slugs) {
        if (parts.isEmpty || parts.containsKey(s)) add(alias, s);
      }
    });
    byPhrase.forEach((k, v) => _partPhrases.add(_PartPhrase(k.split(' '), v.toList())));
    _partPhrases.sort((a, b) => b.tokens.length.compareTo(a.tokens.length));
  }

  static List<String> _vehicleWords(String s) => TextTools.words(s).map((w) => _roman[w] ?? w).toList();

  void _buildVehicleIndex() {
    final map = <String, _ModelKey>{};
    for (final v in vehicles) {
      final key = '${v.make}|${v.model}';
      final existing = map[key];
      if (existing != null) {
        existing.engines.add(v);
        continue;
      }
      final mw = _vehicleWords(v.model);
      if (mw.isEmpty) continue;
      map[key] = _ModelKey(_vehicleWords(v.make), mw.first, mw.sublist(1), [v]);
    }
    _models.addAll(map.values);
  }

  static bool _vehTokEq(String a, String b) {
    if (a == b) return true;
    if (a.length < 5 || b.length < 5) return false;
    return TextTools.fuzzyEq(a, b);
  }

  _VehicleDetection? _detectVehicle(String message) {
    if (_models.isEmpty) return null;
    final words = _vehicleWords(message);
    if (words.isEmpty) return null;
    final norm = words.join(' ');
    bool has(String t) => words.any((w) => _vehTokEq(w, t));
    final years = words.map(int.tryParse).whereType<int>().where((y) => y >= 1950 && y <= 2035).toList();
    final saysNoDpf = RegExp(r'\b(sans|pas de) fap\b').hasMatch(norm);
    final saysDpf = !saysNoDpf && words.contains('fap');
    final saysDiesel = words.any(const {'diesel', 'gasoil', 'gazole'}.contains);
    final saysPetrol = words.contains('essence');

    final scored = <MapEntry<VehicleEntry, double>>[];
    var anyEngine = false;
    for (final m in _models) {
      if (!has(m.main)) continue;
      final makeHit = m.makeTokens.isNotEmpty && m.makeTokens.every(has);
      final numericMain = int.tryParse(m.main);
      if (!makeHit && (m.main.length < 2 || _commonModelWords.contains(m.main))) continue;
      if (!makeHit && numericMain != null && (m.main.length < 3 || years.contains(numericMain))) continue;
      var modelScore = 3.0 + (makeHit ? 2 : 0);
      for (final r in m.rest) {
        if (has(r)) modelScore += 1;
      }
      for (final e in m.engines) {
        var s = modelScore;
        if (years.isNotEmpty && e.yearFrom != null) {
          final to = e.yearTo ?? 2100;
          s += years.any((y) => y >= e.yearFrom! && y <= to) ? 2 : -1;
        }
        var engineHits = 0;
        for (final t in _vehicleWords(e.engine)) {
          if (has(t)) {
            engineHits++;
            s += t.contains('.') ? 2 : 1;
          } else {
            s -= 0.25;
          }
        }
        if (e.code != null && has(TextTools.normalize(e.code!))) {
          engineHits++;
          s += 2;
        }
        if (saysDiesel) s += e.fuel == 'diesel' ? 1 : -1;
        if (saysPetrol) s += e.fuel == 'petrol' ? 1 : -1;
        if (saysNoDpf && e.dpf != null) s += e.dpf! ? -1.5 : 1.5;
        if (saysDpf && e.dpf != null) s += e.dpf! ? 1 : -1;
        if (engineHits > 0) anyEngine = true;
        scored.add(MapEntry(e, s));
      }
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.value.compareTo(a.value));
    final best = scored.first.value;
    final list = anyEngine
        ? scored.where((e) => best - e.value < 0.5).map((e) => e.key).take(3).toList()
        : scored.map((e) => e.key).take(6).toList();
    return _VehicleDetection(list, anyEngine);
  }

  List<String> detectDtcCodes(String message) {
    final codes = <String>[];
    for (final m in dtcRegex.allMatches(message.toUpperCase())) {
      if (!codes.contains(m[0]!)) codes.add(m[0]!);
    }
    return codes;
  }

  List<String> detectParts(String message, {VehicleCtx? ctx}) {
    final toks = TextTools.tokens(message);
    final covered = List<bool>.filled(toks.length, false);
    final found = <String>[];
    for (final ph in _partPhrases) {
      final n = ph.tokens.length;
      for (var i = 0; i + n <= toks.length; i++) {
        var ok = true;
        for (var k = 0; k < n; k++) {
          if (covered[i + k] || !TextTools.fuzzyEq(toks[i + k], ph.tokens[k])) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        for (var k = 0; k < n; k++) {
          covered[i + k] = true;
        }
        for (final s in ph.slugs) {
          if (!found.contains(s) && partCompatible(s, ctx)) found.add(s);
        }
        break;
      }
    }
    return found;
  }

  bool partCompatible(String slug, VehicleCtx? ctx) {
    if (ctx == null) return true;
    final fuel = ctx.fuel;
    final p = parts[slug];
    if (p != null && p.fuel.isNotEmpty && !ctx.fuelMatches(p.fuel)) return false;
    if (_dpfParts.contains(slug) && ctx.hasDpf == false) return false;
    if (fuel != null) {
      final diesel = _dieselOnlyParts.contains(slug) || (p != null && _dieselSections.contains(p.section));
      final petrol = _petrolOnlyParts.contains(slug) || (p != null && _petrolSections.contains(p.section));
      if (diesel && !ctx.fuelMatches(const ['diesel'])) return false;
      if (petrol && !ctx.fuelMatches(const ['petrol'])) return false;
      if (p != null && _hvSections.contains(p.section) && !ctx.fuelMatches(const ['electric'])) return false;
      if (fuel == 'electric' &&
          p != null &&
          (_combustionGroups.contains(p.group) || _combustionSections.contains(p.section))) {
        return false;
      }
    }
    final kind = ctx.effectiveKind;
    if (kind != null) {
      String? partKind = p?.kind;
      if (partKind == null) {
        if (_motoParts.contains(slug) || (p != null && _motoSections.contains(p.section))) {
          partKind = 'moto';
        } else if (p != null && p.groupKind != 'both') {
          partKind = p.groupKind;
        }
      }
      if (partKind != null && partKind != kind) return false;
    }
    return true;
  }

  bool _isDpfCode(String code) {
    if (_dpfCodes.contains(code) || code.startsWith('P244')) return true;
    final n = int.tryParse(code.substring(1), radix: 16);
    if (code.startsWith('P') && n != null && n >= 0x2452 && n <= 0x2463) return true;
    return dtcs[code]?.parts.contains('dpf') ?? false;
  }

  bool dtcCompatible(String code, VehicleCtx? ctx) {
    if (ctx == null) return true;
    if (_isDpfCode(code) && ctx.hasDpf == false) return false;
    final d = dtcs[code];
    return d == null || ctx.fuelMatches(d.fuel);
  }

  String? _incompatibility(KbIntent i, VehicleCtx? ctx) {
    if (ctx == null) return null;
    if (i.requires.contains('dpf') && ctx.hasDpf == false) {
      if (ctx.dpf == false) return 'Votre véhicule est déclaré sans FAP : il n\'y a pas de filtre à particules à contrôler.';
      final fuel = ctx.fuel == null ? '' : ' ; votre véhicule est ${botFuelLabel(ctx.fuel!)}';
      return 'Le filtre à particules (FAP) concerne les moteurs diesel$fuel.';
    }
    if (!ctx.fuelMatches(i.fuel)) {
      return 'Ce sujet concerne les moteurs ${i.fuel.map(botFuelLabel).join(' / ')} ; '
          'votre véhicule est ${botFuelLabel(ctx.fuel!)}.';
    }
    final kind = ctx.effectiveKind;
    if (i.kind != null && kind != null && i.kind != kind) {
      return i.kind == 'moto' ? 'Ce sujet concerne les motos et scooters.' : 'Ce sujet concerne les voitures.';
    }
    return null;
  }

  static final _tagRegex = RegExp(r'^\[([a-z,]+)\]\s*');

  static bool checkVisible(String check, VehicleCtx? ctx) {
    final m = _tagRegex.firstMatch(check);
    if (m == null || ctx == null) return true;
    final tags = m[1]!.split(',');
    final fuels = tags.where(const {'petrol', 'diesel', 'hybrid', 'electric', 'lpg'}.contains).toList();
    if (fuels.isNotEmpty && !ctx.fuelMatches(fuels)) return false;
    if (tags.contains('dpf') && ctx.hasDpf == false) return false;
    final kind = ctx.effectiveKind;
    for (final k in const ['car', 'moto']) {
      if (tags.contains(k) && kind != null && kind != k) return false;
    }
    return true;
  }

  static String stripTag(String check) => check.replaceFirst(_tagRegex, '');

  static const dpfUnknownSuffix = ' (si équipé)';

  static String displayCheck(String check, VehicleCtx? ctx) {
    final text = stripTag(check);
    final tags = _tagRegex.firstMatch(check)?[1]?.split(',') ?? const <String>[];
    if (ctx == null || !tags.contains('dpf') || ctx.hasDpf != null) return text;
    return text.endsWith('.')
        ? '${text.substring(0, text.length - 1)}$dpfUnknownSuffix.'
        : '$text$dpfUnknownSuffix';
  }

  List<String> _filterChecks(List<String> checks, VehicleCtx? ctx) =>
      checks.where((c) => checkVisible(c, ctx)).map((c) => displayCheck(c, ctx)).toList();

  // Each pattern word must match a message word of the same polarity: "moteur chauffe" ignores
  // "le moteur ne chauffe pas", "moteur ne chauffe pas" ignores "le moteur chauffe".
  // A negated pattern (negated_patterns) is written in positive form and counts only when negated.
  double _patternScore(_Pattern p, List<String> toks, List<bool> neg, {bool negatedPattern = false}) {
    int find(String pt, bool? wantNegated) {
      for (var i = 0; i < toks.length; i++) {
        if ((wantNegated == null || neg[i] == wantNegated) && TextTools.fuzzyEq(toks[i], pt)) return i;
      }
      return -1;
    }

    final idx = <int>[];
    for (var k = 0; k < p.tokens.length; k++) {
      var found = find(p.tokens[k], negatedPattern || p.negated[k]);
      if (found < 0 && negatedPattern) found = find(p.tokens[k], null);
      idx.add(found);
    }
    if (negatedPattern && !idx.any((i) => i >= 0 && neg[i])) return 0;
    final missing = idx.where((i) => i < 0).length;
    if (missing == 0) {
      var contiguous = p.tokens.length > 1;
      for (var k = 1; k < idx.length && contiguous; k++) {
        if (idx[k] != idx[k - 1] + 1) contiguous = false;
      }
      return p.weight + (contiguous ? 0.5 : 0);
    }
    if (p.tokens.length >= 3 && missing == 1) return (p.tokens.length - 1) * 0.6;
    return 0;
  }

  List<_ScoredIntent> _scoreIntents(List<String> toks, List<bool> neg, List<String> partsFound, List<String> codes) {
    final out = <_ScoredIntent>[];
    for (final i in intents) {
      final scores = [
        for (final p in _patterns[i.id] ?? const <_Pattern>[]) _patternScore(p, toks, neg),
        for (final p in _negatedPatterns[i.id] ?? const <_Pattern>[])
          _patternScore(p, toks, neg, negatedPattern: true),
      ].where((s) => s > 0).toList()
        ..sort((a, b) => b.compareTo(a));
      var raw = 0.0;
      if (scores.isNotEmpty) {
        raw = scores.first + 0.25 * (scores.length - 1).clamp(0, 3);
        raw += 0.75 * partsFound.where(i.parts.contains).length;
      }
      raw += 2.0 * codes.where(i.dtc.contains).length;
      if (raw > 0) out.add(_ScoredIntent(i, raw, raw + i.priority));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  static final _precheckQuery =
      RegExp(r'\b(controle technique|controle tech|pre ?controle|contre ?visite|ct)\b');

  /// Contrôle technique : géré dans le code (chatbot_kb.json est partagé).
  static bool isPrecheckQuery(String message) => _precheckQuery.hasMatch(TextTools.normalize(message));

  static const _precheckFiller = {
    'preparer', 'preparation', 'passer', 'passage', 'avant', 'faire', 'liste', 'checklist', 'points',
    'point', 'verifier', 'verification', 'comment', 'quoi', 'prochain', 'bientot', 'mon', 'voiture', 'moto',
    'scooter', 'vehicule', 'aide', 'conseils', 'conseil',
  };

  static const precheckAction =
      BotAction('Ouvrir le pré-contrôle technique', BotActionType.openPrecheck, 'precheck');

  static String precheckText(VehicleCtx? ctx) => ctx?.effectiveKind == 'moto'
      ? 'Pour préparer le contrôle technique de votre deux-roues, EMV propose une liste de points à '
          'vérifier vous-même (freins, éclairage, pneus, chaîne, bruit…) avec le niveau de défaillance '
          'possible et un conseil. C\'est indicatif : cela ne remplace pas le contrôle.'
      : 'Pour préparer le contrôle technique, EMV propose une liste de points à vérifier vous-même, '
          'fonction par fonction (freinage, éclairage, pneus, pollution…), avec le niveau de défaillance '
          'possible et un conseil. C\'est indicatif : cela ne remplace pas le contrôle.';

  BotReply reply(String message, {VehicleCtx? ctx}) {
    final r = _reply(message, ctx: ctx);
    if (!isPrecheckQuery(message)) return r;
    // « contrôle technique » seul, sans autre sujet : la checklist plutôt qu'une intention voisine.
    final rest = TextTools.normalize(message)
        .replaceAll(_precheckQuery, ' ')
        .split(' ')
        .where((w) => w.length > 1 && !TextTools.stopwords.contains(w) && !_precheckFiller.contains(w));
    final understood = rest.isNotEmpty &&
        (r.intentId != null || r.dtcCode != null || r.partSlug != null || r.checks.isNotEmpty);
    return BotReply(
      text: understood ? r.text : precheckText(r.ctx),
      checks: r.checks,
      actions: [precheckAction, ...r.actions],
      safety: r.safety,
      suggestions: understood ? r.suggestions : const [],
      intentId: r.intentId,
      dtcCode: r.dtcCode,
      partSlug: r.partSlug,
      vehicles: r.vehicles,
      ctx: r.ctx,
    );
  }

  BotReply _reply(String message, {VehicleCtx? ctx}) {
    final codes = detectDtcCodes(message);
    final detection = _detectVehicle(message);
    var effCtx = ctx;
    if (detection != null && detection.candidates.isNotEmpty) {
      final best = detection.candidates.first;
      if (detection.engineMatched) {
        effCtx = VehicleCtx.fromEntry(best);
      } else {
        final fuels = detection.candidates.map((v) => v.fuel).toSet();
        effCtx = VehicleCtx(
            make: best.make, model: best.model, kind: best.kind, fuel: fuels.length == 1 ? fuels.first : null);
      }
    }
    final analysis = TextTools.analyze(message);
    final partsFound = detectParts(message);
    final compatibleParts = partsFound.where((s) => partCompatible(s, effCtx)).toList();
    final scored = _scoreIntents(analysis.tokens, analysis.negated, partsFound, codes);
    final compatible =
        scored.where((s) => s.raw >= minScore && _incompatibility(s.intent, effCtx) == null).toList();
    String? note;
    if (scored.isNotEmpty && scored.first.raw >= minScore) {
      final inc = _incompatibility(scored.first.intent, effCtx);
      if (inc != null && (compatible.isEmpty || scored.first.score > compatible.first.score + 0.25)) note = inc;
    }

    final vehicleActions = <BotAction>[];
    final vehicleLines = <String>[];
    final candidates = detection?.candidates ?? const <VehicleEntry>[];
    if (candidates.isNotEmpty) {
      if (detection!.engineMatched) {
        vehicleLines.add('Véhicule reconnu : ${effCtx!.label}.');
        for (final v in candidates) {
          vehicleActions.add(BotAction('Choisir ce véhicule : ${v.label}', BotActionType.selectVehicle, v.id, vehicle: v));
        }
      } else {
        vehicleLines.add('Modèle reconnu : ${candidates.first.make} ${candidates.first.model}. Précisez la motorisation :');
        for (final v in candidates) {
          vehicleActions.add(BotAction('Choisir : ${v.label}', BotActionType.selectVehicle, v.id, vehicle: v));
        }
      }
    } else if (ctx != null && (ctx.make != null || ctx.model != null)) {
      vehicleLines.add('Pour : ${ctx.label}.');
    }

    if (codes.isNotEmpty) {
      return _dtcReply(codes, compatible, effCtx, vehicleLines, vehicleActions, candidates);
    }
    if (compatible.isNotEmpty) {
      return _intentReply(compatible, compatibleParts, effCtx, vehicleLines, vehicleActions, candidates, note);
    }
    if (compatibleParts.isNotEmpty) {
      return _partReply(compatibleParts, effCtx, vehicleLines, vehicleActions, candidates);
    }
    String? text;
    if (partsFound.isNotEmpty && effCtx != null) {
      final names = partsFound.map((s) => parts[s]?.name ?? s).join(', ');
      text = '$names : pièce non concernée sur ce véhicule (${effCtx.label}).';
    } else if (note != null) {
      text = note;
    } else if (vehicleActions.isNotEmpty) {
      text = 'Choisissez-le pour adapter les vues éclatées et les réponses, puis décrivez le symptôme.';
    }
    if (text != null) {
      return BotReply(
        text: [...vehicleLines, text].join('\n'),
        actions: vehicleActions,
        suggestions: fallbackSuggestions,
        vehicles: candidates,
        ctx: effCtx,
      );
    }
    return BotReply(
      text: 'Je n\'ai pas compris. Essayez un code défaut (ex. P0401), une pièce (« vanne EGR ») '
          'ou un des symptômes ci-dessous.',
      suggestions: fallbackSuggestions,
      ctx: effCtx,
    );
  }

  List<BotAction> _partActions(List<String> slugs, VehicleCtx? ctx, {String? preferred, int max = 4}) {
    final ordered = <String>[
      if (preferred != null && slugs.contains(preferred)) preferred,
      ...slugs.where((s) => s != preferred),
    ].where((s) => partCompatible(s, ctx) && (parts.isEmpty || parts.containsKey(s))).take(max).toList();
    return [
      for (var i = 0; i < ordered.length; i++)
        i == 0
            ? BotAction('Voir la vue éclatée : ${parts[ordered[i]]?.name ?? ordered[i]}', BotActionType.openView,
                ordered[i])
            : BotAction('Pièce liée : ${parts[ordered[i]]?.name ?? ordered[i]}', BotActionType.openPart, ordered[i]),
    ];
  }

  List<BotAction> _dtcActions(List<String> codes, VehicleCtx? ctx, {int max = 2}) => codes
      .where((c) => dtcCompatible(c, ctx) && (dtcs.isEmpty || dtcs.containsKey(c)))
      .take(max)
      .map((c) => BotAction('Fiche code $c', BotActionType.openDtc, c))
      .toList();

  List<BotAction> _viewActions(List<String> views, VehicleCtx? ctx) {
    final kind = ctx?.effectiveKind;
    return views
        .where((v) {
          if (kind == 'moto' && (v == 'wiring-starting' || v == 'wiring-charging')) return false;
          if (kind == 'car' && v.startsWith('wiring-moto')) return false;
          if (v == 'wiring-glow-plugs-diesel' && !(ctx?.fuelMatches(const ['diesel']) ?? true)) return false;
          if (v == 'wiring-ignition-petrol' && !(ctx?.fuelMatches(const ['petrol']) ?? true)) return false;
          return true;
        })
        .take(2)
        .map((v) => BotAction(viewLabels[v] ?? 'Schéma', BotActionType.openViewId, v))
        .toList();
  }

  List<String> _related(List<_ScoredIntent> compatible, String excludeId) => compatible
      .where((s) => s.intent.id != excludeId && s.intent.patterns.isNotEmpty && s.intent.section.isNotEmpty)
      .take(3)
      .map((s) => _capitalize(s.intent.patterns.first))
      .toList();

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  List<BotAction> _lightActions(String intentId, VehicleCtx? ctx) => (lightsByIntent[intentId] ?? const [])
      .where((l) => ctx?.effectiveKind == null || l.kind == 'both' || l.kind == ctx!.effectiveKind)
      .take(2)
      .map((l) => BotAction('Voyant : ${l.name}', BotActionType.openLight, l.id))
      .toList();

  static Map<String, List<({String id, String name, String kind})>> lightsByIntentFromJson(String raw) {
    final out = <String, List<({String id, String name, String kind})>>{};
    for (final l in jsonDecode(raw) as List) {
      final m = l as Map<String, dynamic>;
      for (final i in (m['intents'] as List? ?? const [])) {
        out.putIfAbsent('$i', () => []).add((id: '${m['id']}', name: '${m['name']}', kind: '${m['kind'] ?? 'car'}'));
      }
    }
    return out;
  }

  BotReply _intentReply(List<_ScoredIntent> compatible, List<String> partsFound, VehicleCtx? ctx,
      List<String> vehicleLines, List<BotAction> vehicleActions, List<VehicleEntry> candidates, String? note) {
    final intent = compatible.first.intent;
    final preferred = partsFound.where(intent.parts.contains).firstOrNull;
    final guide = intent.guideFor(ctx?.fuel);
    return BotReply(
      text: [...vehicleLines, ?note, intent.answer].join('\n'),
      checks: _filterChecks(intent.checks, ctx).take(5).toList(),
      actions: [
        if (guide != null) BotAction('Ouvrir le guide pas-à-pas', BotActionType.openGuide, guide),
        ..._lightActions(intent.id, ctx),
        ..._partActions(intent.parts, ctx, preferred: preferred),
        ..._viewActions(intent.views, ctx),
        ..._dtcActions(intent.dtc, ctx),
        ...vehicleActions,
      ],
      safety: intent.safety,
      suggestions: _related(compatible, intent.id),
      intentId: intent.id,
      partSlug: preferred,
      vehicles: candidates,
      ctx: ctx,
    );
  }

  BotReply _partReply(List<String> slugs, VehicleCtx? ctx, List<String> vehicleLines, List<BotAction> vehicleActions,
      List<VehicleEntry> candidates) {
    final slug = slugs.first;
    final p = parts[slug];
    final lines = <String>[
      ...vehicleLines,
      if (p == null) slug else p.role.isEmpty ? p.name : '${p.name} : ${p.role}',
      if (p != null && p.wear.isNotEmpty) 'Usure / pannes : ${p.wear}',
    ];
    return BotReply(
      text: lines.join('\n'),
      actions: [
        ..._partActions(slugs, ctx, preferred: slug),
        ..._dtcActions(p?.dtc ?? const [], ctx),
        ...vehicleActions,
      ],
      partSlug: slug,
      vehicles: candidates,
      ctx: ctx,
    );
  }

  static String describeCode(String code) {
    final letter = code[0];
    final second = code[1];
    final system = switch (letter) {
      'P' => 'groupe motopropulseur',
      'B' => 'carrosserie (airbag, confort, éclairage)',
      'C' => 'châssis (freins, ABS, direction, suspension)',
      _ => 'réseau de communication entre calculateurs',
    };
    final generic = (second == '0' || second == '2') ? 'code générique (norme SAE)' : 'code spécifique au constructeur';
    var detail = '';
    if (letter == 'P' && (second == '0' || second == '2')) {
      detail = switch (code[2]) {
        '0' || '1' => ' — dosage air / carburant',
        '2' => ' — circuit d\'injection',
        '3' => ' — allumage ou ratés',
        '4' => ' — dépollution',
        '5' => ' — vitesse, ralenti, entrées',
        '6' => ' — calculateur et sorties',
        '7' || '8' || '9' => ' — transmission',
        _ => ' — systèmes complémentaires',
      };
    }
    return '$system, $generic$detail';
  }

  BotReply _dtcReply(List<String> codes, List<_ScoredIntent> compatible, VehicleCtx? ctx, List<String> vehicleLines,
      List<BotAction> vehicleActions, List<VehicleEntry> candidates) {
    final code = codes.first;
    final d = dtcs[code];
    final intent = compatible.where((s) => s.intent.dtc.contains(code)).map((s) => s.intent).firstOrNull;
    final lines = <String>[...vehicleLines];
    if (d != null) {
      lines.add('Code $code : ${d.title}.');
      if (d.causes.isNotEmpty) lines.add('Causes probables : ${d.causes.take(3).join(', ')}.');
      if (!(ctx?.fuelMatches(d.fuel) ?? true)) {
        lines.add('Attention : ce code concerne surtout les moteurs ${d.fuel.map(botFuelLabel).join(' / ')}.');
      }
    } else {
      lines.add('Code $code : ${describeCode(code)}. Ce code n\'est pas encore détaillé dans la base.');
    }
    if (intent != null) lines.add(intent.answer);
    if (codes.length > 1) lines.add('Autres codes relevés : ${codes.skip(1).join(', ')}.');
    final checks = d != null && d.diagnostic.isNotEmpty
        ? d.diagnostic.take(5).toList()
        : _filterChecks(intent?.checks ?? const [], ctx).take(5).toList();
    return BotReply(
      text: lines.join('\n'),
      checks: checks,
      actions: [
        if (d != null || dtcs.isEmpty) BotAction('Fiche code $code', BotActionType.openDtc, code),
        ..._dtcActions(codes.skip(1).toList(), null),
        ..._partActions({...?d?.parts, ...?intent?.parts}.toList(), ctx),
        ..._viewActions(intent?.views ?? const [], ctx),
        ...vehicleActions,
      ],
      safety: d != null && d.severity >= 3
          ? 'Défaut sévère : limitez l\'utilisation du véhicule et faites-le contrôler rapidement.'
          : intent?.safety,
      suggestions: d == null ? fallbackSuggestions : const [],
      intentId: intent?.id,
      dtcCode: code,
      vehicles: candidates,
      ctx: ctx,
    );
  }
}
