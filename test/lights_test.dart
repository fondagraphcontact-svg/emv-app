import 'package:emv/chatbot/chatbot_engine.dart';
import 'package:emv/data.dart';
import 'package:emv/guides/guide_assets.dart';
import 'package:emv/lights/light_assets.dart';
import 'package:emv/lights/light_icon.dart';
import 'package:emv/lights/light_models.dart';
import 'package:emv/lights/light_screen.dart';
import 'package:emv/lights/lights_screen.dart';
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
const _hybridDiesel = Vehicle(
    make: 'Peugeot',
    model: '3008',
    engine: 'HYbrid4',
    fuel: 'hybrid',
    family: 'hybrid-diesel',
    kind: VehicleKind.car);

void main() {
  late AppData data;
  late List<DashboardLight> lights;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
    lights = await loadLights();
    await loadGuides();
    for (final l in lights) {
      await loadLightStrokes(l.iconAsset);
    }
  });

  DashboardLight light(String id) => lights.firstWhere((l) => l.id == id);

  group('dashboard_lights.json', () {
    test('≈45 voyants auto et ≈12 moto, identifiants uniques', () {
      final ids = lights.map((l) => l.id).toSet();
      expect(ids.length, lights.length);
      final moto = lights.where((l) => l.kind == VehicleKind.moto).length;
      expect(lights.length - moto, greaterThanOrEqualTo(45));
      expect(moto, greaterThanOrEqualTo(12));
    });

    test('valeurs normalisées et textes présents', () {
      for (final l in lights) {
        expect(lightCategories.keys, contains(l.category), reason: l.id);
        expect(lightColorNames.keys, contains(l.color), reason: l.id);
        expect(l.urgency, inInclusiveRange(1, 3), reason: l.id);
        expect(l.meaning, isNotEmpty, reason: l.id);
        expect(l.now, isNotEmpty, reason: l.id);
        expect(l.causes, isNotEmpty, reason: l.id);
        expect(l.fuel, isNotEmpty, reason: l.id);
      }
      for (final c in lightCategories.keys) {
        expect(lights.where((l) => l.category == c), isNotEmpty, reason: c);
      }
    });

    test('codes, pièces et guides liés existent', () {
      final guides = {for (final g in loadedGuides!) g.id};
      for (final l in lights) {
        for (final c in l.dtc) {
          expect(data.dtc(c), isNotNull, reason: '${l.id} $c');
        }
        for (final p in l.parts) {
          expect(data.part(p), isNotNull, reason: '${l.id} $p');
        }
        for (final g in l.guides) {
          expect(guides, contains(g), reason: '${l.id} $g');
        }
      }
    });

    test('chaque voyant a un pictogramme lisible', () async {
      for (final l in lights) {
        final strokes = await loadLightStrokes(l.iconAsset);
        expect(strokes, isNotEmpty, reason: l.iconAsset);
        for (final s in strokes) {
          final b = s.path.getBounds();
          expect(b.left >= -1 && b.top >= -1 && b.right <= 101 && b.bottom <= 101,
              isTrue,
              reason: '${l.id} déborde du cadre 100×100 : $b');
        }
      }
    });
  });

  group('modèle', () {
    test('parseLightSvg lit tracés, épaisseur et remplissage', () {
      final s = parseLightSvg('<svg><g><path d="M 0 0 L 10 10" stroke-width="4"/>'
          '<path d="M 5 5 L 6 6 Z" stroke-width="1" fill="#FFFFFF" stroke="none"/></g></svg>');
      expect(s, hasLength(2));
      expect(s[0].width, 4);
      expect(s[0].fill, isFalse);
      expect(s[1].fill, isTrue);
    });

    test('voyants filtrés selon le véhicule', () {
      expect(light('dpf').appliesTo(_diesel), isTrue);
      expect(light('dpf').appliesTo(_petrol), isFalse);
      expect(light('dpf').appliesTo(_hybridDiesel), isTrue);
      expect(light('glow-plug').appliesTo(_petrol), isFalse);
      expect(light('moto-neutral').appliesTo(_moto), isTrue);
      expect(light('moto-neutral').appliesTo(_petrol), isFalse);
      expect(light('engine-check').appliesTo(_moto), isFalse);
      expect(light('high-beam').appliesTo(_moto), isTrue);
      expect(light('brake-system').appliesTo(_moto), isTrue);
    });

    test('recherche sans accents sur nom et mots-clés', () {
      List<String> find(String q) =>
          [for (final l in lights) if (l.matches(q)) l.id];
      expect(find('tortue'), contains('reduced-power-ev'));
      expect(find('prechauffage'), contains('glow-plug'));
      expect(find('burette'), contains('oil-pressure'));
      expect(find('BEQUILLE'), contains('moto-side-stand'));
    });
  });

  group('écrans', () {
    Future<AppState> pump(WidgetTester tester, Widget home,
        {Vehicle? vehicle}) async {
      SharedPreferences.setMockInitialValues({'disclaimer.accepted': true});
      final state = AppState(data, await SharedPreferences.getInstance());
      if (vehicle != null) state.setVehicle(vehicle);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: home),
      ));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('carte « Un voyant est allumé ? » ouvre la galerie',
        (tester) async {
      await pump(tester, const FaultsScreen());
      expect(find.text('Un voyant est allumé ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lights-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Voyants du tableau de bord'), findsOneWidget);
      expect(find.byType(LightIcon), findsWidgets);
    });

    testWidgets('filtre couleur, catégorie et recherche', (tester) async {
      await pump(tester, const LightsScreen());
      await tester.tap(find.byKey(const Key('lights-color-bleu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('light-high-beam')), findsOneWidget);
      expect(find.byKey(const Key('light-oil-pressure')), findsNothing);
      await tester.tap(find.byKey(const Key('lights-color-bleu')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('lights-cat-freinage')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('light-abs')), findsOneWidget);
      expect(find.byKey(const Key('light-high-beam')), findsNothing);
      await tester.tap(find.byKey(const Key('lights-cat-freinage')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('lights-search')), 'tortue');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('light-reduced-power-ev')), findsOneWidget);
      expect(find.byType(LightIcon), findsOneWidget);
    });

    testWidgets('filtre « Mon véhicule » masque le FAP sur essence',
        (tester) async {
      await pump(tester, const LightsScreen(), vehicle: _petrol);
      await tester.enterText(find.byKey(const Key('lights-search')), 'FAP');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('light-dpf')), findsNothing);
      await tester.tap(find.byKey(const Key('lights-vehicle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('light-dpf')), findsOneWidget);
    });

    testWidgets('fiche voyant : urgence, code lié, guide, retour',
        (tester) async {
      await pump(tester, LightScreen(light: light('oil-pressure')));
      expect(find.text('Pression d\'huile'), findsOneWidget);
      expect(find.byKey(const Key('urgency-3')), findsOneWidget);
      expect(find.text('Arrêt immédiat'), findsOneWidget);
      expect(find.text('Que faire maintenant'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const Key('light-guide-oil-leak')), 200);
      expect(find.byKey(const Key('light-guide-oil-leak')), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const Key('feedback-report')), 200);
      expect(find.byKey(const Key('feedback-report')), findsOneWidget);

      await tester.scrollUntilVisible(
          find.byKey(const Key('light-dtc-P0520')), -200);
      await tester.tap(find.byKey(const Key('light-dtc-P0520')));
      await tester.pumpAndSettle();
      expect(find.byType(DtcScreen), findsOneWidget);
    });
  });

  group('chatbot', () {
    late ChatbotEngine engine;
    setUpAll(() async => engine = await sharedChatbotEngine());

    Iterable<String> lightActions(BotReply r) => r.actions
        .where((a) => a.type == BotActionType.openLight)
        .map((a) => a.payload);

    test('voyant huile -> action openLight', () {
      expect(lightActions(engine.reply('voyant huile')), contains('oil-pressure'));
    });

    test('contexte moto : voyants voiture écartés', () {
      final r = engine.reply('voyant batterie', ctx: const VehicleCtx(kind: 'moto'));
      expect(lightActions(r), isNot(contains('battery-charge')));
    });
  });
}
