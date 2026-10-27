enum CodeStatus { open, resolved }

final _codePattern = RegExp(r'^[PCBU][0-9A-F]{4}$');

String normalizeCode(String raw) =>
    raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// Message d'erreur pour un code saisi, null s'il est valide.
String? codeFormatError(String raw) {
  final code = normalizeCode(raw);
  if (code.isEmpty) return 'Saisissez un code';
  if (!_codePattern.hasMatch(code)) {
    return 'Format attendu : P, C, B ou U + 4 caractères (ex. P0301)';
  }
  return null;
}

class CodeLogEntry {
  final String id;
  final String vehicleKey;
  final String code;
  final DateTime date;
  final int? km;
  final String note;
  final DateTime? resolvedAt;

  const CodeLogEntry({
    required this.id,
    required this.vehicleKey,
    required this.code,
    required this.date,
    this.km,
    this.note = '',
    this.resolvedAt,
  });

  CodeStatus get status =>
      resolvedAt == null ? CodeStatus.open : CodeStatus.resolved;
  bool get isOpen => status == CodeStatus.open;

  CodeLogEntry resolved(DateTime? at) => CodeLogEntry(
        id: id,
        vehicleKey: vehicleKey,
        code: code,
        date: date,
        km: km,
        note: note,
        resolvedAt: at,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleKey': vehicleKey,
        'code': code,
        'date': date.toIso8601String(),
        if (km != null) 'km': km,
        if (note.isNotEmpty) 'note': note,
        'status': isOpen ? 'ouvert' : 'résolu',
        if (resolvedAt != null) 'resolvedAt': resolvedAt!.toIso8601String(),
      };

  factory CodeLogEntry.fromJson(Map<String, dynamic> j) => CodeLogEntry(
        id: j['id'].toString(),
        vehicleKey: j['vehicleKey'].toString(),
        code: normalizeCode(j['code'].toString()),
        date: DateTime.parse(j['date'].toString()),
        km: (j['km'] as num?)?.toInt(),
        note: j['note']?.toString() ?? '',
        resolvedAt: j['resolvedAt'] == null
            ? null
            : DateTime.tryParse(j['resolvedAt'].toString()),
      );
}
