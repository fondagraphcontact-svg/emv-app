import 'package:emv/config.dart';
import 'package:emv/data.dart';
import 'package:emv/state.dart';
import 'package:emv/widgets/feedback_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
  });

  Future<AppState> pumpBar(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'disclaimer.accepted': true});
    final state = AppState(data, await SharedPreferences.getInstance());
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(
          home: Scaffold(body: FeedbackBar(type: 'dtc', id: 'P0301'))),
    ));
    return state;
  }

  testWidgets('vote local 👍 / 👎 basculable et persistant', (tester) async {
    final state = await pumpBar(tester);
    expect(find.text('Cette fiche vous a aidé ?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('feedback-1')));
    await tester.pump();
    expect(state.feedbackVote('dtc:P0301'), 1);
    expect(find.text('Merci pour votre avis'), findsOneWidget);

    await tester.tap(find.byKey(const Key('feedback--1')));
    await tester.pump();
    expect(state.feedbackVote('dtc:P0301'), -1);
    expect(AppState(data, state.prefs).feedbackVote('dtc:P0301'), -1);

    await tester.tap(find.byKey(const Key('feedback--1')));
    await tester.pump();
    expect(state.feedbackVote('dtc:P0301'), 0);
  });

  testWidgets('Signaler une erreur ouvre un mailto pré-rempli', (tester) async {
    Uri? launched;
    FeedbackBar.launcher = (uri) async {
      launched = uri;
      return true;
    };
    await pumpBar(tester);
    await tester.tap(find.byKey(const Key('feedback-report')));
    await tester.pumpAndSettle();

    final version = await loadDataVersion();
    expect(launched?.scheme, 'mailto');
    expect(launched?.path, contactEmail);
    expect(launched?.queryParameters['subject'],
        'EMV dtc P0301 v${version ?? '?'}');
    expect(launched.toString(), isNot(contains('+')));
  });

  testWidgets('sans client mail : message avec l\'adresse', (tester) async {
    FeedbackBar.launcher = (uri) async => false;
    await pumpBar(tester);
    await tester.tap(find.byKey(const Key('feedback-report')));
    await tester.pumpAndSettle();
    expect(find.textContaining(contactEmail), findsOneWidget);
  });
}
