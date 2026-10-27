import 'dart:ui' show Color, Offset;

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const <String>[];

String _str(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

bool? _bool(dynamic v) => v is bool ? v : null;

double _num(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;

enum VehicleKind { car, moto, both }

VehicleKind parseKind(dynamic v) => switch (_str(v)) {
      'car' => VehicleKind.car,
      'moto' => VehicleKind.moto,
      _ => VehicleKind.both,
    };

bool kindMatches(VehicleKind item, VehicleKind? filter) =>
    filter == null ||
    filter == VehicleKind.both ||
    item == VehicleKind.both ||
    item == filter;

class TreePart {
  final String slug;
  final String name;
  final String role;
  final String wear;
  final List<String> dtc;
  final VehicleKind kind;

  const TreePart({
    required this.slug,
    required this.name,
    this.role = '',
    this.wear = '',
    this.dtc = const [],
    this.kind = VehicleKind.both,
  });

  factory TreePart.fromJson(Map<String, dynamic> j,
          [VehicleKind inherited = VehicleKind.both]) =>
      TreePart(
        slug: _str(j['slug']),
        name: _str(j['name']),
        role: _str(j['role']),
        wear: _str(j['wear']),
        dtc: _strings(j['dtc']),
        kind: j['kind'] == null ? inherited : parseKind(j['kind']),
      );
}

class TreeGroup {
  final String slug;
  final String name;
  final VehicleKind kind;
  final List<TreePart> parts;

  const TreeGroup(
      {required this.slug,
      required this.name,
      required this.kind,
      required this.parts});

  factory TreeGroup.fromJson(Map<String, dynamic> j, VehicleKind inherited) {
    final kind = j['kind'] == null ? inherited : parseKind(j['kind']);
    return TreeGroup(
      slug: _str(j['slug']),
      name: _str(j['name']),
      kind: kind,
      parts: [
        for (final p in (j['parts'] as List? ?? const []))
          TreePart.fromJson(p as Map<String, dynamic>, kind)
      ],
    );
  }
}

class TreeSection {
  final String slug;
  final String name;
  final VehicleKind kind;
  final List<TreeGroup> children;

  const TreeSection(
      {required this.slug,
      required this.name,
      required this.kind,
      required this.children});

  factory TreeSection.fromJson(Map<String, dynamic> j) {
    final kind = parseKind(j['kind']);
    return TreeSection(
      slug: _str(j['slug']),
      name: _str(j['name']),
      kind: kind,
      children: [
        for (final g in (j['children'] as List? ?? const []))
          TreeGroup.fromJson(g as Map<String, dynamic>, kind)
      ],
    );
  }
}

class EngineSpec {
  final String name;
  final String fuel;
  final String family;
  final String code;
  final bool? dpf;

  const EngineSpec(
      {required this.name,
      required this.fuel,
      required this.family,
      this.code = '',
      this.dpf});

  factory EngineSpec.fromJson(Map<String, dynamic> j) => EngineSpec(
        name: _str(j['name']),
        fuel: _str(j['fuel']),
        family: _str(j['family']),
        code: _str(j['code']),
        dpf: _bool(j['dpf']),
      );
}

class VehicleModel {
  final String name;
  final int? yearFrom;
  final int? yearTo;
  final List<EngineSpec> engines;

  const VehicleModel(
      {required this.name, this.yearFrom, this.yearTo, required this.engines});

  factory VehicleModel.fromJson(Map<String, dynamic> j) {
    final years = j['years'] is List ? j['years'] as List : const [];
    int? year(int i) => i < years.length && years[i] is num
        ? (years[i] as num).toInt()
        : null;
    return VehicleModel(
      name: _str(j['name']),
      yearFrom: year(0),
      yearTo: year(1),
      engines: [
        for (final e in (j['engines'] as List? ?? const []))
          EngineSpec.fromJson(e as Map<String, dynamic>)
      ],
    );
  }
}

class Make {
  final String name;
  final VehicleKind kind;
  final List<VehicleModel> models;

  const Make({required this.name, required this.kind, required this.models});

  factory Make.fromJson(Map<String, dynamic> j) => Make(
        name: _str(j['name']),
        kind: parseKind(j['kind']),
        models: [
          for (final m in (j['models'] as List? ?? const []))
            VehicleModel.fromJson(m as Map<String, dynamic>)
        ],
      );
}

/// Flattened make + model + engine, as selected and persisted by the user.
class Vehicle {
  final String make;
  final String model;
  final String engine;
  final String fuel;
  final String family;
  final String code;
  final VehicleKind kind;
  final int? yearFrom;
  final int? yearTo;
  final bool? dpf;

  const Vehicle({
    required this.make,
    required this.model,
    required this.engine,
    required this.fuel,
    required this.family,
    required this.kind,
    this.code = '',
    this.yearFrom,
    this.yearTo,
    this.dpf,
  });

  /// Diesel hybrids (family hybrid-diesel) count as diesel: glow plugs, no
  /// spark ignition, DPF possible.
  bool get isDiesel =>
      fuel == 'diesel' ||
      family.startsWith('diesel-') ||
      family == 'hybrid-diesel';

  /// False for petrol/electric engines and diesels declared without one.
  bool get mayHaveDpf => isDiesel && dpf != false;

  String? get dpfLabel =>
      !isDiesel || dpf == null ? null : (dpf! ? 'Avec FAP' : 'Sans FAP');

  String get id => '$make|$model|$engine|${yearFrom ?? ''}';

  String get title => '$make $model';

  String get years {
    if (yearFrom == null) return '';
    if (yearTo == null) return 'depuis $yearFrom';
    return '$yearFrom–$yearTo';
  }

  String get subtitle => [
        engine,
        if (code.isNotEmpty) code,
        if (years.isNotEmpty) years,
        fuelLabel(fuel),
        ?dpfLabel,
      ].join(' · ');

  Map<String, dynamic> toJson() => {
        'make': make,
        'model': model,
        'engine': engine,
        'fuel': fuel,
        'family': family,
        'code': code,
        'kind': kind.name,
        'yearFrom': yearFrom,
        'yearTo': yearTo,
        if (dpf != null) 'dpf': dpf,
      };

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        make: _str(j['make']),
        model: _str(j['model']),
        engine: _str(j['engine']),
        fuel: _str(j['fuel']),
        family: _str(j['family']),
        code: _str(j['code']),
        kind: parseKind(j['kind']),
        yearFrom: (j['yearFrom'] as num?)?.toInt(),
        yearTo: (j['yearTo'] as num?)?.toInt(),
        dpf: _bool(j['dpf']),
      );
}

String fuelLabel(String fuel) => switch (fuel) {
      'petrol' => 'Essence',
      'diesel' => 'Diesel',
      'hybrid' => 'Hybride',
      'electric' => 'Électrique',
      'lpg' => 'GPL',
      _ => fuel,
    };

class Family {
  final String key;
  final String name;
  final VehicleKind kind;
  final List<String> views;

  const Family(
      {required this.key,
      required this.name,
      required this.kind,
      required this.views});

  factory Family.fromJson(Map<String, dynamic> j) => Family(
        key: _str(j['key']),
        name: _str(j['name']),
        kind: parseKind(j['kind']),
        views: _strings(j['views']),
      );
}

class ViewPart {
  final String slug;
  final String label;
  final String path;
  final Offset? labelAt;
  final int order;
  final Color? color;

  const ViewPart({
    required this.slug,
    required this.label,
    required this.path,
    this.labelAt,
    this.order = 0,
    this.color,
  });

  bool get isClosed => path.contains('Z') || path.contains('z');

  factory ViewPart.fromJson(Map<String, dynamic> j) {
    final at = j['labelAt'];
    return ViewPart(
      slug: _str(j['slug']),
      label: _str(j['label']),
      path: _str(j['path']),
      labelAt: at is List && at.length >= 2
          ? Offset(_num(at[0]), _num(at[1]))
          : null,
      order: (j['order'] as num?)?.toInt() ?? 0,
      color: parseColor(j['color']),
    );
  }
}

class ViewGuide {
  final String d;
  final Color? color;

  const ViewGuide(this.d, {this.color});
}

const _namedColors = {
  'noir': 0xFF1A1A1A, 'black': 0xFF1A1A1A,
  'rouge': 0xFFE53935, 'red': 0xFFE53935,
  'marron': 0xFF8D5524, 'brown': 0xFF8D5524,
  'bleu': 0xFF1E88E5, 'blue': 0xFF1E88E5,
  'jaune': 0xFFFDD835, 'yellow': 0xFFFDD835,
  'vert': 0xFF43A047, 'green': 0xFF43A047,
  'blanc': 0xFFF5F5F5, 'white': 0xFFF5F5F5,
  'gris': 0xFF9E9E9E, 'grey': 0xFF9E9E9E, 'gray': 0xFF9E9E9E,
  'orange': 0xFFFB8C00,
  'violet': 0xFF8E24AA, 'purple': 0xFF8E24AA,
  'rose': 0xFFEC407A, 'pink': 0xFFEC407A,
  'beige': 0xFFD7C4A3,
  'transparent': 0xFFE0E0E0,
};

/// Accepts `#RGB`, `#RRGGBB`, `#AARRGGBB` or a usual wire colour name.
Color? parseColor(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim().toLowerCase();
  final named = _namedColors[s];
  if (named != null) return Color(named);
  var hex = s.startsWith('#') ? s.substring(1) : s;
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = 'ff$hex';
  if (hex.length != 8) return null;
  final n = int.tryParse(hex, radix: 16);
  return n == null ? null : Color(n);
}

class ExplodedView {
  final String id;
  final String name;
  final double width;
  final double height;
  final List<ViewPart> parts;
  final List<ViewGuide> guides;
  final String? engineCode;
  final bool specific;

  const ExplodedView({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.parts,
    this.guides = const [],
    this.engineCode,
    this.specific = false,
  });

  bool containsPart(String slug) => parts.any((p) => p.slug == slug);

  factory ExplodedView.fromJson(Map<String, dynamic> j) {
    final parts = [
      for (final p in (j['parts'] as List? ?? const []))
        ViewPart.fromJson(p as Map<String, dynamic>)
    ]..sort((a, b) => a.order.compareTo(b.order));
    return ExplodedView(
      id: _str(j['id']),
      name: _str(j['name']),
      width: _num(j['width'], 1000),
      height: _num(j['height'], 700),
      parts: parts,
      guides: [
        for (final g in (j['guides'] as List? ?? const []))
          if (g is Map && g['d'] != null)
            ViewGuide(g['d'].toString(), color: parseColor(g['color']))
      ],
      engineCode: j['engineCode']?.toString(),
      specific: j['specific'] == true,
    );
  }
}

class Dtc {
  final String code;
  final String title;
  final String system;
  final List<String> symptoms;
  final List<String> causes;
  final List<String> diagnostic;
  final List<String> parts;
  final int severity;
  final List<String> fuel;

  const Dtc({
    required this.code,
    required this.title,
    this.system = '',
    this.symptoms = const [],
    this.causes = const [],
    this.diagnostic = const [],
    this.parts = const [],
    this.severity = 1,
    this.fuel = const [],
  });

  factory Dtc.fromJson(Map<String, dynamic> j) => Dtc(
        code: _str(j['code']).toUpperCase(),
        title: _str(j['title']),
        system: _str(j['system']),
        symptoms: _strings(j['symptoms']),
        causes: _strings(j['causes']),
        diagnostic: _strings(j['diagnostic']),
        parts: _strings(j['parts']),
        severity: (j['severity'] as num?)?.toInt() ?? 1,
        fuel: _strings(j['fuel']),
      );
}

String systemLabel(String system) => switch (system) {
      'ignition' => 'Allumage',
      'fuel' => 'Carburant',
      'air' => 'Admission d\'air',
      'emissions' => 'Dépollution',
      'transmission' => 'Transmission',
      'electrical' => 'Électricité',
      'cooling' => 'Refroidissement',
      'engine' => 'Moteur',
      'sensors' => 'Capteurs',
      'speed-idle' => 'Vitesse et ralenti',
      'computer' => 'Calculateur',
      'hybrid' => 'Hybride',
      'chassis' => 'Châssis',
      'climate' => 'Climatisation',
      'network' => 'Réseau multiplexé',
      _ => system,
    };

const _dtcFamilyOrder = 'PCBU';

/// Powertrain (P) first, then chassis (C), body (B) and network (U) codes.
int compareDtcCodes(Dtc a, Dtc b) {
  final byFamily = _dtcFamilyOrder
      .indexOf(a.code[0])
      .compareTo(_dtcFamilyOrder.indexOf(b.code[0]));
  return byFamily != 0 ? byFamily : a.code.compareTo(b.code);
}

/// Rule linking a vehicles.json engine without code to an engine spec.
class EngineMatch {
  final String engine;
  final String? make;
  final List<String> models;
  final int? since;
  final int? until;

  const EngineMatch(
      {required this.engine,
      this.make,
      this.models = const [],
      this.since,
      this.until});

  factory EngineMatch.fromJson(Map<String, dynamic> j) => EngineMatch(
        engine: _str(j['engine']),
        make: j['make']?.toString(),
        models: _strings(j['models']),
        since: (j['since'] as num?)?.toInt(),
        until: (j['until'] as num?)?.toInt(),
      );
}

/// Engine architecture sheet (engine_specs.json), keyed by engine code.
class EngineSpecInfo {
  final String code;
  final String name;
  final VehicleKind kind;
  final int cylinders;
  final String layout;
  final int valves;
  final String timing;
  final bool wetBelt;
  final String fuel;
  final String injection;
  final String turbo;
  final bool egr;
  final String dpf;
  final String cooling;
  final int? displacement;
  final int? vAngle;
  final List<String> specific;
  final List<String> notes;
  final List<String> vehicles;
  final List<String> aliases;
  final List<EngineMatch> match;

  const EngineSpecInfo({
    required this.code,
    required this.name,
    this.kind = VehicleKind.car,
    this.cylinders = 4,
    this.layout = 'inline',
    this.valves = 16,
    this.timing = '',
    this.wetBelt = false,
    this.fuel = '',
    this.injection = '',
    this.turbo = 'none',
    this.egr = false,
    this.dpf = 'no',
    this.cooling = 'liquid',
    this.displacement,
    this.vAngle,
    this.specific = const [],
    this.notes = const [],
    this.vehicles = const [],
    this.aliases = const [],
    this.match = const [],
  });

  factory EngineSpecInfo.fromJson(Map<String, dynamic> j) => EngineSpecInfo(
        code: _str(j['code']),
        name: _str(j['name']),
        kind: parseKind(j['kind']),
        cylinders: (j['cylinders'] as num?)?.toInt() ?? 4,
        layout: _str(j['layout'], 'inline'),
        valves: (j['valves'] as num?)?.toInt() ?? 16,
        timing: _str(j['timing']),
        wetBelt: j['wetBelt'] == true,
        fuel: _str(j['fuel']),
        injection: _str(j['injection']),
        turbo: _str(j['turbo'], 'none'),
        egr: j['egr'] == true,
        dpf: _str(j['dpf'], 'no'),
        cooling: _str(j['cooling'], 'liquid'),
        displacement: (j['displacement'] as num?)?.toInt(),
        vAngle: (j['vAngle'] as num?)?.toInt(),
        specific: _strings(j['specific']),
        notes: _strings(j['notes']),
        vehicles: _strings(j['vehicles']),
        aliases: _strings(j['aliases']),
        match: [
          for (final m in (j['match'] as List? ?? const []))
            if (m is Map<String, dynamic>) EngineMatch.fromJson(m)
        ],
      );

  String get title => '$code · $name';

  String get layoutLabel => switch (layout) {
        'v' => vAngle == null
            ? '$cylinders cylindres en V (V$cylinders)'
            : '$cylinders cylindres en V à $vAngle° (V$cylinders)',
        'boxer' => '$cylinders cylindres à plat (boxer)',
        'single' => 'monocylindre',
        'inline' => '$cylinders cylindres en ligne',
        _ => layout,
      };

  String get timingLabel => switch (timing) {
        'chain' => 'chaîne',
        'belt' => wetBelt ? 'courroie baignant dans l\'huile' : 'courroie',
        'gear' => 'cascade de pignons',
        _ => timing,
      };

  String get injectionLabel => switch (injection) {
        'common-rail' => 'injection directe common rail',
        'direct-petrol' => 'injection directe essence',
        'port' => 'injection indirecte',
        'indirect' => 'injection indirecte',
        'carburetor' => 'carburateur',
        'unit-injector' => 'injecteurs-pompes',
        'distributor-pump' => 'injection directe par pompe distributrice',
        _ => injection,
      };

  String get turboLabel => switch (turbo) {
        'vgt' => 'turbo à géométrie variable',
        'fixed' => 'turbo à géométrie fixe',
        'twin' => 'biturbo',
        'supercharger' => 'compresseur mécanique',
        'variant' => 'turbo selon version',
        'none' => 'atmosphérique',
        _ => turbo,
      };

  /// Petrol engines carry a GPF, not a FAP; null when there is no filter.
  String? get particleFilterName => fuel == 'diesel'
      ? 'FAP'
      : dpf == 'no'
          ? null
          : 'GPF (FAP essence)';

  String get dpfLabel => switch (dpf) {
        'yes' => 'oui',
        'variant' => 'selon version',
        'no' => 'non',
        _ => dpf,
      };

  String get coolingLabel => switch (cooling) {
        'air' => 'par air',
        'variant' => 'air/huile ou liquide selon version',
        'liquid' => 'liquide',
        _ => cooling,
      };
}

class ModelIssue {
  final String title;
  final String symptoms;
  final List<String> parts;
  final List<String> dtc;
  final List<String> engines;

  const ModelIssue(
      {required this.title,
      this.symptoms = '',
      this.parts = const [],
      this.dtc = const [],
      this.engines = const []});

  factory ModelIssue.fromJson(Map<String, dynamic> j) => ModelIssue(
        title: _str(j['title']),
        symptoms: _str(j['symptoms']),
        parts: _strings(j['parts']),
        dtc: _strings(j['dtc']),
        engines: _strings(j['engines']),
      );
}

class MaintenanceItem {
  final String item;
  final String note;

  const MaintenanceItem({required this.item, this.note = ''});

  factory MaintenanceItem.fromJson(Map<String, dynamic> j) =>
      MaintenanceItem(item: _str(j['item']), note: _str(j['note']));
}

/// Per-generation model sheet (model_specs.json), keyed by make and model.
class ModelSpec {
  final String key;
  final int? yearFrom;
  final int? yearTo;
  final String platform;
  final List<String> body;
  final Map<String, String> brakes;
  final Map<String, String> suspension;
  final String steering;
  final List<String> fuseBoxes;
  final String battery;
  final String obdPort;
  final List<ModelIssue> knownIssues;
  final List<MaintenanceItem> maintenance;
  final List<String> tips;
  final List<String> views;

  const ModelSpec({
    required this.key,
    this.yearFrom,
    this.yearTo,
    this.platform = '',
    this.body = const [],
    this.brakes = const {},
    this.suspension = const {},
    this.steering = '',
    this.fuseBoxes = const [],
    this.battery = '',
    this.obdPort = '',
    this.knownIssues = const [],
    this.maintenance = const [],
    this.tips = const [],
    this.views = const [],
  });

  static Map<String, String> _map(dynamic v) => v is Map
      ? {for (final e in v.entries) e.key.toString(): e.value.toString()}
      : const {};

  factory ModelSpec.fromJson(Map<String, dynamic> j) {
    final years = j['years'] is List ? j['years'] as List : const [];
    return ModelSpec(
      key: _str(j['key']),
      yearFrom: years.isNotEmpty ? (years[0] as num?)?.toInt() : null,
      yearTo: years.length > 1 ? (years[1] as num?)?.toInt() : null,
      platform: _str(j['platform']),
      body: _strings(j['body']),
      brakes: _map(j['brakes']),
      suspension: _map(j['suspension']),
      steering: _str(j['steering']),
      fuseBoxes: _strings(j['fuseBoxes']),
      battery: _str(j['battery']),
      obdPort: _str(j['obdPort']),
      knownIssues: [
        for (final i in (j['knownIssues'] as List? ?? const []))
          if (i is Map<String, dynamic>) ModelIssue.fromJson(i)
      ],
      maintenance: [
        for (final m in (j['maintenance'] as List? ?? const []))
          if (m is Map<String, dynamic>) MaintenanceItem.fromJson(m)
      ],
      tips: _strings(j['tips']),
      views: _strings(j['views']),
    );
  }
}
