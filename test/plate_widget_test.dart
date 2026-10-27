import 'package:emv/data.dart';
import 'package:emv/main.dart';
import 'package:emv/models.dart';
import 'package:emv/plate/identify_card.dart';
import 'package:emv/plate/plate_format.dart';
import 'package:emv/plate/plate_lookup.dart';
import 'package:emv/plate/vin_decoder.dart';
import 'package:emv/state.dart';
import 'package:emv/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLookup implements PlateLookupService {
  final PlateInfo? info;
  final PlateLookupError? error;
  final List<Plate> calls = [];

  _FakeLookup({this.info, this.error});

  @override
  bool get isConfigured => true;

  @override
  Future<PlateInfo> lookup(Plate plate) async {
    calls.add(plate);
    if (error != null) throw PlateLookupException(error!);
    return info!;
  }
}

void main() {
  late AppData data;
  late VinDecoder vin;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
    vin = await VinDecoder.load(rootBundle);
  });

  Future<AppState> makeState() async {
    SharedPreferences.setMockInitialValues({'disclaimer.accepted': true});
    return AppState(data, await SharedPreferences.getInstance());
  }

  Future<(AppState, List<(String, VehicleKind?)>)> pumpCard(
      WidgetTester tester, PlateLookupService lookup) async {
    final state = await makeState();
    final searches = <(String, VehicleKind?)>[];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: IdentifyVehicleCard(
              lookup: lookup,
              vinDecoder: vin,
              initiallyExpanded: true,
              onSearch: (q, k) => searches.add((q, k)),
            ),
          ),
        ),
      ),
    ));
    return (state, searches);
  }

  Future<void> submit(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.tap(find.byKey(const Key('identify-submit')));
    await tester.pumpAndSettle();
  }

  String message(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('identify-message'))).data!;

  testWidgets('écran Véhicule : plaque sans backend → service non configuré',
      (tester) async {
    final state = await makeState();
    await tester.pumpWidget(EmvApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Identifier mon véhicule'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plate-field')), findsOneWidget);
    await submit(tester, 'plate-field', 'ab123cd');
    expect(message(tester), contains('service non configuré'));
    final field = tester.widget<TextField>(find.byKey(const Key('plate-field')));
    expect(field.controller!.text, 'AB-123-CD');
  });

  testWidgets('plaque invalide : message, pas d\'appel réseau', (tester) async {
    final lookup = _FakeLookup(error: PlateLookupError.unavailable);
    await pumpCard(tester, lookup);
    await submit(tester, 'plate-field', 'AB-12');
    expect(message(tester), contains('format attendu'));
    expect(lookup.calls, isEmpty);
  });

  testWidgets('erreur du service affichée en français', (tester) async {
    final lookup = _FakeLookup(error: PlateLookupError.unknownPlate);
    await pumpCard(tester, lookup);
    await submit(tester, 'plate-field', 'AB-123-CD');
    expect(message(tester), contains('Plaque inconnue'));
  });

  testWidgets('plaque → une motorisation : sélection directe', (tester) async {
    final lookup = _FakeLookup(
        info: const PlateInfo(
            make: 'OPEL', model: 'MERIVA', year: 2011,
            engine: '1.7 CDTI 110', fuel: 'GO'));
    final (state, _) = await pumpCard(tester, lookup);
    await submit(tester, 'plate-field', 'ab 123 cd');
    expect(lookup.calls.single.value, 'AB-123-CD');
    expect(state.current?.model, 'Meriva B');
    expect(state.current?.engine, '1.7 CDTI 110');
  });

  testWidgets('plaque → plusieurs motorisations : liste à choisir',
      (tester) async {
    final lookup = _FakeLookup(
        info: const PlateInfo(
            make: 'RENAULT', model: 'LAGUNA', year: 2009,
            engine: '2.0 DCI 150', fuel: 'DIESEL'));
    final (state, _) = await pumpCard(tester, lookup);
    await submit(tester, 'plate-field', 'AB-123-CD');
    expect(find.byKey(const Key('plate-candidates')), findsOneWidget);
    expect(state.current, isNull);
    final tiles = find.descendant(
        of: find.byKey(const Key('plate-candidates')),
        matching: find.byType(ListTile));
    expect(tiles, findsNWidgets(2));
    await tester.tap(tiles.first);
    await tester.pumpAndSettle();
    expect(state.current?.model, 'Laguna III');
    expect(state.current?.engine, startsWith('2.0 dCi 150'));
  });

  testWidgets('VIN : décodage hors ligne et recherche préremplie',
      (tester) async {
    final (_, searches) = await pumpCard(tester, _FakeLookup());
    await tester.tap(find.text('VIN'));
    await tester.pumpAndSettle();
    await submit(tester, 'vin-field', 'wvwzzz1kzbw123456');
    expect(message(tester), contains('Volkswagen'));
    expect(message(tester), contains('2011'));
    expect(searches.single, ('Volkswagen 2011', null));

    await submit(tester, 'vin-field', 'VF1BZOB0644123456');
    expect(message(tester), contains('I, O ni Q'));
  });
}
