import 'dart:convert';

import 'package:emv/chatbot/chatbot_engine.dart';
import 'package:emv/data.dart';
import 'package:emv/guides/guide_assets.dart';
import 'package:emv/guides/guide_models.dart';
import 'package:emv/guides/guide_runner_screen.dart';
import 'package:emv/main.dart';
import 'package:emv/models.dart';
import 'package:emv/screens/assistant.dart';
import 'package:emv/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Réponses menant du premier pas à [target], ou null si inatteignable.
List<GuideAnswer>? pathTo(Guide g, String target) {
  final seen = <String>{};
  List<GuideAnswer>? walk(String id) {
    if (id == target) return [];
    final s = g.step(id);
    if (s == null || !seen.add(id)) return null;
    for (final (a, next) in [
      (GuideAnswer.yes, s.yes),
      (GuideAnswer.no, s.no),
      (GuideAnswer.unknown, s.unknownTarget),
    ]) {
      final rest = walk(next);
      if (rest != null) return [a, ...rest];
    }
    return null;
  }

  return walk(g.first!.id);
}

const _keys = {
  GuideAnswer.yes: Key('guide-yes'),
  GuideAnswer.no: Key('guide-no'),
  GuideAnswer.unknown: Key('guide-unknown'),
};

void main() {
  late AppData data;
  late List<Guide> guides;
  late String kbRaw;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
    // Préchargé hors fake-async : l'onglet Guides réutilise ce cache.
    guides = await loadGuides();
    kbRaw = await rootBundle.loadString('assets/data/chatbot_kb.json');
  });

  Guide guide(String id) => guides.firstWhere((g) => g.id == id);

  group('guides.json', () {
    test('au moins 30 guides, ids uniques, 5 à 15 étapes', () {
      expect(guides.length, greaterThanOrEqualTo(30));
      expect(guides.map((g) => g.id).toSet().length, guides.length);
      for (final g in guides) {
        expect(g.steps.length, inInclusiveRange(5, 15), reason: g.id);
        expect(g.stopIf, isNotEmpty, reason: g.id);
        expect(g.difficulty, inInclusiveRange(1, 3), reason: g.id);
        final ids = [...g.steps.map((s) => s.id), ...g.results.map((r) => r.id)];
        expect(ids.toSet().length, ids.length, reason: g.id);
      }
    });

    test('références oui/non/je-ne-sais-pas résolues, aucune étape orpheline',
        () {
      for (final g in guides) {
        final reached = <String>{};
        final todo = [g.first!.id];
        while (todo.isNotEmpty) {
          final id = todo.removeLast();
          if (!reached.add(id)) continue;
          final s = g.step(id);
          if (s == null) {
            expect(g.result(id), isNotNull, reason: '${g.id} → $id');
            continue;
          }
          expect(s.question, isNotEmpty, reason: '${g.id}/$id');
          expect(s.check, isNotEmpty, reason: '${g.id}/$id');
          todo.addAll([s.yes, s.no, s.unknownTarget]);
        }
        for (final s in g.steps) {
          expect(reached, contains(s.id), reason: '${g.id}/${s.id} orpheline');
        }
        for (final r in g.results) {
          expect(reached, contains(r.id), reason: '${g.id}/${r.id} orphelin');
        }
      }
    });

    test('pièces, codes et vues existent dans les données', () {
      for (final g in guides) {
        final parts = [
          for (final s in g.steps) ...s.parts,
          for (final r in g.results) ...r.parts
        ];
        final codes = [
          for (final s in g.steps) ...s.dtc,
          for (final r in g.results) ...r.dtc
        ];
        for (final p in parts) {
          expect(data.part(p), isNotNull, reason: '${g.id}: pièce $p');
        }
        for (final c in codes) {
          expect(data.dtc(c), isNotNull, reason: '${g.id}: code $c');
        }
        for (final r in g.results) {
          for (final v in r.views) {
            expect(data.view(v), isNotNull, reason: '${g.id}: vue $v');
          }
        }
      }
    });

    test('chaque intention de la KB avec « guide » pointe vers un guide', () {
      final ids = guides.map((g) => g.id).toSet();
      final kb = jsonDecode(kbRaw) as List;
      var linked = 0;
      for (final i in kb.cast<Map<String, dynamic>>()) {
        final g = i['guide'];
        if (g == null) continue;
        linked++;
        final targets = g is Map ? g.values : [g];
        for (final t in targets) {
          expect(ids, contains(t), reason: '${i['id']} → $t');
        }
      }
      expect(linked, greaterThanOrEqualTo(30));
    });
  });

  group('filtre véhicule', () {
    const laguna = Vehicle(
        make: 'Renault',
        model: 'Laguna III',
        engine: '2.0 dCi 150',
        fuel: 'diesel',
        family: 'diesel-common-rail',
        kind: VehicleKind.car,
        dpf: false);
    const moto = Vehicle(
        make: 'Yamaha',
        model: 'MT-07',
        engine: '689',
        fuel: 'petrol',
        family: 'moto',
        kind: VehicleKind.moto);

    test('diesel sans FAP : pas de guide régénération ni moto ni essence', () {
      expect(guide('dpf-regeneration').appliesTo(laguna), isFalse);
      expect(guide('moto-chain').appliesTo(laguna), isFalse);
      expect(guide('power-loss-petrol').appliesTo(laguna), isFalse);
      expect(guide('power-loss-diesel').appliesTo(laguna), isTrue);
      expect(guide('adblue').appliesTo(null), isTrue);
    });

    test('moto : guides moto proposés, guides voiture écartés', () {
      expect(guide('moto-no-start').appliesTo(moto), isTrue);
      expect(guide('cv-joint-click').appliesTo(moto), isFalse);
    });
  });

  group('chatbot', () {
    late ChatbotEngine engine;
    setUpAll(() async => engine = await sharedChatbotEngine());

    Iterable<String> guideActions(BotReply r) => r.actions
        .where((a) => a.type == BotActionType.openGuide)
        .map((a) => a.payload);

    test('fumée noire -> action Ouvrir le guide', () {
      expect(guideActions(engine.reply('fumée noire à l\'échappement')),
          contains('exhaust-smoke'));
    });

    test('perte de puissance : guide selon le carburant', () {
      expect(
          guideActions(engine.reply('perte de puissance',
              ctx: const VehicleCtx(fuel: 'diesel'))),
          contains('power-loss-diesel'));
      expect(
          guideActions(engine.reply('perte de puissance',
              ctx: const VehicleCtx(fuel: 'petrol'))),
          contains('power-loss-petrol'));
    });
  });

  group('GuideRunnerScreen', () {
    Future<AppState> makeState() async {
      SharedPreferences.setMockInitialValues({'disclaimer.accepted': true});
      return AppState(data, await SharedPreferences.getInstance());
    }

    Future<void> pumpRunner(WidgetTester tester, Guide g,
        {GuideLink? onView, GuideLink? onPart, GuideLink? onDtc}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: await makeState(),
        child: MaterialApp(
            home: GuideRunnerScreen(
                guide: g, onOpenView: onView, onOpenPart: onPart, onOpenDtc: onDtc)),
      ));
      await tester.pumpAndSettle();
    }

    String question(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('guide-question'))).data!;

    testWidgets('sécurité, questions, fil d\'Ariane, résultat, recommencer',
        (tester) async {
      final g = guide('no-start-cranks');
      await pumpRunner(tester, g);
      expect(find.byKey(const Key('guide-stopif')), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-start')));
      await tester.pumpAndSettle();

      final first = g.first!;
      expect(question(tester), first.question);
      await tester.tap(find.byKey(const Key('guide-yes')));
      await tester.pumpAndSettle();
      final second = g.step(first.yes)!;
      expect(question(tester), second.question);

      await tester.tap(find.byKey(const Key('guide-unknown')));
      await tester.pumpAndSettle();
      expect(question(tester), g.step(second.unknownTarget)!.question);
      expect(find.byKey(const Key('guide-crumb-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide-crumb-0')));
      await tester.pumpAndSettle();
      expect(question(tester), first.question);
      expect(find.byKey(const Key('guide-crumb-0')), findsNothing);

      await tester.tap(find.byKey(const Key('guide-no')));
      await tester.pumpAndSettle();
      final result = g.result(first.no)!;
      expect(find.byKey(const Key('guide-result')), findsOneWidget);
      expect(find.text(result.title), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const Key('feedback-report')), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Cette fiche vous a aidé ?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide-restart')));
      await tester.pumpAndSettle();
      expect(question(tester), first.question);
    });

    testWidgets('boutons du résultat appellent vue, pièce et code',
        (tester) async {
      late Guide g;
      late GuideResult r;
      found:
      for (final cand in guides) {
        for (final res in cand.results) {
          if (res.views.isNotEmpty && res.parts.isNotEmpty && res.dtc.isNotEmpty) {
            g = cand;
            r = res;
            break found;
          }
        }
      }
      final opened = <String>[];
      await pumpRunner(tester, g,
          onView: (id) => opened.add('view:$id'),
          onPart: (s) => opened.add('part:$s'),
          onDtc: (c) => opened.add('dtc:$c'));
      await tester.tap(find.byKey(const Key('guide-start')));
      await tester.pumpAndSettle();
      for (final a in pathTo(g, r.id)!) {
        await tester.tap(find.byKey(_keys[a]!));
        await tester.pumpAndSettle();
      }
      expect(find.text(r.title), findsOneWidget);

      final list = find.byType(Scrollable).last;
      Future<void> tapKey(String k) async {
        await tester.scrollUntilVisible(find.byKey(Key(k)), 200,
            scrollable: list);
        await tester.tap(find.byKey(Key(k)));
        await tester.pumpAndSettle();
      }

      await tapKey('guide-part-${r.parts.first}');
      await tapKey('guide-view-${r.views.first}');
      await tapKey('guide-dtc-${r.dtc.first}');
      expect(opened, [
        'part:${r.parts.first}',
        'view:${r.views.first}',
        'dtc:${r.dtc.first}',
      ]);
    });
  });

  testWidgets('onglet Diagnostic > Guides ouvre un guide', (tester) async {
    SharedPreferences.setMockInitialValues({'disclaimer.accepted': true});
    final state = AppState(data, await SharedPreferences.getInstance());
    await tester.pumpWidget(EmvApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnostic'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dtc-search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-guides')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('guide-search')), 'surchauffe');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guide-overheating')));
    await tester.pumpAndSettle();
    expect(find.byType(GuideRunnerScreen), findsOneWidget);
    expect(find.byKey(const Key('guide-start')), findsOneWidget);
  });
}
