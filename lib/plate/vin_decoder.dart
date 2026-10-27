import 'dart:convert';

import 'package:flutter/services.dart';

import '../models.dart';

const wmiAsset = 'assets/data/wmi.json';

class WmiEntry {
  final String make;
  final String country;
  final VehicleKind? kind;

  /// True when this manufacturer encodes the model year in position 10
  /// (mandatory in North America only; in Europe e.g. VW group, Volvo, Opel).
  final bool year;

  const WmiEntry(
      {required this.make, required this.country, this.kind, this.year = false});

  factory WmiEntry.fromJson(Map<String, dynamic> j) => WmiEntry(
        make: j['make']?.toString() ?? '',
        country: j['country']?.toString() ?? '',
        kind: switch (j['kind']) {
          'moto' => VehicleKind.moto,
          'car' => VehicleKind.car,
          _ => null,
        },
        year: j['year'] == true,
      );
}

class VinInfo {
  final String vin;
  final WmiEntry? wmi;
  final int? year;

  const VinInfo({required this.vin, this.wmi, this.year});

  String? get make => wmi?.make;
  String? get country => wmi?.country;
}

String normalizeVin(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[\s\-.]'), '');

final _vinChars = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');

/// French error message for an invalid VIN, null when it is well formed.
String? vinError(String input) {
  final v = normalizeVin(input);
  if (v.isEmpty) {
    return 'Saisissez les 17 caractères du VIN (carte grise, case E).';
  }
  if (RegExp(r'[IOQ]').hasMatch(v)) {
    return 'Un VIN ne contient jamais les lettres I, O ni Q '
        '(vérifiez les 1 et les 0).';
  }
  if (v.length != 17) {
    return 'Un VIN compte 17 caractères (vous en avez saisi ${v.length}).';
  }
  if (!_vinChars.hasMatch(v)) return 'VIN invalide : lettres et chiffres uniquement.';
  return null;
}

bool isValidVin(String input) => vinError(input) == null;

const _yearCodes = 'ABCDEFGHJKLMNPRSTVWXY123456789';

/// Model year for a position-10 code. The code repeats every 30 years, so the
/// most recent year not after [currentYear] + 1 is chosen.
int? modelYearFromCode(String code, {int? currentYear}) {
  if (code.length != 1) return null;
  final i = _yearCodes.indexOf(code);
  if (i < 0) return null;
  final limit = (currentYear ?? DateTime.now().year) + 1;
  var year = 1980 + i;
  while (year + 30 <= limit) {
    year += 30;
  }
  return year;
}

class VinDecoder {
  final Map<String, WmiEntry> wmi;

  const VinDecoder(this.wmi);

  factory VinDecoder.fromJson(Map<String, dynamic> j) => VinDecoder({
        for (final e in j.entries)
          if (e.value is Map<String, dynamic>)
            e.key.toUpperCase(): WmiEntry.fromJson(e.value as Map<String, dynamic>)
      });

  static Future<VinDecoder>? _shared;

  static Future<VinDecoder> load([AssetBundle? bundle]) {
    if (bundle != null) return _load(bundle);
    return _shared ??= _load(rootBundle);
  }

  static Future<VinDecoder> _load(AssetBundle b) async =>
      VinDecoder.fromJson(
          jsonDecode(await b.loadString(wmiAsset)) as Map<String, dynamic>);

  /// Null when [input] is not a well-formed VIN.
  VinInfo? decode(String input, {int? currentYear}) {
    final vin = normalizeVin(input);
    if (!isValidVin(vin)) return null;
    final entry = wmi[vin.substring(0, 3)];
    final year = entry != null && entry.year
        ? modelYearFromCode(vin[9], currentYear: currentYear)
        : null;
    return VinInfo(vin: vin, wmi: entry, year: year);
  }
}
