import 'dart:convert';

import 'package:emv/chatbot/chatbot_engine.dart';
import 'package:emv/data.dart';
import 'package:emv/guides/guide_assets.dart';
import 'package:emv/lights/light_assets.dart';
import 'package:emv/models.dart';
import 'package:emv/precheck/precheck_assets.dart';
import 'package:emv/precheck/precheck_models.dart';
import 'package:emv/precheck/precheck_screen.dart';
import 'package:emv/precheck/precheck_store.dart';
import 'package:emv/report/report_pdf.dart';
import 'package:emv/screens/assistant.dart';
import 'package:emv/screens/faults.dart';
import 'package:emv/state.dart';
import 'package:emv/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _diesel = Vehicle(
    make: 'Renault',
    model: 'Laguna III',
    engine: '2.0 dCi 150',
    fuel: 'diesel',
    family: 'diesel-i4-turbo-cr',
    kind: VehicleKind.car);
const _petrol = Vehicle(
    make: 'Renault',
    model: 'Clio IV',
    engine: '0.9 TCe 90',
    fuel: 'petrol',
    family: 'petrol-i3-turbo',
    kind: VehicleKind.car);
const _moto = Vehicle(
    make: 'Yamaha',
    model: 'MT-07',
    engine: '689',
    fuel: 'petrol',
    family: 'moto-twin',
    kind: VehicleKind.moto);

void main() {
  late AppData data;
  late PrecheckData pre;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
    pre = await loadPrecheck();
    await loadLights();
    await loadGuides();
  });

  group('données', () {
    test('au moins 60 points voiture et 25 moto, ids uniques', () {
      final ids = pre.points.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(pre.points.where((p) => p.kind == VehicleKind.car).length,
          greaterThanOrEqualTo(60));
      expect(pre.points.where((p) => p.kind == VehicleKind.moto).length,
          greaterThanOrEqualTo(25));
    });

    test('fonctions et niveaux valides, textes renseignés', () {
      final fns = pre.functions.map((f) => f.id).toSet();
      expect(fns, hasLength(9));
      expect(pre.levels.map((l) => l.id), precheckLevels);
      for (final p in pre.points) {
        expect(fns, contains(p.function), reason: p.id);
        expect(precheckLevels, contains(p.level), reason: p.id);
        expect(p.title.trim(), isNotEmpty, reason: p.id);
        expect(p.check.trim(), isNotEmpty, reason: p.id);
        expect(p.advice.trim(), isNotEmpty, reason: p.id);
      }
      expect(pre.disclaimer, contains('ne remplace pas'));
    });

    test('liens pièce / guide / voyant existants', () async {
      final guides = {for (final g in await loadGuides()) g.id};
      final lights = {for (final l in await loadLights()) l.id};
      for (final p in pre.points) {
        if (p.part != null) {
          expect(data.part(p.part!), isNotNull, reason: '${p.id} ${p.part}');
        }
        if (p.guide != null) expect(guides, contains(p.guide), reason: p.id);
        if (p.light != null) expect(lights, contains(p.light), reason: p.id);
      }
    });

    test('filtre voiture / moto et carburant', () {
      final moto = pre.pointsFor(_moto);
      expect(moto, isNotEmpty);
      expect(moto.every((p) => p.kind == VehicleKind.moto), isTrue);
      final petrol = pre.pointsFor(_petrol).map((p) => p.id);
      expect(petrol, isNot(contains('car-diesel-smoke')));
      expect(petrol, contains('car-petrol-emissions'));
      final diesel = pre.pointsFor(_diesel).map((p) => p.id);
      expect(diesel, contains('car-diesel-smoke'));
      expect(diesel, isNot(contains('car-petrol-emissions')));
      expect(diesel, isNot(contains('moto-chain')));
    });
  });

  group('store', () {
    test('persistance par véhicule sous precheck.<id>, remise à zéro',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PrecheckStore.of(prefs);
      await store.set(_diesel.id, 'car-plates', PrecheckStatus.ok);
      await store.set(_diesel.id, 'car-tyre-damage', PrecheckStatus.todo);
      await store.set(_petrol.id, 'car-wipers', PrecheckStatus.todo);

      final raw = prefs.getString('precheck.${_diesel.id}');
      expect(jsonDecode(raw!), {'car-plates': 'ok', 'car-tyre-damage': 'todo'});

      // Relecture depuis les préférences (nouvelle instance).
      final fresh = PrecheckStore.of(await _reload(prefs));
      expect(fresh.status(_diesel.id, 'car-tyre-damage'), PrecheckStatus.todo);
      expect(fresh.status(_diesel.id, 'car-wipers'), PrecheckStatus.unchecked);
      expect(fresh.status(_petrol.id, 'car-wipers'), PrecheckStatus.todo);

      await store.set(_diesel.id, 'car-plates', PrecheckStatus.unchecked);
      expect(store.statuses(_diesel.id).keys, ['car-tyre-damage']);
      await store.reset(_diesel.id);
      expect(store.statuses(_diesel.id), isEmpty);
      expect(prefs.containsKey('precheck.${_diesel.id}'), isFalse);
      expect(store.status(_petrol.id, 'car-wipers'), PrecheckStatus.todo);
    });

    test('valeur corrompue ignorée', () async {
      SharedPreferences.setMockInitialValues(
          {'precheck.${_moto.id}': '{"moto-chain":"todo","x":"bof"'});
      final store = PrecheckStore.of(await SharedPreferences.getInstance());
      expect(store.statuses(_moto.id), isEmpty);
    });

    test('synthèse et rapport : à voir par niveau, critiques d\'abord', () {
      final status = {
        'car-plates': PrecheckStatus.ok,
        'car-tyre-damage': PrecheckStatus.todo,
        'car-wipers': PrecheckStatus.todo,
        'car-horn': PrecheckStatus.todo,
      };
      PrecheckStatus get(String id) => status[id] ?? PrecheckStatus.unchecked;
      final points = pre.pointsFor(_diesel);
      final s = PrecheckSummary.of(points, get);
      expect(s.ok, 1);
      expect(s.todoByLevel, {'mineure': 1, 'majeure': 1, 'critique': 1});
      expect(s.unchecked, points.length - 4);
      final r = PrecheckReport.of(pre, _diesel, get);
      expect(r.todo.first.point.id, 'car-tyre-damage');
      expect(r.todo.first.function, 'Liaisons au sol');
      expect(r.isEmpty, isFalse);
    });

    test('PDF avec section pré-contrôle', () async {
      final r = PrecheckReport.of(pre, _diesel,
          (id) => id == 'car-wipers' ? PrecheckStatus.todo : PrecheckStatus.unchecked);
      final bytes = await buildReportPdf(
        ReportInput(
          vehicle: _diesel,
          symptoms: '',
          codes: const [],
          maintenance: const [],
          generatedAt: DateTime(2026, 10, 27),
          precheck: r,
        ),
        theme: await loadReportTheme(),
      );
      expect(bytes.length, greaterThan(1000));
    });
  });

  group('écrans', () {
    Future<AppState> pump(WidgetTester tester, Widget home,
        {Vehicle? vehicle, Map<String, Object> prefs = const {}}) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(
          {'disclaimer.accepted': true, ...prefs});
      final state = AppState(data, await SharedPreferences.getInstance());
      if (vehicle != null) await state.setVehicle(vehicle);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: home),
      ));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('widget synthèse : compteurs et message prudent',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: PrecheckSummaryCard(
            summary: const PrecheckSummary(
                total: 10,
                ok: 3,
                todoByLevel: {'mineure': 1, 'majeure': 2, 'critique': 1}),
            levels: pre.levels,
          ),
        ),
      ));
      expect(find.text('7/10 points vérifiés'), findsOneWidget);
      expect(find.text('OK : 3'), findsOneWidget);
      expect(find.text('À voir majeure : 2'), findsOneWidget);
      expect(find.text('À voir critique : 1'), findsOneWidget);
      expect(find.text('Non vérifié : 3'), findsOneWidget);
      expect(find.textContaining('avant de rouler'), findsOneWidget);
      expect(find.text(precheckCaution), findsOneWidget);
    });

    testWidgets('carte Diagnostic → checklist, cocher puis remise à zéro',
        (tester) async {
      final state = await pump(tester, const FaultsScreen(), vehicle: _petrol);
      expect(find.byKey(const Key('lights-entry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('precheck-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(PrecheckScreen), findsOneWidget);
      expect(find.text('Identification'), findsOneWidget);
      expect(find.text('À voir critique : 0'), findsOneWidget);

      await tester.ensureVisible(find.text('Identification'));
      await tester.tap(find.text('Identification'));
      await tester.pumpAndSettle();
      final seg = find.descendant(
          of: find.byKey(const Key('precheck-status-car-plates')),
          matching: find.text('À voir'));
      await tester.ensureVisible(seg);
      await tester.tap(seg);
      await tester.pumpAndSettle();
      final store = PrecheckStore.of(state.prefs);
      expect(store.status(_petrol.id, 'car-plates'), PrecheckStatus.todo);
      expect(state.prefs.getString('precheck.${_petrol.id}'), contains('todo'));

      await tester.tap(find.byKey(const Key('precheck-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('precheck-reset-confirm')));
      await tester.pumpAndSettle();
      expect(store.statuses(_petrol.id), isEmpty);
    });

    testWidgets('moto : seules les fonctions moto, cases restaurées',
        (tester) async {
      await pump(tester, const PrecheckScreen(vehicle: _moto),
          vehicle: _moto,
          prefs: {'precheck.${_moto.id}': '{"moto-chain":"todo"}'});
      expect(find.text('Yamaha MT-07'), findsOneWidget);
      expect(find.text('1/${pre.pointsFor(_moto).length} points vérifiés'),
          findsOneWidget);
      await tester.ensureVisible(find.text('Liaisons au sol'));
      await tester.tap(find.text('Liaisons au sol'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const Key('precheck-point-moto-chain')), 200);
      expect(find.byKey(const Key('precheck-point-car-tyre-tread')), findsNothing);
    });

    testWidgets('sans véhicule : message et pas de navigation',
        (tester) async {
      await pump(tester, const FaultsScreen());
      await tester.tap(find.byKey(const Key('precheck-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(PrecheckScreen), findsNothing);
      expect(find.textContaining('Choisissez d\'abord un véhicule'),
          findsOneWidget);
    });
  });

  group('chatbot', () {
    late ChatbotEngine engine;
    setUpAll(() async => engine = await sharedChatbotEngine());

    bool hasPrecheck(BotReply r) =>
        r.actions.any((a) => a.type == BotActionType.openPrecheck);

    test('contrôle technique → action openPrecheck', () {
      for (final q in ['contrôle technique', 'préparer le CT', 'pré-contrôle', 'contre-visite']) {
        final r = engine.reply(q);
        expect(hasPrecheck(r), isTrue, reason: q);
        expect(r.text, isNot(contains('pas compris')), reason: q);
      }
      expect(engine.reply('contrôle technique', ctx: const VehicleCtx(kind: 'moto')).text,
          contains('deux-roues'));
    });

    test('intention existante conservée, action ajoutée', () {
      final r = engine.reply('refusé au contrôle technique pour l\'opacité');
      expect(r.intentId, 'emissions-test-fail');
      expect(hasPrecheck(r), isTrue);
    });

    test('sans rapport avec le CT : pas d\'action', () {
      expect(hasPrecheck(engine.reply('voyant huile')), isFalse);
      expect(hasPrecheck(engine.reply('fumée noire')), isFalse);
    });
  });
}

Future<SharedPreferences> _reload(SharedPreferences prefs) async {
  final values = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}
