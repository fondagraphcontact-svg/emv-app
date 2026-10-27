class MaintenanceEntry {
  final String id;
  final String vehicleKey;
  final DateTime date;
  final int? km;
  final String title;
  final List<String> parts;
  final double? cost;
  final String note;
  final DateTime? reminderDate;
  final int? reminderKm;

  const MaintenanceEntry({
    required this.id,
    required this.vehicleKey,
    required this.date,
    required this.title,
    this.km,
    this.parts = const [],
    this.cost,
    this.note = '',
    this.reminderDate,
    this.reminderKm,
  });

  bool get hasReminder => reminderDate != null || reminderKm != null;

  /// Identifiant stable et positif pour flutter_local_notifications.
  int get notificationId => id.hashCode & 0x7fffffff;

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleKey': vehicleKey,
        'date': date.toIso8601String(),
        if (km != null) 'km': km,
        'title': title,
        'parts': parts,
        if (cost != null) 'cost': cost,
        if (note.isNotEmpty) 'note': note,
        if (reminderDate != null) 'reminderDate': reminderDate!.toIso8601String(),
        if (reminderKm != null) 'reminderKm': reminderKm,
      };

  factory MaintenanceEntry.fromJson(Map<String, dynamic> j) => MaintenanceEntry(
        id: j['id'].toString(),
        vehicleKey: j['vehicleKey'].toString(),
        date: DateTime.parse(j['date'].toString()),
        km: (j['km'] as num?)?.toInt(),
        title: j['title']?.toString() ?? '',
        parts: [for (final p in (j['parts'] as List? ?? const [])) p.toString()],
        cost: (j['cost'] as num?)?.toDouble(),
        note: j['note']?.toString() ?? '',
        reminderDate: j['reminderDate'] == null
            ? null
            : DateTime.tryParse(j['reminderDate'].toString()),
        reminderKm: (j['reminderKm'] as num?)?.toInt(),
      );
}

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String formatKm(int km) {
  final s = km.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b km';
}

String formatCost(double c) =>
    '${c.toStringAsFixed(c.truncateToDouble() == c ? 0 : 2).replaceAll('.', ',')} €';
