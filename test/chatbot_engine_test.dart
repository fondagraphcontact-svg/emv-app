import 'dart:convert';
import 'dart:io';

import 'package:emv/chatbot/chatbot_engine.dart';
import 'package:emv/chatbot/chatbot_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _vehicles = {
  'makes': [
    {
      'name': 'Opel',
      'kind': 'car',
      'models': [
        {
          'name': 'Meriva B',
          'years': [2010, 2017],
          'engines': [
            {'name': '1.4 Turbo 120', 'fuel': 'petrol', 'family': 'petrol-i4-turbo'},
            {'name': '1.7 CDTI 110', 'fuel': 'diesel', 'family': 'diesel-i4-turbo-cr', 'dpf': true},
            {'name': '1.7 CDTI 130', 'fuel': 'diesel', 'family': 'diesel-i4-turbo-cr', 'dpf': true},
          ]
        }
      ]
    },
    {
      'name': 'Renault',
      'kind': 'car',
      'models': [
        {
          'name': 'Laguna II',
          'years': [2001, 2007],
          'engines': [
            {'name': '2.0 dCi 150', 'fuel': 'diesel', 'family': 'diesel-i4-turbo-cr'},
          ]
        },
        {
          'name': 'Laguna III',
          'years': [2007, 2015],
          'engines': [
            {'name': '2.0 16V 140', 'fuel': 'petrol', 'family': 'petrol-i4-na'},
            {'name': '2.0 dCi 150', 'fuel': 'diesel', 'family': 'diesel-i4-turbo-cr', 'dpf': false},
            {'name': '2.0 dCi 150 FAP', 'fuel': 'diesel', 'family': 'diesel-i4-turbo-cr', 'dpf': true},
          ]
        },
        {
          'name': 'Clio IV',
          'years': [2012, 2019],
          'engines': [
            {'name': '0.9 TCe 90', 'fuel': 'petrol', 'family': 'petrol-i3-turbo'},
          ]
        }
      ]
    },
    {
      'name': 'Yamaha',
      'kind': 'moto',
      'models': [
        {
          'name': 'MT-07',
          'years': [2014, 2024],
          'engines': [
            {'name': '689 CP2', 'fuel': 'petrol', 'family': 'moto-twin'},
          ]
        }
      ]
    }
  ]
};

const _dtc = [
  {
    'code': 'P0401',
    'title': 'Débit de recirculation des gaz (EGR) insuffisant',
    'system': 'emissions',
    'causes': ['Vanne EGR encrassée'],
    'diagnostic': ['Contrôler la vanne EGR', 'Contrôler le débitmètre'],
    'parts': ['egr-valve'],
    'severity': 1,
    'fuel': ['petrol', 'diesel']
  },
  {
    'code': 'P0301',
    'title': 'Raté d\'allumage cylindre 1',
    'parts': ['spark-plug', 'ignition-coil'],
    'severity': 2,
    'fuel': ['petrol']
  },
  {
    'code': 'P2002',
    'title': 'Efficacité du filtre à particules insuffisante',
    'parts': ['dpf'],
    'severity': 2,
    'fuel': ['diesel']
  },
  {
    'code': 'P0380',
    'title': 'Circuit de bougie de préchauffage A',
    'parts': ['glow-plug'],
    'severity': 2,
    'fuel': ['diesel']
  },
];

const _noDpfDiesel = VehicleCtx(fuel: 'diesel', family: 'diesel-i4-turbo-cr', dpf: false);
const _dpfDiesel = VehicleCtx(fuel: 'diesel', family: 'diesel-i4-turbo-cr', dpf: true);
const _petrol = VehicleCtx(fuel: 'petrol', family: 'petrol-i4-na');
const _moto = VehicleCtx(fuel: 'petrol', family: 'moto-twin', kind: 'moto');

List<dynamic> _readJsonList(String path) => jsonDecode(File(path).readAsStringSync()) as List<dynamic>;

void main() {
  final kb = _readJsonList('assets/data/chatbot_kb.json');
  final tree = _readJsonList('assets/data/tree.json');
  final engine = ChatbotEngine.fromJson(kb: kb, tree: tree, dtc: _dtc, vehicles: _vehicles);

  Iterable<String> payloads(BotReply r, [BotActionType? t]) =>
      r.actions.where((a) => t == null || a.type == t).map((a) => a.payload);

  group('normalisation', () {
    test('accents, majuscules, ponctuation', () {
      expect(TextTools.normalize('Fumée NOIRE, à l\'accélération !'), 'fumee noire a l acceleration');
      expect(TextTools.normalize('Meriva 1,7cdti'), 'meriva 1.7 cdti');
      expect(TextTools.normalize('Œil'), 'oeil');
    });

    test('stemming et tolérance aux fautes', () {
      expect(TextTools.stem('fumee'), TextTools.stem('fume'));
      expect(TextTools.stem('freins'), TextTools.stem('frein'));
      expect(TextTools.fuzzyEq('surchaufe', 'surchauffe'), isTrue);
      expect(TextTools.fuzzyEq('abs', 'abc'), isFalse);
      expect(TextTools.fuzzyEq('voyant', 'volant'), isFalse);
    });

    test('détection DTC', () {
      expect(engine.detectDtcCodes('j ai p0401 et P2002'), ['P0401', 'P2002']);
      expect(engine.detectDtcCodes('ma C3 de 2011'), isEmpty);
      expect(engine.detectDtcCodes('code U0121'), ['U0121']);
    });
  });

  group('intentions', () {
    test('Meriva 1.7 CDTI + voyant moteur + fumée noire', () {
      final r = engine.reply('ma meriva 1.7 cdti a le voyant moteur et fume noir');
      expect(r.intentId, 'black-smoke');
      expect(r.detectedVehicle, isNotNull);
      expect(r.detectedVehicle!.make, 'Opel');
      expect(r.detectedVehicle!.model, 'Meriva B');
      expect(r.detectedVehicle!.engine, startsWith('1.7 CDTI'));
      expect(r.ctx!.fuel, 'diesel');
      expect(payloads(r, BotActionType.selectVehicle), isNotEmpty);
      expect(r.checks.length, inInclusiveRange(3, 5));
      expect(r.text, contains('Véhicule reconnu'));
    });

    test('P0401 -> action openDtc', () {
      final r = engine.reply('P0401');
      expect(r.dtcCode, 'P0401');
      expect(r.actions.first.type, BotActionType.openDtc);
      expect(r.actions.first.payload, 'P0401');
      expect(payloads(r, BotActionType.openView), contains('egr-valve'));
      expect(r.intentId, 'egr-valve');
    });

    test('code inconnu : description générique, pas de fiche', () {
      final r = engine.reply('j ai le code P1234');
      expect(r.text, contains('constructeur'));
      expect(payloads(r, BotActionType.openDtc), isEmpty);
    });

    test('diesel sans FAP : jamais de FAP proposé', () {
      for (final q in ['fumée noire', 'perte de puissance', 'niveau d huile monte', 'contrôle technique pollution']) {
        final r = engine.reply(q, ctx: _noDpfDiesel);
        expect(r.intentId, isNotNull, reason: q);
        expect(payloads(r), isNot(contains('dpf')), reason: q);
        expect(payloads(r), isNot(contains('P2002')), reason: q);
        expect(r.checks.any((c) => c.contains('FAP')), isFalse, reason: q);
      }
      final fap = engine.reply('mon fap est colmaté', ctx: _noDpfDiesel);
      expect(fap.intentId, isNot('dpf-clogged'));
      expect(fap.text, contains('sans FAP'));
      expect(payloads(fap), isNot(contains('dpf')));
    });

    test('diesel avec FAP : le FAP est proposé', () {
      final r = engine.reply('fap colmaté', ctx: _dpfDiesel);
      expect(r.intentId, 'dpf-clogged');
      expect(payloads(r, BotActionType.openView), contains('dpf'));
      expect(payloads(r, BotActionType.openDtc), contains('P2002'));
      final p = engine.reply('perte de puissance', ctx: _dpfDiesel);
      expect(p.checks.any((c) => c.contains('FAP')), isTrue);
    });

    test('diesel : pas de bougies d allumage, essence : pas de préchauffage', () {
      final d = engine.reply('démarrage difficile à froid', ctx: _noDpfDiesel);
      expect(d.intentId, 'hard-start-cold');
      expect(payloads(d), isNot(contains('spark-plug')));
      expect(payloads(d), contains('glow-plug'));
      final p = engine.reply('démarrage difficile à froid', ctx: _petrol);
      expect(payloads(p), isNot(contains('glow-plug')));
      expect(p.checks.any((c) => c.contains('préchauffage')), isFalse);
      expect(payloads(engine.reply('bougie', ctx: _noDpfDiesel)), isNot(contains('spark-plug')));
    });

    test('essence : le voyant préchauffage est signalé hors sujet', () {
      final r = engine.reply('voyant préchauffage', ctx: _petrol);
      expect(r.intentId, isNot('glow-plug-light'));
      expect(r.text, contains('diesel'));
    });

    test('Laguna 3 dCi 150 sans FAP -> sélection véhicule', () {
      final r = engine.reply('Laguna 3 dCi 150');
      final v = r.detectedVehicle!;
      expect(v.model, 'Laguna III');
      expect(v.engine, '2.0 dCi 150');
      expect(v.dpf, isFalse);
      expect(r.actions.first.type, BotActionType.selectVehicle);
      expect(r.actions.first.vehicle, isNotNull);
    });

    test('modèle sans motorisation -> liste de motorisations', () {
      final r = engine.reply('clio 4');
      expect(r.text, contains('Précisez la motorisation'));
      expect(payloads(r, BotActionType.selectVehicle), isNotEmpty);
    });

    test('symptômes clés reconnus', () {
      const cases = {
        'ça claque au ralenti': 'knock-idle',
        'elle ne démarre pas': 'no-start-cranks',
        'batterie à plat': 'battery-dead',
        'voyant préchauffage qui clignote': 'glow-plug-light',
        'voyant ABS allumé': 'abs-light',
        'surchauffe moteur': 'overheating',
        'fuite d\'huile sous la voiture': 'oil-leak',
        'clic quand je tourne la clé': 'no-start-click',
        'fusible qui grille à répétition': 'fuse-blown',
        'comment tester un fusible': 'fuse-test',
        'relais qui claque': 'relay-clicking',
        'clignotant rapide': 'indicator-fast',
        'voyant batterie allumé en roulant': 'battery-light',
        'klaxon muet': 'horn-wipers',
        'embrayage qui patine': 'clutch-slipping',
        'la clim ne refroidit pas': 'ac-not-cold',
        'surchaufe': 'overheating',
      };
      cases.forEach((q, id) => expect(engine.reply(q).intentId, id, reason: q));
    });

    test('actions vers schémas électriques', () {
      final r = engine.reply('fusible qui grille');
      expect(payloads(r, BotActionType.openViewId), contains('fuse-box-generic'));
      expect(r.safety, isNotNull);
      final s = engine.reply('le démarreur clique', ctx: _petrol);
      expect(payloads(s, BotActionType.openViewId), contains('wiring-starting'));
    });

    test('moto : intentions moto et pas de pièces voiture', () {
      final r = engine.reply('ma moto batterie se décharge', ctx: _moto);
      expect(r.intentId, 'moto-charging');
      expect(payloads(r, BotActionType.openViewId), contains('wiring-moto-charging'));
      final c = engine.reply('embrayage qui patine', ctx: _moto);
      expect(c.intentId, isNot('clutch-slipping'));
      final mt = engine.reply('MT-07 chaîne détendue');
      expect(mt.detectedVehicle?.model, 'MT-07');
      expect(mt.intentId, 'moto-chain-maintenance');
    });

    test('nom de pièce seul -> fiche pièce + vue', () {
      final r = engine.reply('débitmètre');
      expect(payloads(r, BotActionType.openView).first, 'maf-sensor');
    });

    test('rien compris -> 6 suggestions', () {
      final r = engine.reply('blabla xyz');
      expect(r.intentId, isNull);
      expect(r.suggestions.length, 6);
    });
  });

  group('négation', () {
    List<String> negated(String q) {
      final a = TextTools.analyze(q);
      return [for (var i = 0; i < a.tokens.length; i++) if (a.negated[i]) a.tokens[i]];
    }

    test('portée de la négation limitée à la proposition', () {
      expect(negated('le moteur ne chauffe pas'), [TextTools.stem('chauffe')]);
      expect(negated('pas de fumée noire à l\'accélération'), ['fum', 'noir']);
      expect(negated('sans fumée, le turbo siffle'), ['fum']);
      expect(negated('aucun voyant mais elle cale'), ['voyant']);
      expect(negated('ça démarre pas'), ['demarr']);
      expect(negated('la batterie n\'est pas à plat'), ['plat']);
      expect(negated('plus de chauffage'), ['chauffag']);
      expect(negated('elle consomme plus de gasoil'), isEmpty);
      expect(negated('ne marche que le matin'), isEmpty);
      expect(negated('fume noir et ne démarre plus'), ['demarr']);
      expect(negated('ne démarre pas puis cale'), ['demarr']);
      expect(negated('moteur 1.7 cdti, pas de fap'), ['fap']);
    });

    test('negated_patterns : la forme niée alimente l intention inverse', () {
      final e = ChatbotEngine(intents: const [
        KbIntent(id: 'hot', patterns: ['moteur chauffe'], answer: 'chaud'),
        KbIntent(id: 'cold', patterns: ['moteur froid'], negatedPatterns: ['moteur chauffe'], answer: 'froid'),
      ]);
      expect(e.reply('le moteur chauffe').intentId, 'hot');
      expect(e.reply('le moteur ne chauffe pas').intentId, 'cold');
      expect(e.reply('le moteur chauffe pas').intentId, 'cold');
      expect(e.reply('le moteur ne chauffe jamais').intentId, 'cold');
    });

    test('pattern déjà négatif : exige la négation dans le message', () {
      final e = ChatbotEngine(intents: const [
        KbIntent(id: 'no-start', patterns: ['ne demarre pas'], answer: 'a'),
        KbIntent(id: 'start-ok', patterns: ['demarre bien'], answer: 'b'),
      ]);
      expect(e.reply('elle ne démarre pas').intentId, 'no-start');
      expect(e.reply('elle démarre pas').intentId, 'no-start');
      expect(e.reply('elle démarre bien').intentId, 'start-ok');
    });
  });

  group('FAP selon engine.dpf', () {
    const dieselUnknown = VehicleCtx(fuel: 'diesel', family: 'diesel-i4-turbo-cr');
    const hybridDiesel = VehicleCtx(fuel: 'hybrid', family: 'diesel-i4-turbo-cr', dpf: true);
    const hybridPetrol = VehicleCtx(fuel: 'hybrid', family: 'hybrid-petrol');

    test('état FAP déduit du moteur', () {
      expect(dieselUnknown.hasDpf, isNull);
      expect(hybridDiesel.hasDpf, isTrue);
      expect(_noDpfDiesel.hasDpf, isFalse);
      expect(_petrol.hasDpf, isFalse);
      expect(hybridPetrol.hasDpf, isFalse);
      expect(const VehicleCtx(fuel: 'hybrid', family: 'diesel-i4-turbo-cr').hasDpf, isNull);
    });

    test('hybride diesel avec FAP : FAP proposé sans réserve, pas de bougie d allumage', () {
      final r = engine.reply('fap colmaté', ctx: hybridDiesel);
      expect(r.intentId, 'dpf-clogged');
      expect(payloads(r, BotActionType.openView), contains('dpf'));
      final p = engine.reply('perte de puissance', ctx: hybridDiesel);
      expect(p.checks.where((c) => c.contains('FAP')), isNotEmpty);
      expect(p.checks.any((c) => c.endsWith(ChatbotEngine.dpfUnknownSuffix)), isFalse);
      expect(engine.partCompatible('spark-plug', hybridDiesel), isFalse);
      expect(engine.partCompatible('glow-plug', hybridDiesel), isTrue);
      expect(engine.partCompatible('hv-battery', hybridDiesel), isTrue);
    });

    test('diesel FAP inconnu : contrôles FAP suffixés « (si équipé) », FAP non exclu', () {
      final p = engine.reply('perte de puissance', ctx: dieselUnknown);
      expect(p.checks.where((c) => c.contains('FAP')).single, endsWith(ChatbotEngine.dpfUnknownSuffix));
      expect(engine.reply('fap colmaté', ctx: dieselUnknown).intentId, 'dpf-clogged');
      expect(engine.dtcCompatible('P2002', dieselUnknown), isTrue);
      expect(ChatbotEngine.displayCheck('[dpf] Contrôlez le FAP.', dieselUnknown), 'Contrôlez le FAP (si équipé).');
      expect(ChatbotEngine.displayCheck('[dpf] Contrôlez le FAP', _dpfDiesel), 'Contrôlez le FAP');
    });

    test('hybride essence : pas de FAP', () {
      expect(engine.reply('perte de puissance', ctx: hybridPetrol).checks.any((c) => c.contains('FAP')), isFalse);
      expect(engine.partCompatible('dpf', hybridPetrol), isFalse);
    });
  });

  test('tree.json : pièces haute tension communes voiture et moto électrique', () {
    const motoEv = VehicleCtx(fuel: 'electric', family: 'moto-electric', kind: 'moto');
    expect(engine.partCompatible('hv-battery', motoEv), isTrue);
    expect(engine.partCompatible('electric-motor', motoEv), isTrue);
    expect(engine.partCompatible('planet-gear', motoEv), isFalse);
    expect(engine.partCompatible('planet-gear', const VehicleCtx(fuel: 'hybrid', family: 'hybrid-petrol')), isTrue);
  });

  testWidgets('ChatbotScreen : envoi + bouton d action -> callback', (tester) async {
    String? openedDtc;
    VehicleEntry? selected;
    await tester.pumpWidget(MaterialApp(
      home: ChatbotScreen(
        engine: engine,
        onOpenView: (_) {},
        onOpenDtc: (c) => openedDtc = c,
        onSelectVehicle: (v) => selected = v,
      ),
    ));
    await tester.enterText(find.byType(TextField), 'P0401');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fiche code P0401'));
    expect(openedDtc, 'P0401');

    await tester.enterText(find.byType(TextField), 'Laguna 3 dCi 150');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    final choose = find.text('Choisir ce véhicule : Renault Laguna III 2.0 dCi 150');
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(selected?.engine, '2.0 dCi 150');
    expect(find.textContaining('Véhicule choisi'), findsOneWidget);
  });

  group('cohérence chatbot_kb.json', () {
    final partSlugs = {for (final p in PartInfo.listFromTree(tree)) p.slug};
    final sections = {
      for (final s in tree)
        for (final c in (s as Map<String, dynamic>)['children'] as List) (c as Map<String, dynamic>)['slug'] as String
    };
    final intents = [for (final k in kb) KbIntent.fromJson(k as Map<String, dynamic>)];

    test('80+ intentions, ids uniques', () {
      expect(intents.length, greaterThanOrEqualTo(80));
      expect(intents.map((i) => i.id).toSet().length, intents.length);
    });

    test('pièces et sections existent dans tree.json', () {
      for (final i in intents) {
        for (final p in i.parts) {
          expect(partSlugs, contains(p), reason: '${i.id} -> $p');
        }
        if (i.section.isNotEmpty) expect(sections, contains(i.section), reason: i.id);
      }
    });

    test('codes DTC bien formés', () {
      for (final i in intents) {
        for (final c in i.dtc) {
          expect(ChatbotEngine.dtcRegex.hasMatch(c), isTrue, reason: '${i.id} -> $c');
        }
      }
    });

    test('vehicles.json réel : Meriva B 1.7 CDTI 2011', () {
      final f = File('assets/data/vehicles.json');
      final real = ChatbotEngine.fromJson(
          kb: kb, tree: tree, vehicles: jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      final r = real.reply('Opel Meriva 1.7 CDTI 2011');
      expect(r.detectedVehicle?.model, 'Meriva B');
      expect(r.detectedVehicle?.fuel, 'diesel');
    });
  });
}
