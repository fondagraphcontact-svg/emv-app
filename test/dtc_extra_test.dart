import 'package:emv/data.dart';
import 'package:emv/models.dart';
import 'package:emv/widgets/engine_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const extraCodes = [
  'P2002', 'P2463', 'P2452', 'P2453', 'P20EE', 'P20B9', 'P2047', 'P2200', //
  'P2135', 'P2263', 'P2004', 'P2015', 'P244A', 'P203F', 'P20E8', 'U0100',
  'U0121', 'C0035', 'C0040', 'C0045', 'C0050', 'C0750', 'P0A80', 'P0AFA',
  'P0A7F', 'P0A78', 'P0AA1', 'P0AA6',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppData data;

  setUpAll(() async {
    data = await AppData.load(rootBundle);
  });

  List<String> codes(Iterable<Dtc> l) => [for (final d in l) d.code];

  group('codes hors plage P0000-P0999', () {
    test('fiches complètes avec pièces existantes', () {
      for (final c in extraCodes) {
        final d = data.dtc(c);
        expect(d, isNotNull, reason: c);
        expect(d!.symptoms, isNotEmpty, reason: c);
        expect(d.causes, isNotEmpty, reason: c);
        expect(d.diagnostic, isNotEmpty, reason: c);
        expect(d.fuel, isNotEmpty, reason: c);
        expect(d.parts, isNotEmpty, reason: c);
        expect(d.parts.where((p) => data.part(p) == null), isEmpty, reason: c);
        expect(systemLabel(d.system), isNot(d.system), reason: c);
      }
    });

    test('recherche par préfixe C, U, P0A et P2', () {
      expect(codes(data.searchDtc('C00')), ['C0035', 'C0040', 'C0045', 'C0050']);
      expect(codes(data.searchDtc('c07')), ['C0750']);
      expect(codes(data.searchDtc('U01')), ['U0100', 'U0121']);
      expect(codes(data.searchDtc('P0A')),
          ['P0A78', 'P0A7F', 'P0A80', 'P0AA1', 'P0AA6', 'P0AFA']);
      expect(codes(data.searchDtc('P20E')), ['P20E8', 'P20EE']);
      expect(codes(data.searchDtc('contacteur positif')), contains('P0AA1'));
    });

    test('liste triée P puis C puis B puis U', () {
      final all = codes(data.searchDtc('', limit: 100000));
      expect(all.first, 'P0000');
      final families = all.map((c) => c[0]).toList();
      final firstIndex = {for (final f in 'PCBU'.split('')) f: families.indexOf(f)};
      final lastP = families.lastIndexOf('P');
      expect(lastP, lessThan(firstIndex['C']!));
      expect(families.lastIndexOf('C'), lessThan(firstIndex['U']!));
      expect(all.indexOf('P0999'), lessThan(all.indexOf('P0A78')));
      expect(all.indexOf('P0AFA'), lessThan(all.indexOf('P2002')));
    });

    test('contacteur HT relié à P0AA1 et à la vue BEV', () {
      expect(codes(data.dtcsForPart('hv-contactor')), contains('P0AA1'));
      final bev = data.view('electric-bev-drive');
      expect(bev?.parts.map((p) => p.slug), contains('hv-contactor'));
    });
  });

  group('filtre à particules essence', () {
    Future<void> pump(WidgetTester tester, EngineSpecInfo spec) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: EngineSheet(spec: spec))));

    testWidgets('essence « variant » : GPF, pas FAP', (tester) async {
      await pump(tester, const EngineSpecInfo(code: 'X', name: 'x', fuel: 'petrol', dpf: 'variant'));
      expect(find.text('GPF (FAP essence)'), findsOneWidget);
      expect(find.text('selon version'), findsOneWidget);
      expect(find.text('FAP'), findsNothing);
    });

    testWidgets('diesel : FAP ; essence sans filtre : aucune ligne', (tester) async {
      await pump(tester, const EngineSpecInfo(code: 'D', name: 'd', fuel: 'diesel', dpf: 'yes'));
      expect(find.text('FAP'), findsOneWidget);
      await pump(tester, const EngineSpecInfo(code: 'E', name: 'e', fuel: 'petrol'));
      expect(find.textContaining('GPF'), findsNothing);
      expect(find.text('FAP'), findsNothing);
    });

    test('les moteurs essence « variant » de engine_specs affichent GPF', () {
      final gpf = data.engineSpecs.where((s) => s.fuel == 'petrol' && s.dpf == 'variant');
      expect(gpf, isNotEmpty);
      for (final s in gpf) {
        expect(s.particleFilterName, 'GPF (FAP essence)', reason: s.code);
      }
    });
  });
}
