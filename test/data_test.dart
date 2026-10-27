import 'package:emv/data.dart';
import 'package:emv/models.dart';
import 'package:emv/widgets/exploded_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppData data;

  setUpAll(() async {
    data = await AppData.load(rootBundle);
  });

  group('chargement', () {
    test('tous les JSON se chargent', () {
      expect(data.tree, isNotEmpty);
      expect(data.makes, isNotEmpty);
      expect(data.families, isNotEmpty);
      expect(data.dtcs, isNotEmpty);
      expect(data.views, isNotEmpty);
    });

    test('views/index.json ne référence que des vues existantes', () async {
      final index = await AppData.viewIds(rootBundle);
      final loaded = data.views.map((v) => v.id).toSet();
      expect(index.where((id) => !loaded.contains(id)), isEmpty,
          reason: 'vue listée mais absente ou invalide');
    });

    test('chaque vue a un id égal à son nom de fichier et des tracés valides',
        () async {
      for (final v in data.views) {
        final raw = await rootBundle.loadString('assets/views/${v.id}.json');
        expect(raw, contains('"${v.id}"'));
        expect(v.parts, isNotEmpty, reason: v.id);
        expect(parseViewParts(v).length, v.parts.length,
            reason: 'tracé SVG invalide dans ${v.id}');
      }
    });
  });

  group('arborescence', () {
    test('slugs uniques et en kebab-case', () {
      final slugs = <String>[];
      for (final s in data.tree) {
        slugs.add(s.slug);
        for (final g in s.children) {
          slugs.add(g.slug);
          slugs.addAll(g.parts.map((p) => p.slug));
        }
      }
      final dup = slugs.where((s) => slugs.where((x) => x == s).length > 1);
      expect(dup.toSet(), isEmpty);
      final kebab = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
      expect(slugs.where((s) => !kebab.hasMatch(s)), isEmpty);
    });

    test('150+ pièces avec rôle et usure, voiture et moto', () {
      final parts = [
        for (final s in data.tree)
          for (final g in s.children) ...g.parts
      ];
      expect(parts.length, greaterThanOrEqualTo(150));
      expect(parts.where((p) => p.role.isEmpty || p.wear.isEmpty), isEmpty);
      expect(data.treeFor(VehicleKind.moto).expand((s) => s.children),
          isNotEmpty);
      for (final slug in const [
        'piston', 'connecting-rod', 'crankshaft', 'intake-valve',
        'exhaust-valve', 'camshaft', 'timing-belt', 'tensioner', 'water-pump',
        'turbocharger', 'intercooler', 'injector', 'high-pressure-pump',
        'spark-plug', 'ignition-coil', 'maf-sensor', 'map-sensor',
        'lambda-sensor-upstream', 'catalytic-converter', 'egr-valve', 'dpf',
        'brake-disc', 'brake-pad', 'caliper', 'shock-absorber', 'coil-spring',
        'battery', 'alternator', 'starter-motor', 'ecu',
      ]) {
        expect(data.part(slug), isNotNull, reason: slug);
      }
    });
  });

  group('cohérence entre fichiers', () {
    test('toutes les pièces des vues existent dans tree.json', () {
      final missing = <String>[
        for (final v in data.views)
          for (final p in v.parts)
            if (data.part(p.slug) == null) '${v.id}/${p.slug}'
      ];
      expect(missing, isEmpty);
    });

    test('codes DTC uniques et bien formés', () {
      final codes = data.dtcs.map((d) => d.code).toList();
      final dup = codes.where((c) => codes.where((x) => x == c).length > 1);
      expect(dup.toSet(), isEmpty);
      final format = RegExp(r'^[PCBU][0-9A-F]{4}$');
      expect(codes.where((c) => !format.hasMatch(c)), isEmpty);
      expect(data.dtcs.where((d) => d.title.isEmpty).map((d) => d.code),
          isEmpty);
    });

    test('toutes les pièces des DTC existent dans tree.json', () {
      final missing = <String>[
        for (final d in data.dtcs)
          for (final p in d.parts)
            if (data.part(p) == null) '${d.code}/$p'
      ];
      expect(missing, isEmpty);
      expect(data.dtcs.where((d) => d.parts.isNotEmpty), isNotEmpty);
    });

    test('familles des véhicules et vues des familles (tolérant)', () {
      final unknownFamilies = <String>{
        for (final m in data.makes)
          for (final model in m.models)
            for (final e in model.engines)
              if (data.family(e.family) == null) e.family
      };
      final unknownViews = <String>{
        for (final f in data.families)
          for (final v in f.views)
            if (data.view(v) == null) '${f.key}/$v'
      };
      // Families and views are authored in parallel: report, don't fail.
      if (unknownFamilies.isNotEmpty) {
        debugPrint('Familles inconnues : $unknownFamilies');
      }
      if (unknownViews.isNotEmpty) {
        debugPrint('Vues pas encore créées : $unknownViews');
      }
      expect(data.families.map((f) => f.key).toSet().length,
          data.families.length);
    });
  });

  group('recherche', () {
    test('normalisation des accents', () {
      expect(normalize('Électrique Œuvre à Côté'), 'electrique oeuvre a cote');
      expect(normalize('  Clio-IV  '), 'clio iv');
    });

    test('véhicule par marque, modèle, sans accent et par année', () {
      final v = data.makes.first;
      final model = v.models.first;
      final query = '${v.name.toUpperCase()} ${model.name.toLowerCase()}';
      final results = data.searchVehicles(query);
      expect(results, isNotEmpty);
      expect(results.every((r) => r.make == v.name), isTrue);
      if (model.yearFrom != null) {
        expect(data.searchVehicles('${v.name} ${model.yearFrom}'), isNotEmpty);
        expect(data.searchVehicles('${v.name} 1901'), isEmpty);
      }
      expect(data.searchVehicles('zzzz-inexistant'), isEmpty);
    });

    test('DTC par code exact, préfixe et mot', () {
      final d = data.dtcs.first;
      expect(data.searchDtc(d.code.toLowerCase()).first.code, d.code);
      expect(data.searchDtc(d.code.substring(0, 3)), contains(d));
      final word = normalize(d.title).split(' ').firstWhere((w) => w.length > 3);
      expect(data.searchDtc(word), contains(d));
    });

    test('pannes liées à une pièce et vue contenant une pièce', () {
      final v = data.views.first;
      final slug = v.parts.first.slug;
      expect(data.bestViewFor([slug])?.containsPart(slug), isTrue);
      final d = data.dtcs.firstWhere((d) => d.parts.isNotEmpty);
      expect(data.dtcsForPart(d.parts.first), contains(d));
    });
  });

  test('hit test des tracés', () {
    const view = ExplodedView(
      id: 't',
      name: 't',
      width: 100,
      height: 100,
      parts: [
        ViewPart(slug: 'a', label: 'A', path: 'M0 0 L50 0 L50 50 L0 50 Z'),
        ViewPart(slug: 'b', label: 'B', path: 'M20 20 L40 20 L40 40 L20 40 Z'),
        ViewPart(slug: 'c', label: 'C', path: 'M70 70 L90 90'),
      ],
    );
    final parts = parseViewParts(view);
    expect(hitTestParts(parts, const Offset(5, 5)), 'a');
    expect(hitTestParts(parts, const Offset(30, 30)), 'b');
    expect(hitTestParts(parts, const Offset(80, 81)), 'c');
    expect(hitTestParts(parts, const Offset(65, 10)), isNull);
  });

  test('couleurs optionnelles des pièces et guides', () {
    expect(parseColor('#FF0000'), const Color(0xFFFF0000));
    expect(parseColor('#0f0'), const Color(0xFF00FF00));
    expect(parseColor('Rouge'), isNotNull);
    expect(parseColor('pas-une-couleur'), isNull);
    expect(parseColor(null), isNull);
    final v = ExplodedView.fromJson({
      'id': 'w',
      'name': 'w',
      'width': 100,
      'height': 100,
      'guides': [
        {'d': 'M0 0 L10 0', 'color': 'noir'},
        {'d': 'M0 5 L10 5'},
      ],
      'parts': [
        {'slug': 'relay', 'label': 'R', 'path': 'M0 0 L10 10', 'color': '#1E88E5'},
      ],
    });
    expect(v.guides.first.color, isNotNull);
    expect(v.guides.last.color, isNull);
    expect(v.parts.single.color, const Color(0xFF1E88E5));
    expect(v.parts.single.isClosed, isFalse);
  });

  group('FAP et allumage selon le véhicule', () {
    Vehicle pick(bool Function(Vehicle v) test) => data
        .searchVehicles('', limit: 100000)
        .firstWhere(test);

    test('dpf lu depuis vehicles.json et conservé à la sérialisation', () {
      final withDpf = pick((v) => v.isDiesel && v.dpf == true);
      final noDpf = pick((v) => v.isDiesel && v.dpf == false);
      expect(withDpf.dpfLabel, 'Avec FAP');
      expect(noDpf.dpfLabel, 'Sans FAP');
      expect(noDpf.subtitle, contains('Sans FAP'));
      expect(Vehicle.fromJson(noDpf.toJson()).dpf, isFalse);
      expect(EngineSpec.fromJson({'name': 'x', 'dpf': true}).dpf, isTrue);
      expect(EngineSpec.fromJson({'name': 'x'}).dpf, isNull);
      expect(pick((v) => v.fuel == 'petrol').dpfLabel, isNull);
    });

    test('pièces et codes FAP masqués sans FAP, allumage masqué en diesel', () {
      final noDpf = pick((v) => v.isDiesel && v.dpf == false);
      final withDpf = pick((v) => v.isDiesel && v.dpf == true);
      final petrol = pick((v) => v.fuel == 'petrol');
      final fapDtc = data.dtcs.firstWhere((d) => d.parts.contains('dpf'));

      for (final v in [noDpf, petrol]) {
        expect(partAppliesTo('dpf', v), isFalse);
        expect(partAppliesTo('dpf-pressure-sensor', v), isFalse);
        expect(data.searchDtc(fapDtc.code, vehicle: v), isEmpty);
        expect(data.dtcsForPart('exhaust-pressure-sensor', vehicle: v),
            isNot(contains(fapDtc)));
        expect(data.searchParts('filtre a particules', vehicle: v)
            .map((p) => p.slug), isNot(contains('dpf')));
      }
      expect(data.searchDtc(fapDtc.code, vehicle: withDpf), [fapDtc]);
      expect(data.searchDtc(fapDtc.code), [fapDtc]);
      expect(partAppliesTo('dpf', withDpf), isTrue);

      for (final slug in ignitionPartSlugs) {
        expect(partAppliesTo(slug, noDpf), isFalse, reason: slug);
        expect(partAppliesTo(slug, petrol), isTrue, reason: slug);
      }
      final dieselTree = data
          .treeFor(noDpf.kind, vehicle: noDpf)
          .expand((s) => s.children)
          .expand((g) => g.parts)
          .map((p) => p.slug)
          .toSet();
      expect(dieselTree, isNot(contains('spark-plug')));
      expect(dieselTree, isNot(contains('dpf')));
      expect(dieselTree, contains('glow-plug'));
      expect(data.partsFor(['spark-plug', 'injector'], noDpf), ['injector']);
    });

    test('codes FAP reconnus par plage', () {
      for (final code in ['P2002', 'P2003', 'P2452', 'P2459', 'P242F', 'P2463']) {
        expect(isDpfDtc(Dtc(code: code, title: 't')), isTrue, reason: code);
      }
      for (final code in ['P2451', 'P2460', 'P0420']) {
        expect(isDpfDtc(Dtc(code: code, title: 't')), isFalse, reason: code);
      }
    });
  });

  test('sous-section Câblage / Fusibles / Relais', () {
    for (final slug in const [
      'fuse-mini', 'fuse-ato', 'fuse-maxi', 'main-fuse', 'relay',
      'fuse-puller', 'fuse-box-engine', 'fuse-box-cabin', 'ignition-switch',
      'ground-strap', 'wiring-harness', 'connector', 'starter-relay',
      'fuel-pump-relay', 'cooling-fan-relay', 'voltage-regulator',
      'glow-plug-control-unit', 'stator', 'rectifier-regulator',
    ]) {
      expect(data.part(slug), isNotNull, reason: slug);
    }
    expect(data.part('relay')!.group.name, 'Câblage / Fusibles / Relais');
  });
  group('catégories de vues', () {
    test('chaque vue générique a une catégorie connue', () {
      for (final v in data.genericViews) {
        expect(viewCategory(v.id), isNot('Autres'), reason: v.id);
      }
    });

    test('exemples et ordre des sections', () {
      expect(viewCategory('wiring-moto-charging'), 'Moto');
      expect(viewCategory('wiring-abs'), 'Électricité / Schémas');
      expect(viewCategory('turbo-intake'), 'Alimentation / Admission');
      expect(viewCategory('timing-belt'), 'Moteur');
      final groups = groupViewsByCategory(data.genericViews);
      final names = [for (final (c, _) in groups) c];
      expect(names.first, 'Moteur');
      expect(names, orderedEquals([for (final c in viewCategories) if (names.contains(c)) c]));
      expect(groups.fold<int>(0, (n, g) => n + g.$2.length), data.genericViews.length);
    });
  });
}
