import 'package:emv/chatbot/chatbot_engine.dart';
import 'package:emv/chatbot/chatbot_screen.dart';
import 'package:emv/data.dart';
import 'package:emv/main.dart';
import 'package:emv/screens/assistant.dart';
import 'package:emv/screens/faults.dart';
import 'package:emv/state.dart';
import 'package:emv/widgets/feedback_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
    await sharedChatbotEngine();
  });

  Future<AppState> makeState({bool accepted = true}) async {
    SharedPreferences.setMockInitialValues(
        accepted ? {'disclaimer.accepted': true} : {});
    return AppState(data, await SharedPreferences.getInstance());
  }

  testWidgets('avertissement au premier lancement', (tester) async {
    final state = await makeState(accepted: false);
    await tester.pumpWidget(EmvApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Avertissement'), findsOneWidget);
    await tester.tap(find.text('J\'ai compris'));
    await tester.pumpAndSettle();
    expect(state.disclaimerAccepted, isTrue);
    expect(find.text('Avertissement'), findsNothing);
  });

  testWidgets('5 onglets et choix d\'un véhicule', (tester) async {
    final state = await makeState();
    await tester.pumpWidget(EmvApp(state: state));
    await tester.pumpAndSettle();
    for (final label in ['Véhicule', 'Vues', 'Diagnostic', 'Profil', 'Assistant']) {
      expect(find.text(label), findsWidgets);
    }
    final make = data.makes.first;
    await tester.enterText(
        find.byKey(const Key('vehicle-search')), make.name.toLowerCase());
    await tester.pumpAndSettle();
    await tester.tap(find.text('${make.name} ${make.models.first.name}').first);
    await tester.pumpAndSettle();
    expect(state.current?.make, make.name);
    expect(state.saved, isNotEmpty);
  });

  testWidgets('fiche DTC : Voir les pièces ouvre la vue', (tester) async {
    final state = await makeState();
    final dtc = data.dtcs.firstWhere(
        (d) => data.bestViewFor(d.parts) != null,
        orElse: () => data.dtcs.first);
    await tester.pumpWidget(EmvApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnostic'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dtc-search')), dtc.code);
    await tester.pumpAndSettle();
    await tester.tap(find.text(dtc.title).first);
    await tester.pumpAndSettle();
    expect(find.text(dtc.code), findsWidgets);
    expect(state.recentDtcs.first.code, dtc.code);
    final sheet = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.byType(FeedbackBar), 300,
        scrollable: sheet);
    expect(find.byType(FeedbackBar), findsOneWidget);
    expect(find.byKey(const Key('prepare-report')), findsOneWidget);
    if (data.bestViewFor(dtc.parts) == null) return;
    await tester.scrollUntilVisible(find.byKey(const Key('show-parts')), -300,
        scrollable: sheet);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('show-parts')));
    await tester.pumpAndSettle();
    expect(state.tab, AppTab.views);
    expect(state.activeView, isNotNull);
    expect(state.highlighted, isNotEmpty);
  });

  testWidgets('onglet Assistant relié au véhicule courant', (tester) async {
    final state = await makeState();
    final v = data.searchVehicles('', limit: 100000)
        .firstWhere((v) => v.fuel == 'diesel' && v.dpf == false);
    await state.setVehicle(v);
    await tester.pumpWidget(EmvApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    expect(state.tab, AppTab.assistant);
    final screen = tester.widget<ChatbotScreen>(find.byType(ChatbotScreen));
    expect(screen.engine, isNotNull);
    expect(screen.vehicle?.dpf, isFalse);
    expect(screen.vehicle?.fuel, 'diesel');
    expect(screen.vehicle?.make, v.make);

    screen.onSelectVehicle(VehicleEntry(
        make: 'Renault', model: 'Laguna III', engine: '2.0 dCi 150',
        fuel: 'diesel', family: v.family, dpf: false));
    await tester.pumpAndSettle();
    expect(state.current?.model, 'Laguna III');
    expect(state.current?.dpf, isFalse);

    final slug = data.views.first.parts.first.slug;
    screen.onOpenView(slug);
    await tester.pumpAndSettle();
    expect(state.tab, AppTab.views);
    expect(state.highlighted, contains(slug));

    screen.onOpenViewId!(data.views.last.id);
    await tester.pumpAndSettle();
    expect(state.activeView?.id, data.views.last.id);

    final dtc = data.dtcs.firstWhere((d) => d.symptoms.isNotEmpty);
    screen.onOpenDtc(dtc.code);
    await tester.pumpAndSettle();
    expect(find.byType(DtcScreen), findsOneWidget);
  });

  testWidgets('Profil : carnet et rapport accessibles', (tester) async {
    final state = await makeState();
    await state.setVehicle(data.searchVehicles('', limit: 1).first);
    await tester.pumpWidget(EmvApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-maintenance')));
    await tester.pumpAndSettle();
    expect(find.text('Carnet d\'entretien'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-report')));
    await tester.pumpAndSettle();
    expect(find.text('Préparer pour le garage'), findsOneWidget);
    expect(find.byKey(const Key('report-symptoms')), findsOneWidget);
  });
  testWidgets('Vues : vues génériques regroupées par catégorie repliable', (tester) async {
    final state = await makeState();
    await tester.pumpWidget(EmvApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vues').first);
    await tester.pumpAndSettle();
    expect(find.text('Moteur'), findsOneWidget);
    expect(find.text('Freinage'), findsOneWidget);
    final brakes = data.genericViews.firstWhere((v) => v.id == 'brakes-disc');
    expect(find.text(brakes.name), findsNothing);
    await tester.tap(find.text('Freinage'));
    await tester.pumpAndSettle();
    expect(find.text(brakes.name), findsOneWidget);
  });
}
