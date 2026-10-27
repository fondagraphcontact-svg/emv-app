import 'dart:convert';

import 'package:emv/data.dart';
import 'package:emv/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppData data;

  setUpAll(() async {
    data = await AppData.load(rootBundle);
  });

  Vehicle find(String make, String model, String engine) {
    for (final m in data.makes.where((m) => m.name == make)) {
      for (final mo in m.models.where((mo) => mo.name == model)) {
        for (final e in mo.engines.where((e) => e.name == engine)) {
          return Vehicle(
              make: m.name,
              model: mo.name,
              engine: e.name,
              fuel: e.fuel,
              family: e.family,
              code: e.code,
              kind: m.kind,
              yearFrom: mo.yearFrom,
              yearTo: mo.yearTo,
              dpf: e.dpf);
        }
      }
    }
    throw StateError('$make $model $engine absent de vehicles.json');
  }

  group('vues spécifiques moteur', () {
    test('engine_specs chargé avec A17DT, A17DTR, A17DTS et M9R', () {
      expect(data.engineSpecs.length, greaterThanOrEqualTo(45));
      for (final c in ['A17DT', 'A17DTR', 'A17DTS', 'M9R']) {
        expect(data.engineSpec(c), isNotNull, reason: c);
      }
    });

    test('chaque code de engine_views existe dans engine_specs', () {
      expect(data.engineViews, isNotEmpty);
      for (final code in data.engineViews.keys) {
        expect(data.engineSpec(code)?.code, code);
      }
    });

    test('chaque vue de engine_views existe et est marquée specific', () {
      for (final e in data.engineViews.entries) {
        expect(e.value, hasLength(3));
        for (final id in e.value) {
          final v = data.view(id);
          expect(v, isNotNull, reason: id);
          expect(v!.specific, isTrue, reason: id);
          expect(v.engineCode, e.key, reason: id);
          expect(v.parts.length, inInclusiveRange(15, 40), reason: id);
        }
      }
    });

    test('les pièces des vues spécifiques existent dans tree.json', () {
      for (final v in data.views.where((v) => v.specific)) {
        for (final p in v.parts) {
          expect(data.part(p.slug), isNotNull, reason: '${v.id}/${p.slug}');
        }
      }
    });

    test('les vues spécifiques ne sont pas listées sans véhicule', () {
      expect(data.viewsFor(null).where((v) => v.specific), isEmpty);
    });

    test('Meriva B 1.7 CDTI (110 et 130) a des vues spécifiques', () {
      final v130 = find('Opel', 'Meriva B', '1.7 CDTI 130');
      expect(data.engineSpecFor(v130)?.code, 'A17DTS');
      expect(data.specificViewsFor(v130).map((v) => v.id),
          containsAll(['engine-A17DTS', 'head-A17DTS', 'timing-A17DTS']));
      final v110 = find('Opel', 'Meriva B', '1.7 CDTI 110');
      expect(data.engineSpecFor(v110)?.code, 'A17DTC');
      expect(data.specificViewsFor(v110), hasLength(3));
    });

    test('Laguna III 2.0 dCi 150 a les vues M9R', () {
      final v = find('Renault', 'Laguna III', '2.0 dCi 150');
      expect(data.engineSpecFor(v)?.code, 'M9R');
      expect(data.specificViewsFor(v).map((v) => v.id),
          ['engine-M9R', 'head-M9R', 'timing-M9R']);
    });

    test('codes multiples séparés par / et alias', () {
      const v = Vehicle(
          make: 'Opel',
          model: 'X',
          engine: '1.7 CDTI',
          fuel: 'diesel',
          family: 'diesel-i4-turbo-cr',
          kind: VehicleKind.car,
          code: 'XXX/A17DTR');
      expect(data.engineSpecFor(v)?.code, 'A17DTR');
      expect(data.engineSpec('a17dte')?.code, 'A17DTC');
    });

    test('un code inconnu ne retombe pas sur les règles de nom', () {
      const v = Vehicle(
          make: 'Volkswagen',
          model: 'Golf V',
          engine: '2.0 TDI 140',
          fuel: 'diesel',
          family: 'diesel-i4-turbo-cr',
          kind: VehicleKind.car,
          code: 'ZZZ999');
      expect(data.engineSpecFor(v), isNull);
    });

    test('containsToken respecte les limites de mots', () {
      expect(containsToken('1.6 TDI 105', '1.6 TDI'), isTrue);
      expect(containsToken('1250 cm³', '125'), isFalse);
      expect(containsToken('1.25', '125'), isFalse);
    });
  });

  group('fiches modèle', () {
    test('chaque clé de model_specs existe dans vehicles.json', () async {
      final raw = jsonDecode(
          await rootBundle.loadString('assets/data/model_specs.json')) as List;
      final keys = {
        for (final m in data.makes)
          for (final mo in m.models) '${m.name}|${mo.name}'
      };
      expect(raw, isNotEmpty);
      for (final j in raw) {
        expect(keys, contains((j as Map)['key']));
      }
    });

    test('Meriva B et Laguna III ont une fiche', () {
      final meriva = find('Opel', 'Meriva B', '1.7 CDTI 130');
      final laguna = find('Renault', 'Laguna III', '2.0 dCi 150');
      expect(data.modelSpecFor(meriva), isNotNull);
      expect(data.modelSpecFor(laguna), isNotNull);
    });

    test('les points faibles sont filtrés sur le moteur', () {
      final diesel = find('Opel', 'Meriva B', '1.7 CDTI 130');
      final titles = data.issuesFor(diesel).map((i) => i.title).join('|');
      expect(titles, contains('1.7 CDTI'));
      expect(titles, isNot(contains('1.4 Turbo')));
    });

    test('les vues de la fiche existent', () {
      for (final m in data.modelSpecs) {
        for (final id in m.views) {
          expect(data.view(id), isNotNull, reason: '${m.key}: $id');
        }
      }
    });
  });

  group('hybrides diesel et kind des pièces', () {
    test('Mercedes C 300 h = hybride diesel OM651', () {
      final v = find('Mercedes-Benz', 'Classe C (W205)', 'C 300 h 231');
      expect(v.family, 'hybrid-diesel');
      expect(v.isDiesel, isTrue);
      expect(v.mayHaveDpf, isTrue);
      expect(data.engineSpecFor(v)?.code, 'OM651');
      expect(partAppliesTo('spark-plug', v), isFalse);
      final ids = data.viewsFor(v).map((x) => x.id).toList();
      expect(ids, containsAll(['hybrid-drive', 'engine-diesel-i4', 'exhaust-dpf-scr']));
    });

    test('les pièces car ne sortent pas pour une moto', () {
      final carOnly = [
        for (final s in data.tree)
          for (final g in s.children)
            for (final p in g.parts)
              if (p.kind == VehicleKind.car) p.slug
      ];
      expect(carOnly, isNotEmpty);
      final moto = {
        for (final s in data.treeFor(VehicleKind.moto))
          for (final g in s.children)
            for (final p in g.parts) p.slug
      };
      for (final slug in carOnly) {
        expect(moto, isNot(contains(slug)));
      }
    });
  });

  group('libellés de la fiche moteur', () {
    test('chaque valeur de engine_specs.json a un libellé français', () {
      for (final s in data.engineSpecs) {
        final pairs = {
          'layout': (s.layout, s.layoutLabel),
          'timing': (s.timing, s.timingLabel),
          'fuel': (s.fuel, fuelLabel(s.fuel)),
          'injection': (s.injection, s.injectionLabel),
          'turbo': (s.turbo, s.turboLabel),
          'dpf': (s.dpf, s.dpfLabel),
          'cooling': (s.cooling, s.coolingLabel),
        };
        for (final MapEntry(key: k, value: (raw, label)) in pairs.entries) {
          expect(label, isNot(raw), reason: '${s.code}.$k « $raw » sans libellé');
        }
      }
    });

    test('V, boxer, ligne, injecteurs-pompes, VGT, biturbo', () {
      const v6 = EngineSpecInfo(
          code: 'X', name: 'x', cylinders: 6, layout: 'v', vAngle: 90);
      expect(v6.layoutLabel, '6 cylindres en V à 90° (V6)');
      expect(const EngineSpecInfo(code: 'X', name: 'x', layout: 'boxer').layoutLabel,
          contains('boxer'));
      expect(const EngineSpecInfo(code: 'X', name: 'x').layoutLabel,
          '4 cylindres en ligne');
      expect(const EngineSpecInfo(code: 'X', name: 'x', injection: 'unit-injector')
          .injectionLabel, 'injecteurs-pompes');
      expect(const EngineSpecInfo(code: 'X', name: 'x', turbo: 'vgt').turboLabel,
          'turbo à géométrie variable');
      expect(const EngineSpecInfo(code: 'X', name: 'x', turbo: 'twin').turboLabel,
          'biturbo');
      expect(const EngineSpecInfo(code: 'X', name: 'x', turbo: 'supercharger').turboLabel,
          'compresseur mécanique');
      expect(const EngineSpecInfo(code: 'X', name: 'x', injection: 'distributor-pump')
          .injectionLabel, contains('pompe distributrice'));
      final real = data.engineSpecs.where((e) => e.layout == 'v');
      expect(real, isNotEmpty);
      for (final e in real) {
        expect(e.layoutLabel, contains('en V'));
      }
    });
  });
}
