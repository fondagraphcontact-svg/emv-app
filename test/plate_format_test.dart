import 'package:emv/plate/plate_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SIV', () {
    test('normalise casse, espaces et tirets', () {
      for (final input in ['ab-123-cd', 'AB 123 CD', 'ab123cd', ' AB.123-cd ']) {
        final p = parsePlate(input);
        expect(p?.value, 'AB-123-CD', reason: input);
        expect(p?.format, PlateFormat.siv);
        expect(p?.compact, 'AB123CD');
      }
    });

    test('refuse I, O, U, SS et 000', () {
      for (final bad in ['AI-123-CD', 'AB-123-CO', 'UB-123-CD', 'SS-123-AB',
          'AB-123-SS', 'AB-000-CD', 'AB-12-CD', 'ABC-123-DE']) {
        expect(parsePlate(bad), isNull, reason: bad);
        expect(plateError(bad), isNotNull, reason: bad);
      }
    });
  });

  group('FNI', () {
    test('formats valides', () {
      expect(parsePlate('1234 AB 69')?.value, '1234 AB 69');
      expect(parsePlate('1234ab69')?.format, PlateFormat.fni);
      expect(parsePlate('12 ABC 2A')?.value, '12 ABC 2A');
      expect(parsePlate('123-AB-974')?.value, '123 AB 974');
      expect(parsePlate('1 A 01')?.value, '1 A 01');
    });

    test('départements invalides', () {
      for (final bad in ['1234 AB 00', '1234 AB 99', '1234 AB 977', '0 AB 69']) {
        expect(parsePlate(bad), isNull, reason: bad);
      }
    });
  });

  test('messages d\'erreur en français', () {
    expect(plateError(''), contains('Saisissez'));
    expect(plateError('XYZ'), contains('AB-123-CD'));
    expect(plateError('AB-123-CD'), isNull);
  });
}
