import 'package:emv/codelog/code_entry.dart';
import 'package:emv/codelog/code_log_screen.dart';
import 'package:emv/codelog/code_log_store.dart';
import 'package:emv/data.dart';
import 'package:emv/models.dart';
import 'package:emv/report/report_pdf.dart';
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
  engine: '1.7 CDTI',
  fuel: 'diesel',
  family: 'diesel-i4-turbo-cr',
  kind: VehicleKind.car,
  yearFrom: 2010,
  yearTo: 2017,
);

void main() {
  late AppData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
  });

  Future<AppState> makeState([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(
        {'disclaimer.accepted': true, ...prefs});
    return AppState(data, await SharedPreferences.getInstance());
  }

  Widget host(AppState state, Widget home) => ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: home),
      );

  group('format du code', () {
    test('accepte P/C/B/U + 4 caractères hexadécimaux', () {
      for (final c in ['P0301', 'p0a80', 'C0035', 'B1000', 'U0100', ' P 2002 ']) {
        expect(codeFormatError(c), isNull, reason: c);
      }
      expect(normalizeCode(' p0a-80 '), 'P0A80');
    });

    test('refuse les formats invalides', () {
      for (final c in ['', 'X0301', 'P030', 'P03011', 'P0G01', '0301']) {
        expect(codeFormatError(c), isNotNull, reason: c);
      }
    });
  });

  test('entrée : JSON aller-retour et statut', () {
    final e = CodeLogEntry(
        id: 'a',
        vehicleKey: meriva.id,
        code: 'P0401',
        date: DateTime(2026, 10, 1),
        km: 182000,
        note: 'Lu au garage');
    expect(e.status, CodeStatus.open);
    expect(e.toJson()['status'], 'ouvert');
    final r = CodeLogEntry.fromJson(e.resolved(DateTime(2026, 10, 5)).toJson());
    expect(r.status, CodeStatus.resolved);
    expect(r.resolvedAt, DateTime(2026, 10, 5));
    expect(r.km, 182000);
    expect(r.note, 'Lu au garage');
    expect(r.toJson()['status'], 'résolu');
  });

  test('journal : persistance, tri par date, résolu, suppression', () async {
    final state = await makeState();
    final store = CodeLogStore.of(state.prefs);
    expect(identical(store, CodeLogStore.of(state.prefs)), isTrue);

    final old = await store.add(
        vehicleKey: meriva.id, code: 'p0401', date: DateTime(2025, 5, 1));
    final recent = await store.add(
        vehicleKey: meriva.id,
        code: 'P0299',
        date: DateTime(2026, 9, 1),
        km: 181000,
        note: '  à froid ');
    await store.add(vehicleKey: 'autre', code: 'U0100', date: DateTime(2026));

    expect(store.entriesFor(meriva.id).map((e) => e.code), ['P0299', 'P0401']);
    expect(store.entriesFor(meriva.id).first.note, 'à froid');

    await store.markResolved(old.id, at: DateTime(2025, 6, 1));
    expect(store.openFor(meriva.id).single.id, recent.id);
    expect(store.resolvedFor(meriva.id).single.resolvedAt, DateTime(2025, 6, 1));

    // Relecture depuis les préférences brutes (nouvelle instance).
    SharedPreferences.setMockInitialValues({
      CodeLogStore.prefsKey: state.prefs.getStringList(CodeLogStore.prefsKey)!,
    });
    final reloaded = CodeLogStore.of(await SharedPreferences.getInstance());
    expect(identical(reloaded, store), isFalse);
    expect(reloaded.entriesFor(meriva.id).length, 2);
    expect(reloaded.resolvedFor(meriva.id).single.code, 'P0401');

    await reloaded.reopen(old.id);
    expect(reloaded.openFor(meriva.id).length, 2);
    await reloaded.delete(recent.id);
    expect(reloaded.entriesFor(meriva.id).map((e) => e.code), ['P0401']);
    expect(reloaded.entriesFor('autre').single.code, 'U0100');
  });

  test('entrées corrompues ignorées', () async {
    final state = await makeState({
      CodeLogStore.prefsKey: ['{pas du json', '{"id":"x"}'],
    });
    expect(CodeLogStore.of(state.prefs).entriesFor(meriva.id), isEmpty);
  });

  test('rapport PDF avec section codes relevés', () async {
    final open = CodeLogEntry(
        id: 'o',
        vehicleKey: meriva.id,
        code: 'P0401',
        date: DateTime(2026, 10, 1),
        km: 182000,
        note: 'Voyant à froid — œil');
    final done = CodeLogEntry(
        id: 'r',
        vehicleKey: meriva.id,
        code: 'P1ABC',
        date: DateTime(2026, 8, 1),
        resolvedAt: DateTime(2026, 8, 20));
    final bytes = await buildReportPdf(
      ReportInput(
        vehicle: meriva,
        symptoms: '',
        codes: const [],
        maintenance: const [],
        loggedCodes: [(open, data.dtc(open.code)), (done, null)],
        generatedAt: DateTime(2026, 10, 27),
      ),
      theme: await loadReportTheme(rootBundle),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  testWidgets('écran : ajout validé, autocomplétion, résolu, suppression',
      (tester) async {
    final state = await makeState();
    await tester.pumpWidget(host(state, const CodeLogScreen(vehicle: meriva)));
    expect(find.text('Aucun code ouvert'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('codelog-code')), 'X12');
    await tester.tap(find.byKey(const Key('codelog-add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Format attendu'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('codelog-code')), 'p040');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('codelog-option-P0401')), findsOneWidget);
    await tester.tap(find.byKey(const Key('codelog-option-P0401')));
    await tester.pumpAndSettle();
    expect(find.text(data.dtc('P0401')!.title), findsOneWidget);

    await tester.enterText(find.byKey(const Key('codelog-km')), '182000');
    await tester.enterText(find.byKey(const Key('codelog-note')), 'Lu au garage');
    await tester.tap(find.byKey(const Key('codelog-add')));
    await tester.pumpAndSettle();

    final store = CodeLogStore.of(state.prefs);
    final entry = store.entriesFor(meriva.id).single;
    expect(entry.code, 'P0401');
    expect(entry.km, 182000);
    expect(find.text('OUVERTS (1)'), findsOneWidget);
    expect(find.byKey(Key('codelog-entry-${entry.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('codelog-menu-${entry.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('codelog-resolve')));
    await tester.pumpAndSettle();
    expect(find.text('RÉSOLUS (1)'), findsOneWidget);
    expect(store.entriesFor(meriva.id).single.isOpen, isFalse);

    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('codelog-entry-${entry.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(DtcScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('codelog-menu-${entry.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('codelog-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('codelog-delete-confirm')));
    await tester.pumpAndSettle();
    expect(store.entriesFor(meriva.id), isEmpty);
  });

  testWidgets('fiche DTC : « Ajouter à mes codes » pour le véhicule courant',
      (tester) async {
    final state = await makeState();
    await state.setVehicle(meriva);
    await state.setOdometer(meriva.id, 150000);
    final dtc = data.dtc('P0401')!;
    await tester.pumpWidget(host(state, DtcScreen(dtc: dtc)));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('codelog-add-from-dtc'));
    await tester.scrollUntilVisible(button, 300);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('150000'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('codelog-dialog-note')), 'Valise du voisin');
    await tester.tap(find.byKey(const Key('codelog-dialog-save')));
    await tester.pumpAndSettle();

    final e = CodeLogStore.of(state.prefs).entriesFor(meriva.id).single;
    expect(e.code, 'P0401');
    expect(e.km, 150000);
    expect(e.note, 'Valise du voisin');
    expect(find.text('P0401 ajouté à vos codes relevés'), findsOneWidget);
  });

  testWidgets('onglet Diagnostic : tuile Mes codes relevés', (tester) async {
    final state = await makeState();
    await state.setVehicle(meriva);
    await CodeLogStore.of(state.prefs)
        .add(vehicleKey: meriva.id, code: 'P0401', date: DateTime(2026));
    await tester.pumpWidget(host(state, const FaultsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('1 ouvert(s) · 0 résolu(s)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('codelog-tile')));
    await tester.pumpAndSettle();
    expect(find.byType(CodeLogScreen), findsOneWidget);
  });
}
