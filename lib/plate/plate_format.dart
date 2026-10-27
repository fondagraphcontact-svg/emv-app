enum PlateFormat { siv, fni }

/// French registration plate, stored in its canonical display form.
class Plate {
  final String value;
  final PlateFormat format;

  const Plate._(this.value, this.format);

  /// Letters and digits only, as expected by most lookup providers.
  String get compact => value.replaceAll(RegExp(r'[^A-Z0-9]'), '');

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is Plate && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Uppercase, without spaces, dashes or dots.
String compactPlate(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

// SIV (since 2009): I, O and U are never issued, SS is excluded from both
// letter blocks and 000 from the digits; WW is the temporary series.
final _siv = RegExp(r'^([A-HJ-NP-TV-Z]{2})([0-9]{3})([A-HJ-NP-TV-Z]{2})$');

// FNI (before 2009): 1-4 digits, 1-3 letters, department (01-95, 2A/2B,
// 971-976 overseas).
final _fni = RegExp(r'^([0-9]{1,4})([A-Z]{1,3})(97[1-6]|2A|2B|[0-9]{2})$');

Plate? parsePlate(String input) {
  final c = compactPlate(input);
  final siv = _siv.firstMatch(c);
  if (siv != null) {
    final a = siv.group(1)!, n = siv.group(2)!, b = siv.group(3)!;
    if (a == 'SS' || b == 'SS' || n == '000') return null;
    return Plate._('$a-$n-$b', PlateFormat.siv);
  }
  final fni = _fni.firstMatch(c);
  if (fni != null) {
    final n = fni.group(1)!, l = fni.group(2)!, d = fni.group(3)!;
    final dept = int.tryParse(d);
    if (int.parse(n) == 0) return null;
    if (dept != null && (dept < 1 || (dept > 95 && dept < 971))) return null;
    return Plate._('$n $l $d', PlateFormat.fni);
  }
  return null;
}

/// French error message for an invalid entry, null when the plate is valid.
String? plateError(String input) {
  final c = compactPlate(input);
  if (c.isEmpty) return 'Saisissez une plaque, par exemple AB-123-CD.';
  if (parsePlate(input) != null) return null;
  return 'Plaque non reconnue : format attendu AB-123-CD '
      '(ou ancien format 1234 AB 69).';
}
