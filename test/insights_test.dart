import 'dart:io';

import 'package:emv/chatbot/chatbot_engine.dart';
import 'package:emv/chatbot/chatbot_screen.dart';
import 'package:emv/data.dart';
import 'package:emv/insights/insight_engine.dart';
import 'package:emv/insights/insights_section.dart';
import 'package:emv/insights/urgency.dart';
import 'package:emv/models.dart';
import 'package:emv/screens/assistant.dart';
import 'package:emv/screens/faults.dart';
import 'package:emv/state.dart';
import 'package:emv/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const meriva = Vehicle(
    make: 'Opel',
    model: 'Meriva B',
    engine: '1.7 CDTI 110',
    fuel: 'diesel',
    family: 'diesel-i4-turbo-cr',
    kind: VehicleKind.car,
    code: 'A17DT',
    yearFrom: 2010,
    yearTo: 2017,
    dpf: true);

const laguna = Vehicle(
    make: 'Renault',
    model: 'Laguna III',
    engine: '2.0 dCi 150',
    fuel: 'diesel',
    family: 'diesel-i4-turbo-cr',
    kind: VehicleKind.car,
    code: 'M9R',
    yearFrom: 2007,
    yearTo: 2015,
    dpf: false);

const lagunaFap = Vehicle(
    make: 'Renault',
    model: 'Laguna III',
    engine: '2.0 dCi 150 FAP',
    fuel: 'diesel',
    family: 'diesel-i4-turbo-cr',
    kind: VehicleKind.car,
    code: 'M9R',
    yearFrom: 2007,
    yearTo: 2015,
    dpf: true);

Iterable<Vehicle> allVehicles(AppData data) sync* {
  for (final m in data.makes) {
    for (final model in m.models) {
      for (final e in model.engines) {
        yield Vehicle(
            make: m.name,
            model: model.name,
            engine: e.name,
            fuel: e.fuel,
            family: e.family,
            code: e.code,
            kind: m.kind,
            yearFrom: model.yearFrom,
            yearTo: model.yearTo,
            dpf: e.dpf);
      }
    }
  }
}

/// Share of (covered engine version x complete code) pairs with at least one
/// insight; [step] samples one version out of [step].
(int, int) coverage(AppData data, {int step = 1}) {
  final engine = InsightEngine.of(data);
  final complete = [
    for (final d in data.dtcs)
      if (d.causes.isNotEmpty && d.diagnostic.isNotEmpty) d
  ];
  var pairs = 0, hits = 0, i = 0;
  for (final v in allVehicles(data)) {
    if (i++ % step != 0) continue;
    if (data.engineSpecFor(v) == null && data.modelSpecFor(v) == null) continue;
    for (final d in complete) {
      if (!dtcAppliesTo(d, v)) continue;
      if (d.fuel.isNotEmpty &&
          !d.fuel.contains(v.fuel) &&
          !(v.isDiesel && d.fuel.contains('diesel'))) {
        continue;
      }
      pairs++;
      if (engine.forDtc(d, v).isNotEmpty) hits++;
    }
  }
  return (pairs, hits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppData data;
  late InsightEngine engine;

  setUpAll(() async {
    data = await AppData.load(rootBundle);
    engine = InsightEngine.of(data);
  });

  List<Insight> run(String code, Vehicle? v) => engine.forDtc(data.dtc(code)!, v);

  group('badge d\'urgence', () {
    test('libellés et couleurs par sévérité', () {
      expect(Urgency.of(1).label, 'Peut rouler, à surveiller');
      expect(Urgency.of(2).label, 'Garage sous peu');
      expect(Urgency.of(3).label, 'Arrêt conseillé');
      expect(Urgency.of(0).level, 1);
      expect(Urgency.of(9).level, 3);
      expect(Urgency.of(1).color, EmvColors.severity(1));
      expect(Urgency.of(3).color, EmvColors.severity(3));
    });

    test('formulation prudente, jamais « sans danger »', () {
      for (final s in [1, 2, 3]) {
        final text = '${Urgency.of(s).label} ${Urgency.of(s).advice} ${Urgency.caution}'
            .toLowerCase();
        expect(text, isNot(contains('sans danger')));
        expect(text, isNot(contains('aucun risque')));
      }
    });

    test('toutes les sévérités de dtc.json sont entre 1 et 3', () {
      expect(data.dtcs.where((d) => d.severity < 1 || d.severity > 3), isEmpty);
    });

    test('huile, surchauffe : arrêt conseillé', () {
      for (final c in ['P0217', 'P0298', 'P0520', 'P0524']) {
        expect(data.dtc(c)!.severity, 3, reason: c);
      }
    });
  });

  group('croisement code × moteur × modèle', () {
    test('sans véhicule : aucun résultat', () {
      expect(run('P0401', null), isEmpty);
      expect(engine.forPart('egr-valve', null), isEmpty);
    });

    test('Meriva B 1.7 CDTI A17DT + P0401 : EGR de la fiche modèle puis du moteur', () {
      final r = run('P0401', meriva);
      expect(r, isNotEmpty);
      expect(r.length, lessThanOrEqualTo(3));
      expect(r.first.source, InsightSource.model);
      expect(r.first.text, contains('EGR'));
      expect(r.first.model?.key, 'Opel|Meriva B');
      final note = r.firstWhere((i) => i.source == InsightSource.engine);
      expect(note.engine?.code, 'A17DT');
      expect(note.text, contains('EGR'));
      expect(r.every((i) => i.topics.contains('vanne EGR')), isTrue);
    });

    test('Meriva B 1.7 CDTI de vehicles.json (sans code) : même piste EGR', () {
      final v = allVehicles(data).firstWhere(
          (v) => v.model == 'Meriva B' && v.engine == '1.7 CDTI 110');
      expect(run('P0401', v).first.text, contains('EGR'));
    });

    test('Meriva B A17DT + P2002 : rien qui ne parle pas du FAP', () {
      final r = run('P2002', meriva);
      expect(r.every((i) => i.topics.contains('FAP')), isTrue);
      expect(r.where((i) => i.text.contains('EGR')), isEmpty);
    });

    test('Laguna III 2.0 dCi M9R + P0299 / P0234 : turbo de la fiche M9R', () {
      for (final c in ['P0299', 'P0234']) {
        final r = run(c, laguna);
        expect(r, isNotEmpty, reason: c);
        expect(r.first.engine?.code, 'M9R', reason: c);
        expect(r.first.text.toLowerCase(), contains('turbo'), reason: c);
        expect(r.every((i) => i.topics.contains('turbo')), isTrue, reason: c);
      }
    });

    test('Laguna III M9R + P0401 : point faible EGR du modèle en tête', () {
      final r = run('P0401', laguna);
      expect(r.first.source, InsightSource.model);
      expect(r.first.text, contains('M9R'));
    });

    test('Laguna III FAP + P2002 : colmatage FAP ; version sans FAP : rien', () {
      final r = run('P2002', lagunaFap);
      expect(r.any((i) => i.text.contains('FAP')), isTrue);
      expect(run('P2002', laguna).where((i) => i.text.contains('Diesels FAP')),
          isEmpty);
    });

    test('injecteur AdBlue ≠ injecteur gazole', () {
      final clio = allVehicles(data).firstWhere((v) => v.code == 'K9K');
      for (final i in run('P2047', clio)) {
        expect(i.topics, isNot(contains('injecteurs')));
      }
    });

    test('fiche pièce : turbo du M9R, EGR du Meriva', () {
      expect(engine.forPart('turbocharger', laguna).first.engine?.code, 'M9R');
      expect(engine.forPart('egr-valve', meriva).first.text, contains('EGR'));
    });

    test('au plus 3 éléments, triés par pertinence', () {
      for (final c in ['P0401', 'P0299', 'P0201', 'P0016', 'P0300']) {
        final r = run(c, laguna);
        expect(r.length, lessThanOrEqualTo(3));
        for (var i = 1; i < r.length; i++) {
          expect(r[i - 1].score, greaterThanOrEqualTo(r[i].score));
        }
      }
    });

    test('couverture sur échantillon (1 motorisation sur 25)', () {
      final (pairs, hits) = coverage(data, step: 25);
      expect(pairs, greaterThan(1000));
      expect(hits / pairs, greaterThan(0.10));
    });

    test('couverture complète (EMV_COVERAGE=1)', () {
      final (pairs, hits) = coverage(data);
      // ignore: avoid_print
      print('insights: $hits / $pairs couples = '
          '${(100 * hits / pairs).toStringAsFixed(1)} %');
    },
        skip: Platform.environment['EMV_COVERAGE'] == null,
        timeout: const Timeout(Duration(minutes: 5)));
  });

  group('écran', () {
    Future<AppState> makeState(Vehicle? v) async {
      SharedPreferences.setMockInitialValues({'disclaimer.accepted': true});
      final state = AppState(data, await SharedPreferences.getInstance());
      await state.setVehicle(v);
      return state;
    }

    Future<void> pump(WidgetTester tester, AppState state, String code) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
            theme: buildTheme(), home: DtcScreen(dtc: data.dtc(code)!)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('fiche code : badge en tête et invitation sans véhicule',
        (tester) async {
      await pump(tester, await makeState(null), 'P0234');
      expect(find.byKey(const Key('urgency-3')), findsOneWidget);
      expect(find.text('Arrêt conseillé'), findsOneWidget);
      expect(find.byKey(const Key('insights-choose-vehicle')), findsOneWidget);
    });

    testWidgets('fiche code : section « Fréquemment observé » avec véhicule',
        (tester) async {
      await pump(tester, await makeState(laguna), 'P0401');
      expect(find.byKey(const Key('urgency-2')), findsOneWidget);
      expect(find.text(insightsTitle), findsOneWidget);
      expect(find.textContaining('M9R'), findsWidgets);
      expect(find.byKey(const Key('insights-choose-vehicle')), findsNothing);
    });

    testWidgets('assistant : badge d\'urgence quand un code est cité',
        (tester) async {
      final chatbot = await tester.runAsync(sharedChatbotEngine);
      final state = await makeState(null);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: const AssistantScreen()),
      ));
      await tester.pumpAndSettle();
      final screen = tester.widget<ChatbotScreen>(find.byType(ChatbotScreen));
      expect(screen.engine, same(chatbot));
      final reply = chatbot!.reply('P0234');
      expect(reply.dtcCode, 'P0234');
      final header = screen.replyHeader!(reply);
      expect(header, isA<UrgencyBadge>());
      expect(screen.replyHeader!(const BotReply(text: 'bonjour')), isNull);

      await tester.enterText(find.byType(TextField), 'P0234');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('urgency-3')), findsOneWidget);
    });
  });
}
