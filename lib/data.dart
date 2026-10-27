import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae', 'š': 's', 'ž': 'z', 'č': 'c', 'ř': 'r',
};

/// Lowercase, accent-free, punctuation collapsed to single spaces.
String normalize(String input) {
  final sb = StringBuffer();
  for (final ch in input.toLowerCase().split('')) {
    sb.write(_accents[ch] ?? ch);
  }
  return sb
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9.]+'), ' ')
      .trim();
}

/// True when [needle] occurs in [haystack] as a whole token: "1.6 TDI"
/// matches "1.6 TDI 105" but "125" does not match "1.25" nor "1250".
bool containsToken(String haystack, String needle) {
  final h = haystack.toLowerCase(), n = needle.toLowerCase();
  if (n.isEmpty) return false;
  var i = h.indexOf(n);
  while (i >= 0) {
    final before = i > 0 ? h[i - 1] : ' ';
    final after = i + n.length < h.length ? h[i + n.length] : ' ';
    final okBefore = !RegExp(r'[a-z0-9.]').hasMatch(before);
    final okAfter = !RegExp(r'[0-9]').hasMatch(after);
    if (okBefore && okAfter) return true;
    i = h.indexOf(n, i + 1);
  }
  return false;
}

List<String> _tokens(String query) =>
    normalize(query).split(' ').where((t) => t.isNotEmpty).toList();

const dpfPartSlugs = {'dpf', 'dpf-pressure-sensor', 'dpf-temp-sensor'};

const dpfDtcCodes = {'P2002', 'P2003', 'P242F', 'P2463'};

const ignitionPartSlugs = {
  'spark-plug',
  'ignition-coil',
  'spark-plug-wire',
  'distributor',
};

/// Hides DPF parts on engines without one and spark ignition parts on diesels.
bool partAppliesTo(String slug, Vehicle? v) {
  if (v == null) return true;
  if (!v.mayHaveDpf && dpfPartSlugs.contains(slug)) return false;
  if (v.isDiesel && ignitionPartSlugs.contains(slug)) return false;
  return true;
}

bool isDpfDtc(Dtc d) {
  if (dpfDtcCodes.contains(d.code)) return true;
  final n = d.code.startsWith('P245') ? int.tryParse(d.code.substring(4)) : null;
  if (n != null && n >= 2 && n <= 9) return true;
  return d.parts.any(dpfPartSlugs.contains);
}

bool dtcAppliesTo(Dtc d, Vehicle? v) =>
    v == null || v.mayHaveDpf || !isDpfDtc(d);

class PartLocation {
  final TreeSection section;
  final TreeGroup group;
  final TreePart part;

  const PartLocation(this.section, this.group, this.part);

  String get breadcrumb => '${section.name} › ${group.name}';
}

const viewCategories = [
  'Moteur',
  'Alimentation / Admission',
  'Échappement',
  'Transmission',
  'Freinage',
  'Châssis',
  'Électricité / Schémas',
  'Moto',
  'Autres',
];

String viewCategory(String id) {
  bool any(List<String> prefixes) => prefixes.any(id.startsWith);
  if (any(['moto-', 'scooter-', 'wiring-moto-'])) return 'Moto';
  if (any(['wiring-', 'electrical-', 'fuse-box', 'electric-', 'hybrid-'])) {
    return 'Électricité / Schémas';
  }
  if (any(['engine-', 'head-', 'cylinder-head', 'timing-', 'cooling', 'lubrication'])) {
    return 'Moteur';
  }
  if (any(['fuel-', 'turbo-', 'intake'])) return 'Alimentation / Admission';
  if (id.startsWith('exhaust-')) return 'Échappement';
  if (any(['clutch-', 'gearbox-', 'driveshaft-'])) return 'Transmission';
  if (id.startsWith('brakes-')) return 'Freinage';
  if (any(['steering-', 'suspension-'])) return 'Châssis';
  return 'Autres';
}

/// Views grouped by [viewCategories] order; empty categories are dropped.
List<(String, List<ExplodedView>)> groupViewsByCategory(List<ExplodedView> views) {
  final by = <String, List<ExplodedView>>{};
  for (final v in views) {
    by.putIfAbsent(viewCategory(v.id), () => []).add(v);
  }
  return [
    for (final c in viewCategories)
      if (by[c] != null) (c, by[c]!)
  ];
}

class AppData {
  final List<TreeSection> tree;
  final List<Make> makes;
  final List<Family> families;
  final List<Dtc> dtcs;
  final List<ExplodedView> views;
  final List<EngineSpecInfo> engineSpecs;
  final Map<String, List<String>> engineViews;
  final List<ModelSpec> modelSpecs;

  final Map<String, PartLocation> _parts = {};
  final Map<String, EngineSpecInfo> _engineByCode = {};
  final Map<String, ModelSpec> _modelSpecs = {};
  final Map<String, Family> _families = {};
  final Map<String, Dtc> _dtcs = {};
  final Map<String, ExplodedView> _views = {};
  final List<(Vehicle, String)> _vehicleIndex = [];
  final List<(Dtc, String)> _dtcIndex = [];

  AppData({
    required this.tree,
    required this.makes,
    required this.families,
    required this.dtcs,
    required this.views,
    this.engineSpecs = const [],
    this.engineViews = const {},
    this.modelSpecs = const [],
  }) {
    for (final e in engineSpecs) {
      for (final c in [e.code, ...e.aliases]) {
        _engineByCode.putIfAbsent(c.toUpperCase(), () => e);
      }
    }
    for (final m in modelSpecs) {
      _modelSpecs[m.key] = m;
    }
    for (final s in tree) {
      for (final g in s.children) {
        for (final p in g.parts) {
          _parts[p.slug] = PartLocation(s, g, p);
        }
      }
    }
    for (final f in families) {
      _families[f.key] = f;
    }
    for (final d in dtcs) {
      _dtcs.putIfAbsent(d.code, () => d);
      _dtcIndex.add((
        d,
        normalize('${d.code} ${d.title} ${systemLabel(d.system)} '
            '${d.symptoms.join(' ')}')
      ));
    }
    for (final v in views) {
      _views[v.id] = v;
    }
    for (final m in makes) {
      for (final model in m.models) {
        for (final e in model.engines) {
          final v = Vehicle(
            make: m.name,
            model: model.name,
            engine: e.name,
            fuel: e.fuel,
            family: e.family,
            code: e.code,
            kind: m.kind,
            yearFrom: model.yearFrom,
            yearTo: model.yearTo,
            dpf: e.dpf,
          );
          _vehicleIndex.add((
            v,
            normalize('${m.name} ${model.name} ${e.name} ${e.code} '
                '${fuelLabel(e.fuel)} ${m.kind == VehicleKind.moto ? 'moto' : 'voiture'}')
          ));
        }
      }
    }
  }

  static const dataDir = 'assets/data';
  static const viewsDir = 'assets/views';

  static Future<AppData> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    Future<dynamic> json(String path) async =>
        jsonDecode(await b.loadString(path, cache: false));

    final tree = [
      for (final s in await json('$dataDir/tree.json') as List)
        TreeSection.fromJson(s as Map<String, dynamic>)
    ];
    final vehiclesJson = await json('$dataDir/vehicles.json');
    final makes = [
      for (final m in (vehiclesJson is Map ? vehiclesJson['makes'] : vehiclesJson)
          as List)
        Make.fromJson(m as Map<String, dynamic>)
    ];
    final families = [
      for (final f in await json('$dataDir/families.json') as List)
        Family.fromJson(f as Map<String, dynamic>)
    ];
    final dtcs = [
      for (final d in await json('$dataDir/dtc.json') as List)
        Dtc.fromJson(d as Map<String, dynamic>)
    ]..sort(compareDtcCodes);

    Future<dynamic> optional(String path) async {
      try {
        return await json(path);
      } catch (e) {
        debugPrint('$path ignoré : $e');
        return null;
      }
    }

    final engineSpecs = [
      for (final e in (await optional('$dataDir/engine_specs.json') as List? ?? const []))
        EngineSpecInfo.fromJson(e as Map<String, dynamic>)
    ];
    final ev = await optional('$dataDir/engine_views.json');
    final engineViews = <String, List<String>>{
      if (ev is Map)
        for (final e in ev.entries)
          e.key.toString(): [for (final id in e.value as List) id.toString()]
    };
    final modelSpecs = [
      for (final m in (await optional('$dataDir/model_specs.json') as List? ?? const []))
        ModelSpec.fromJson(m as Map<String, dynamic>)
    ];

    final views = <ExplodedView>[];
    for (final id in await viewIds(b)) {
      try {
        views.add(ExplodedView.fromJson(
            await json('$viewsDir/$id.json') as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Vue ignorée $id : $e');
      }
    }
    return AppData(
        tree: tree,
        makes: makes,
        families: families,
        dtcs: dtcs,
        views: views,
        engineSpecs: engineSpecs,
        engineViews: engineViews,
        modelSpecs: modelSpecs);
  }

  /// Ids from views/index.json, plus any view file bundled but not yet indexed
  /// (views are authored in parallel, the index may lag behind).
  static Future<List<String>> viewIds(AssetBundle b) async {
    final ids = <String>[];
    try {
      final index = jsonDecode(await b.loadString('$viewsDir/index.json'));
      ids.addAll((index as List).map((e) => e.toString()));
    } catch (e) {
      debugPrint('index.json illisible : $e');
    }
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(b);
      for (final a in manifest.listAssets()) {
        if (!a.startsWith('$viewsDir/') || !a.endsWith('.json')) continue;
        final id = a.substring(viewsDir.length + 1, a.length - 5);
        if (id != 'index' && !id.contains('/') && !ids.contains(id)) {
          ids.add(id);
        }
      }
    } catch (_) {}
    return ids;
  }

  PartLocation? part(String slug) => _parts[slug];
  Iterable<String> get partSlugs => _parts.keys;
  Family? family(String key) => _families[key];
  Dtc? dtc(String code) => _dtcs[code.toUpperCase()];
  ExplodedView? view(String id) => _views[id];

  /// Views drawn for one precise engine are only listed for that engine.
  List<ExplodedView> get genericViews =>
      [for (final v in views) if (!v.specific) v];

  List<ExplodedView> viewsFor(Vehicle? vehicle) {
    final fam = vehicle == null ? null : family(vehicle.family);
    if (fam == null) return genericViews;
    final list = [for (final id in fam.views) ?_views[id]];
    return list.isEmpty ? genericViews : list;
  }

  EngineSpecInfo? engineSpec(String code) => _engineByCode[code.toUpperCase()];

  /// The engine sheet for [vehicle]: by engine code first (codes like
  /// "A17DT/A17DTR" list alternatives), else by the spec's match rules when
  /// vehicles.json has no code. Hybrid and non-hybrid never cross-match,
  /// except diesel hybrids whose combustion engine is a plain diesel spec.
  EngineSpecInfo? engineSpecFor(Vehicle? vehicle) {
    if (vehicle == null) return null;
    bool compatible(EngineSpecInfo e) => vehicle.family == 'hybrid-diesel'
        ? e.fuel == 'diesel'
        : (vehicle.fuel == 'hybrid') == (e.fuel == 'hybrid');
    final code = vehicle.code.trim();
    if (code.isNotEmpty) {
      for (final c in code.split('/')) {
        final e = engineSpec(c.trim());
        if (e != null && compatible(e)) return e;
      }
      return null;
    }
    final make = vehicle.make.toLowerCase();
    for (final e in engineSpecs) {
      if (!compatible(e)) continue;
      for (final m in e.match) {
        if (m.make != null && m.make!.toLowerCase() != make) continue;
        if (m.models.isNotEmpty &&
            !m.models.any((x) => containsToken(vehicle.model, x))) {
          continue;
        }
        final y = vehicle.yearFrom;
        if (m.since != null && (y == null || y < m.since!)) continue;
        if (m.until != null && (y == null || y > m.until!)) continue;
        if (containsToken(vehicle.engine, m.engine)) return e;
      }
    }
    return null;
  }

  List<ExplodedView> specificViewsFor(Vehicle? vehicle) {
    final e = engineSpecFor(vehicle);
    if (e == null) return const [];
    return [for (final id in engineViews[e.code] ?? const <String>[]) ?_views[id]];
  }

  ModelSpec? modelSpecFor(Vehicle? vehicle) =>
      vehicle == null ? null : _modelSpecs['${vehicle.make}|${vehicle.model}'];

  /// Chassis views chosen by the model sheet, minus engine-specific ones.
  List<ExplodedView> modelViewsFor(Vehicle? vehicle) {
    final m = modelSpecFor(vehicle);
    if (m == null) return const [];
    return [
      for (final id in m.views)
        if (_views[id] case final v? when !v.specific) v
    ];
  }

  /// Family views not already shown by the model sheet.
  List<ExplodedView> familyViewsFor(Vehicle? vehicle) {
    final shown = modelViewsFor(vehicle).map((v) => v.id).toSet();
    return [for (final v in viewsFor(vehicle)) if (!shown.contains(v.id)) v];
  }

  /// Known issues of the model that concern this vehicle's engine (issues
  /// without an engine list apply to every version).
  List<ModelIssue> issuesFor(Vehicle? vehicle) {
    final m = modelSpecFor(vehicle);
    if (m == null || vehicle == null) return const [];
    final spec = engineSpecFor(vehicle);
    final codes = <String>{
      for (final c in vehicle.code.split('/'))
        if (c.trim().isNotEmpty) c.trim().toUpperCase(),
      if (spec != null) ...[spec.code, ...spec.aliases].map((c) => c.toUpperCase()),
    };
    return [
      for (final i in m.knownIssues)
        if (i.engines.isEmpty ||
            i.engines.any((e) =>
                codes.contains(e.toUpperCase()) ||
                containsToken(vehicle.engine, e)))
          i
    ];
  }

  List<TreeSection> treeFor(VehicleKind? kind, {Vehicle? vehicle}) => [
        for (final s in tree)
          if (kindMatches(s.kind, kind))
            TreeSection(
              slug: s.slug,
              name: s.name,
              kind: s.kind,
              children: [
                for (final g in s.children)
                  if (kindMatches(g.kind, kind))
                    TreeGroup(
                      slug: g.slug,
                      name: g.name,
                      kind: g.kind,
                      parts: [
                        for (final p in g.parts)
                          if (kindMatches(p.kind, kind) &&
                              partAppliesTo(p.slug, vehicle))
                            p
                      ],
                    )
              ],
            )
      ];

  List<String> partsFor(Iterable<String> slugs, Vehicle? vehicle) =>
      [for (final s in slugs) if (partAppliesTo(s, vehicle)) s];

  List<Dtc> dtcsForPart(String slug, {Vehicle? vehicle}) {
    final codes = <String>{...?_parts[slug]?.part.dtc};
    final result = <Dtc>[];
    for (final d in dtcs) {
      final linked = d.parts.contains(slug) || codes.remove(d.code);
      if (linked && dtcAppliesTo(d, vehicle)) result.add(d);
    }
    result.sort((a, b) => a.code.compareTo(b.code));
    return result;
  }

  /// Unknown codes referenced in tree.json, shown without a sheet.
  List<String> unknownDtcCodesForPart(String slug) => [
        for (final c in _parts[slug]?.part.dtc ?? const <String>[])
          if (!_dtcs.containsKey(c)) c
      ];

  /// The view best showing [slugs]: the most matches wins, the vehicle's
  /// family views first on ties.
  ExplodedView? bestViewFor(Iterable<String> slugs, {Vehicle? vehicle}) {
    final wanted = slugs.toSet();
    if (wanted.isEmpty) return null;
    final specific = specificViewsFor(vehicle);
    final preferred = {
      ...specific.map((v) => v.id),
      ...modelViewsFor(vehicle).map((v) => v.id),
      ...viewsFor(vehicle).map((v) => v.id),
    };
    ExplodedView? best;
    var bestScore = 0.0;
    for (final v in [...specific, ...genericViews]) {
      final hits = v.parts.where((p) => wanted.contains(p.slug)).length;
      if (hits == 0) continue;
      final score = hits + (preferred.contains(v.id) ? 0.5 : 0.0);
      if (score > bestScore) {
        best = v;
        bestScore = score;
      }
    }
    return best;
  }

  List<Vehicle> searchVehicles(String query,
      {VehicleKind? kind, int limit = 100}) {
    final tokens = _tokens(query);
    final out = <Vehicle>[];
    for (final (v, text) in _vehicleIndex) {
      if (!kindMatches(v.kind, kind)) continue;
      if (!_matchTokens(tokens, text, v)) continue;
      out.add(v);
      if (out.length >= limit) break;
    }
    return out;
  }

  bool _matchTokens(List<String> tokens, String text, Vehicle v) {
    for (final t in tokens) {
      final year = int.tryParse(t);
      if (year != null && t.length == 4 && v.yearFrom != null) {
        if (year >= v.yearFrom! && year <= (v.yearTo ?? 9999)) continue;
        return false;
      }
      if (!text.contains(t)) return false;
    }
    return true;
  }

  List<Dtc> searchDtc(String query, {Vehicle? vehicle, int limit = 200}) {
    final q = query.trim().toUpperCase();
    final candidates = vehicle == null
        ? dtcs
        : dtcs.where((d) => dtcAppliesTo(d, vehicle));
    if (q.isEmpty) return candidates.take(limit).toList();
    final codeLike = RegExp(r'^[PCBU][0-9A-F]{0,4}$').hasMatch(q);
    if (codeLike) {
      return candidates.where((d) => d.code.startsWith(q)).take(limit).toList();
    }
    final tokens = _tokens(query);
    return [
      for (final (d, text) in _dtcIndex)
        if (tokens.every(text.contains) && dtcAppliesTo(d, vehicle)) d
    ].take(limit).toList();
  }

  List<TreePart> searchParts(String query, {Vehicle? vehicle}) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return const [];
    return [
      for (final loc in _parts.values)
        if (kindMatches(loc.part.kind, vehicle?.kind) &&
            partAppliesTo(loc.part.slug, vehicle) &&
            tokens.every(normalize('${loc.part.name} ${loc.part.slug}').contains))
          loc.part
    ];
  }
}
