import 'package:emv/models.dart';
import 'package:emv/plate/vin_decoder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late VinDecoder decoder;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    decoder = await VinDecoder.load(rootBundle);
  });

  test('wmi.json : ~250+ constructeurs, champs remplis', () {
    expect(decoder.wmi.length, greaterThanOrEqualTo(250));
    for (final e in decoder.wmi.entries) {
      expect(e.key, matches(RegExp(r'^[A-HJ-NPR-Z0-9]{3}$')), reason: e.key);
      expect(e.value.make, isNotEmpty, reason: e.key);
      expect(e.value.country, isNotEmpty, reason: e.key);
    }
  });

  test('validation : 17 caractères, ni I ni O ni Q', () {
    expect(vinError('VF1BZ0B0644123456'), isNull);
    expect(vinError('vf1-bz0b0 644123456'), isNull);
    expect(vinError('VF1BZ0B064412345'), contains('17'));
    expect(vinError('VF1BZOB0644123456'), contains('I, O ni Q'));
    expect(vinError('VF1BZ0B0644I23456'), isNotNull);
    expect(vinError('VF1BZ0B0644Q23456'), isNotNull);
    expect(vinError(''), contains('case E'));
    expect(decoder.decode('VF1BZ0B064412345'), isNull);
  });

  test('VF1 : Renault France, pas d\'année en position 10', () {
    final v = decoder.decode('VF1BZ0B0644123456')!;
    expect(v.make, 'Renault');
    expect(v.country, 'France');
    expect(v.year, isNull);
  });

  test('WVW : Volkswagen, année modèle position 10', () {
    final v = decoder.decode('WVWZZZ1KZBW123456', currentYear: 2026)!;
    expect(v.make, 'Volkswagen');
    expect(v.country, 'Allemagne');
    expect(v.year, 2011);
    expect(decoder.decode('WVWZZZAUZPW123456', currentYear: 2026)!.year, 2023);
    expect(decoder.decode('WVWZZZ1JZ3W123456', currentYear: 2026)!.year, 2003);
  });

  test('JYA : Yamaha moto, Japon', () {
    final v = decoder.decode('JYARN23E00A000123')!;
    expect(v.make, 'Yamaha');
    expect(v.country, 'Japon');
    expect(v.wmi!.kind, VehicleKind.moto);
    expect(v.year, isNull);
  });

  test('WMI inconnu : VIN valide sans constructeur', () {
    final v = decoder.decode('ZZZ12345678901234')!;
    expect(v.wmi, isNull);
    expect(v.make, isNull);
  });

  test('cycle de 30 ans des codes année', () {
    expect(modelYearFromCode('A', currentYear: 2026), 2010);
    expect(modelYearFromCode('Y', currentYear: 2026), 2000);
    expect(modelYearFromCode('T', currentYear: 2026), 2026);
    expect(modelYearFromCode('V', currentYear: 2026), 2027);
    expect(modelYearFromCode('W', currentYear: 2026), 1998);
    expect(modelYearFromCode('0'), isNull);
    expect(modelYearFromCode(''), isNull);
  });
}
