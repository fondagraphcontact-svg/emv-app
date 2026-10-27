import 'dart:convert';

import 'package:emv/data.dart';
import 'package:emv/expenses/expense.dart';
import 'package:emv/expenses/expense_csv.dart';
import 'package:emv/expenses/expense_store.dart';
import 'package:emv/expenses/expenses_screen.dart';
import 'package:emv/maintenance/maintenance_screen.dart';
import 'package:emv/models.dart';
import 'package:emv/report/report_pdf.dart';
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

Expense exp(String id, DateTime date, ExpenseCategory c, int cents,
        {int? km, String label = '', String? maintenanceId}) =>
    Expense(
        id: id,
        vehicleId: meriva.id,
        date: date,
        category: c,
        cents: cents,
        km: km,
        label: label,
        maintenanceId: maintenanceId);

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

  group('modèle', () {
    test('JSON aller-retour, catégorie inconnue → Autre', () {
      final e = exp('a', DateTime(2026, 3, 2), ExpenseCategory.labor, 12345,
          km: 150000, label: 'Embrayage', maintenanceId: 'm1');
      final j = e.toJson();
      expect(j['category'], 'main-oeuvre');
      expect(j['amount'], 123.45);
      final r = Expense.fromJson(j);
      expect(r.cents, 12345);
      expect(r.km, 150000);
      expect(r.maintenanceId, 'm1');
      expect(r.category, ExpenseCategory.labor);
      expect(
          Expense.fromJson({...j, 'category': 'x'}).category,
          ExpenseCategory.other);
    });

    test('montants : saisie et formatage français', () {
      expect(parseEurosToCents('79,5'), 7950);
      expect(parseEurosToCents('79.50 €'), 7950);
      expect(parseEurosToCents('1 234,56'), 123456);
      expect(parseEurosToCents('0,1'), 10);
      for (final bad in ['', 'abc', '1,234', '-5', '1,2,3']) {
        expect(parseEurosToCents(bad), isNull, reason: bad);
      }
      expect(formatEuros(123456), '1\u00a0234,56\u00a0€');
      expect(formatEuros(5), '0,05\u00a0€');
      expect(formatCostPerKm(0.1234), '0,123\u00a0€/km');
    });

    test('catégorie devinée depuis le carnet', () {
      expect(guessCategory('Contrôle technique'), ExpenseCategory.inspection);
      expect(guessCategory('CT + contre-visite'), ExpenseCategory.inspection);
      expect(guessCategory('Vidange'), ExpenseCategory.parts);
    });

    test('périodes : 12 mois, année, tout', () {
      final now = DateTime(2026, 10, 27);
      final list = [
        exp('1', DateTime(2026, 1, 5), ExpenseCategory.fuel, 100),
        exp('2', DateTime(2025, 11, 1), ExpenseCategory.fuel, 100),
        exp('3', DateTime(2025, 10, 26), ExpenseCategory.fuel, 100),
      ];
      List<String> ids(ExpensePeriod p) =>
          [for (final e in inPeriod(list, p, now)) e.id];
      expect(ids(ExpensePeriod.last12Months), ['1', '2']);
      expect(ids(ExpensePeriod.thisYear), ['1']);
      expect(ids(ExpensePeriod.all), ['1', '2', '3']);
    });

    test('totaux par catégorie et coût au km prudent', () {
      final s = ExpenseSummary.of([
        exp('1', DateTime(2026), ExpenseCategory.fuel, 6010, km: 100000),
        exp('2', DateTime(2026), ExpenseCategory.fuel, 5990),
        exp('3', DateTime(2026), ExpenseCategory.parts, 20000, km: 101000),
        exp('4', DateTime(2026), ExpenseCategory.insurance, 3000),
      ]);
      expect(s.totalCents, 35000);
      expect(s.byCategory[ExpenseCategory.fuel], 12000);
      expect(s.ranked.map((r) => r.$1), [
        ExpenseCategory.parts,
        ExpenseCategory.fuel,
        ExpenseCategory.insurance,
      ]);
      expect(s.distanceKm, 1000);
      expect(s.costPerKm, closeTo(0.35, 1e-9));

      final short = ExpenseSummary.of([
        exp('1', DateTime(2026), ExpenseCategory.fuel, 6000, km: 100000),
        exp('2', DateTime(2026), ExpenseCategory.fuel, 6000, km: 100200),
      ]);
      expect(short.costPerKm, isNull, reason: 'distance trop courte');
      expect(ExpenseSummary.of([
        exp('1', DateTime(2026), ExpenseCategory.fuel, 6000, km: 100000)
      ]).costPerKm, isNull);
      expect(ExpenseSummary.of(const []).isEmpty, isTrue);
    });
  });

  test('CSV : BOM, point-virgule, virgule décimale, échappement', () {
    final csv = expensesCsv([
      exp('1', DateTime(2026, 9, 1), ExpenseCategory.parts, 7950,
          km: 128000, label: 'Filtre; "huile"', maintenanceId: 'm1'),
      exp('2', DateTime(2026, 9, 3), ExpenseCategory.fuel, 100000),
    ], vehicleTitle: 'Opel Meriva B', maintenanceTitles: {'m1': 'Vidange'});
    final lines = csv.split('\r\n');
    expect(lines.first,
        'Date;Véhicule;Catégorie;Libellé;Montant (€);Kilométrage;Intervention liée');
    expect(lines[1],
        '01/09/2026;Opel Meriva B;Pièces;"Filtre; ""huile""";79,50;128000;Vidange');
    expect(lines[2], '03/09/2026;Opel Meriva B;Carburant;;1000,00;;');
    expect(lines.last, '');
    final bytes = csvBytes(csv);
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(bytes.skip(3).toList()), csv);
  });

  test('store : persistance, tri, édition, lien carnet, suppression', () async {
    final state = await makeState();
    final store = ExpenseStore.of(state.prefs);
    expect(identical(store, ExpenseStore.of(state.prefs)), isTrue);

    await store.save(exp('a', DateTime(2025, 5, 1), ExpenseCategory.fuel, 5000));
    await store.save(exp('b', DateTime(2026, 9, 1), ExpenseCategory.parts, 7950,
        maintenanceId: 'm1'));
    await store.save(Expense(
        id: 'c',
        vehicleId: 'autre',
        date: DateTime(2026),
        category: ExpenseCategory.other,
        cents: 1));
    expect(store.entriesFor(meriva.id).map((e) => e.id), ['b', 'a']);
    expect(store.linkedTo('m1')?.id, 'b');

    await store.save(store.linkedTo('m1')!.copyWith(cents: 8000));
    expect(store.entriesFor(meriva.id).first.cents, 8000);
    expect(store.entriesFor(meriva.id).length, 2);

    SharedPreferences.setMockInitialValues({
      ExpenseStore.prefsKey: state.prefs.getStringList(ExpenseStore.prefsKey)!,
    });
    final reloaded = ExpenseStore.of(await SharedPreferences.getInstance());
    expect(identical(reloaded, store), isFalse);
    expect(reloaded.entriesFor(meriva.id).map((e) => e.cents), [8000, 5000]);
    await reloaded.delete('a');
    expect(reloaded.entriesFor(meriva.id).single.id, 'b');
    expect(reloaded.entriesFor('autre').single.id, 'c');
  });

  test('entrées corrompues ignorées', () async {
    final state = await makeState({
      ExpenseStore.prefsKey: ['{pas du json', '{"id":"x"}'],
    });
    expect(ExpenseStore.of(state.prefs).entriesFor(meriva.id), isEmpty);
  });

  test('rapport PDF avec section Dépenses (plus de 20 lignes)', () async {
    final bytes = await buildReportPdf(
      ReportInput(
        vehicle: meriva,
        symptoms: '',
        codes: const [],
        maintenance: const [],
        expenses: [
          for (var i = 0; i < 25; i++)
            exp('$i', DateTime(2026, 1, i + 1), ExpenseCategory.values[i % 6],
                1000 + i, km: i.isEven ? 100000 + i * 100 : null,
                label: 'Ligne $i — œ')
        ],
        generatedAt: DateTime(2026, 10, 27),
      ),
      theme: await loadReportTheme(rootBundle),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  testWidgets('écran : ajout validé, total, période, édition, suppression',
      (tester) async {
    final state = await makeState();
    final store = ExpenseStore.of(state.prefs);
    final now = DateTime.now();
    await store.save(exp('old', DateTime(now.year - 3, 1, 1),
        ExpenseCategory.insurance, 40000));
    await tester.pumpWidget(host(state, const ExpensesScreen(vehicle: meriva)));
    expect(find.text('Aucune dépense sur cette période'), findsOneWidget);

    await tester.tap(find.text('Tout'));
    await tester.pumpAndSettle();
    expect(find.text('Assurance'), findsWidgets);
    await tester.tap(find.text('12 mois'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expenses-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();
    expect(find.text('Montant attendu, ex. 45,90'), findsOneWidget);

    await tester.tap(find.byKey(const Key('expense-cat-pieces')));
    await tester.enterText(find.byKey(const Key('expense-amount')), '79,5');
    await tester.enterText(find.byKey(const Key('expense-km')), '128000');
    await tester.enterText(find.byKey(const Key('expense-label')), 'Plaquettes');
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();

    final saved = store.entriesFor(meriva.id).first;
    expect(saved.cents, 7950);
    expect(saved.category, ExpenseCategory.parts);
    expect(saved.km, 128000);
    expect(find.text('Plaquettes'), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('expenses-total'))).data,
        formatEuros(7950));
    expect(find.byType(CategoryBars), findsOneWidget);

    await tester.tap(find.text('Plaquettes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense-amount')), '80');
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();
    expect(store.entriesFor(meriva.id).first.cents, 8000);

    await tester.tap(find.text('Plaquettes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-delete-confirm')));
    await tester.pumpAndSettle();
    expect(store.entriesFor(meriva.id).single.id, 'old');
    expect(find.text('Aucune dépense sur cette période'), findsOneWidget);
  });

  testWidgets('carnet : une intervention chiffrée propose la dépense liée',
      (tester) async {
    final state = await makeState();
    await tester.pumpWidget(host(state, const MaintenanceScreen(vehicle: meriva)));
    await tester.tap(find.byKey(const Key('maintenance-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('maintenance-title')), 'Contrôle technique');
    await tester.enterText(find.byKey(const Key('maintenance-km')), '130000');
    await tester.enterText(find.byKey(const Key('maintenance-cost')), '78');
    await tester.ensureVisible(find.byKey(const Key('maintenance-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('maintenance-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expense-offer')), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(SnackBarAction), matching: find.text('Ajouter')));
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle dépense'), findsOneWidget);
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();

    final entry = state.maintenanceFor(meriva.id).single;
    final linked = ExpenseStore.of(state.prefs).linkedTo(entry.id)!;
    expect(linked.cents, 7800);
    expect(linked.km, 130000);
    expect(linked.category, ExpenseCategory.inspection);
    expect(linked.label, 'Contrôle technique');

    await tester.tap(find.byKey(const Key('maintenance-expenses')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Carnet : Contrôle technique'), findsOneWidget);
  });
}
