import 'package:emv/data.dart';
import 'package:emv/maintenance/maintenance_entry.dart';
import 'package:emv/maintenance/maintenance_screen.dart';
import 'package:emv/maintenance/reminders.dart';
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
  family: 'diesel-cr-i4',
  kind: VehicleKind.car,
  yearFrom: 2010,
  yearTo: 2017,
);

void main() {
  late AppData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
    ReminderScheduler.instance = const NoopReminderScheduler();
  });

  Future<AppState> makeState([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(
        {'disclaimer.accepted': true, ...prefs});
    return AppState(data, await SharedPreferences.getInstance());
  }

  test('carnet : persistance, tri, kilométrage et échéances', () async {
    final state = await makeState();
    await state.saveMaintenance(MaintenanceEntry(
        id: 'a',
        vehicleKey: meriva.id,
        date: DateTime(2025, 3, 1),
        km: 120000,
        title: 'Vidange',
        reminderKm: 135000));
    await state.saveMaintenance(MaintenanceEntry(
        id: 'b',
        vehicleKey: meriva.id,
        date: DateTime(2026, 1, 10),
        km: 130000,
        title: 'Plaquettes',
        cost: 89.9));
    await state.saveMaintenance(MaintenanceEntry(
        id: 'x', vehicleKey: 'autre', date: DateTime(2026), title: 'Autre'));

    expect(state.maintenanceFor(meriva.id).map((e) => e.id), ['b', 'a']);
    expect(state.odometer(meriva.id), 130000);
    expect(state.dueKmReminders(meriva.id), isEmpty);

    await state.setOdometer(meriva.id, 136000);
    expect(state.dueKmReminders(meriva.id).single.id, 'a');

    final reloaded = AppState(data, state.prefs);
    expect(reloaded.maintenanceFor(meriva.id).first.cost, 89.9);
    expect(reloaded.odometer(meriva.id), 136000);

    await reloaded.deleteMaintenance('a');
    expect(reloaded.maintenanceFor(meriva.id).map((e) => e.id), ['b']);
  });

  test('historique DTC : plus récent en tête, sans doublon, borné', () async {
    final state = await makeState();
    for (var i = 0; i < AppState.recentDtcLimit + 5; i++) {
      await state.recordDtcViewed('P${1000 + i}');
    }
    await state.recordDtcViewed('P1002');
    expect(state.recentDtcs.length, AppState.recentDtcLimit);
    expect(state.recentDtcs.first.code, 'P1002');
    expect(state.recentDtcs.where((r) => r.code == 'P1002').length, 1);
    expect(AppState(data, state.prefs).recentDtcs.first.code, 'P1002');
  });

  test('rapport PDF généré avec police unicode', () async {
    final state = await makeState();
    await state.recordDtcViewed(data.dtcs.first.code);
    final bytes = await buildReportPdf(
      ReportInput(
        vehicle: meriva,
        odometer: 130000,
        symptoms: 'À-coups à froid — voyant moteur, coût estimé 120 €',
        codes: [
          for (final r in state.recentDtcs) (r, data.dtc(r.code))
        ],
        maintenance: [
          MaintenanceEntry(
              id: 'a',
              vehicleKey: meriva.id,
              date: DateTime(2025, 3, 1),
              km: 120000,
              title: 'Vidange',
              parts: ['Filtre à huile'],
              cost: 75)
        ],
        dataVersion: '2026.10.26',
        generatedAt: DateTime(2026, 10, 26),
      ),
      theme: await loadReportTheme(rootBundle),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  testWidgets('carnet : ajout d\'une intervention via le formulaire',
      (tester) async {
    final state = await makeState();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
          theme: buildTheme(), home: const MaintenanceScreen(vehicle: meriva)),
    ));
    expect(find.text('Aucune intervention enregistrée'), findsOneWidget);

    await tester.tap(find.byKey(const Key('maintenance-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('maintenance-save')));
    await tester.pumpAndSettle();
    expect(find.text('Indiquez l\'intervention'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('maintenance-title')), 'Vidange + filtre');
    await tester.enterText(find.byKey(const Key('maintenance-km')), '128000');
    await tester.enterText(find.byKey(const Key('maintenance-cost')), '79,5');
    await tester.enterText(
        find.byKey(const Key('maintenance-reminder-km')), '143000');
    await tester.ensureVisible(find.byKey(const Key('maintenance-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('maintenance-save')));
    await tester.pumpAndSettle();

    final entry = state.maintenanceFor(meriva.id).single;
    expect(entry.km, 128000);
    expect(entry.cost, 79.5);
    expect(entry.reminderKm, 143000);
    expect(find.text('Vidange + filtre'), findsWidgets);
    expect(find.text('RAPPELS À VENIR'), findsOneWidget);
    expect(find.text('128 000 km'), findsOneWidget);
  });
}
