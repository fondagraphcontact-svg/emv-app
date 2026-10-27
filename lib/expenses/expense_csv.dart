import 'dart:convert';
import 'dart:typed_data';

import '../maintenance/maintenance_entry.dart';
import 'expense.dart';

const csvHeader = [
  'Date',
  'Véhicule',
  'Catégorie',
  'Libellé',
  'Montant (€)',
  'Kilométrage',
  'Intervention liée',
];

String _cell(String v) =>
    RegExp(r'[;"\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;

String _amount(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100},'
    '${(cents.abs() % 100).toString().padLeft(2, '0')}';

/// CSV « Excel France » : séparateur point-virgule, virgule décimale, CRLF.
String expensesCsv(
  List<Expense> expenses, {
  required String vehicleTitle,
  Map<String, String> maintenanceTitles = const {},
}) {
  final rows = [
    csvHeader,
    for (final e in expenses)
      [
        formatDate(e.date),
        vehicleTitle,
        e.category.label,
        e.label,
        _amount(e.cents),
        e.km?.toString() ?? '',
        e.maintenanceId == null ? '' : maintenanceTitles[e.maintenanceId] ?? '',
      ],
  ];
  final lines = [for (final r in rows) r.map(_cell).join(';')];
  return '${lines.join('\r\n')}\r\n';
}

/// UTF-8 avec BOM : sans lui, Excel lit les accents en Latin-1.
Uint8List csvBytes(String csv) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
