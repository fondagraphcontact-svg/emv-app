import 'package:flutter/material.dart';

enum ExpenseCategory {
  fuel('carburant', 'Carburant', Icons.local_gas_station_outlined,
      Color(0xFF4FC3F7)),
  parts('pieces', 'Pièces', Icons.settings_outlined, Color(0xFFFF8A00)),
  labor('main-oeuvre', 'Main-d\'œuvre', Icons.handyman_outlined,
      Color(0xFFB39DDB)),
  inspection('controle-technique', 'Contrôle technique',
      Icons.fact_check_outlined, Color(0xFF4CC38A)),
  insurance('assurance', 'Assurance', Icons.shield_outlined, Color(0xFFF06292)),
  other('autre', 'Autre', Icons.more_horiz, Color(0xFF9DB9E8));

  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const ExpenseCategory(this.key, this.label, this.icon, this.color);

  static ExpenseCategory fromKey(String? key) =>
      values.firstWhere((c) => c.key == key, orElse: () => other);
}

class Expense {
  final String id;
  final String vehicleId;
  final DateTime date;
  final ExpenseCategory category;

  /// Montant en centimes : les totaux restent exacts.
  final int cents;
  final int? km;
  final String label;
  final String? maintenanceId;

  const Expense({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.category,
    required this.cents,
    this.km,
    this.label = '',
    this.maintenanceId,
  });

  double get amount => cents / 100;

  String get displayLabel => label.isEmpty ? category.label : label;

  Expense copyWith({DateTime? date, int? cents, int? km}) => Expense(
        id: id,
        vehicleId: vehicleId,
        date: date ?? this.date,
        category: category,
        cents: cents ?? this.cents,
        km: km ?? this.km,
        label: label,
        maintenanceId: maintenanceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleId': vehicleId,
        'date': date.toIso8601String(),
        'category': category.key,
        'amount': amount,
        if (km != null) 'km': km,
        if (label.isNotEmpty) 'label': label,
        if (maintenanceId != null) 'maintenanceId': maintenanceId,
      };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'].toString(),
        vehicleId: j['vehicleId'].toString(),
        date: DateTime.parse(j['date'].toString()),
        category: ExpenseCategory.fromKey(j['category']?.toString()),
        cents: ((j['amount'] as num) * 100).round(),
        km: (j['km'] as num?)?.toInt(),
        label: j['label']?.toString() ?? '',
        maintenanceId: j['maintenanceId']?.toString(),
      );
}

enum ExpensePeriod {
  last12Months('12 mois'),
  thisYear('Cette année'),
  all('Tout');

  final String label;

  const ExpensePeriod(this.label);

  bool contains(DateTime d, DateTime now) => switch (this) {
        last12Months => !d.isBefore(DateTime(now.year - 1, now.month, now.day)),
        thisYear => d.year == now.year,
        all => true,
      };
}

List<Expense> inPeriod(List<Expense> list, ExpensePeriod p, DateTime now) =>
    [for (final e in list) if (p.contains(e.date, now)) e];

class ExpenseSummary {
  final Map<ExpenseCategory, int> byCategory;
  final int totalCents;

  /// Kilomètres entre le plus petit et le plus grand relevé saisi.
  final int? distanceKm;

  const ExpenseSummary._(this.byCategory, this.totalCents, this.distanceKm);

  /// En dessous, le coût au km serait surtout du bruit.
  static const minDistanceKm = 500;

  factory ExpenseSummary.of(List<Expense> list) {
    final by = {for (final c in ExpenseCategory.values) c: 0};
    var total = 0;
    int? minKm, maxKm;
    for (final e in list) {
      by[e.category] = by[e.category]! + e.cents;
      total += e.cents;
      final km = e.km;
      if (km != null) {
        if (minKm == null || km < minKm) minKm = km;
        if (maxKm == null || km > maxKm) maxKm = km;
      }
    }
    final distance = minKm == null ? null : maxKm! - minKm;
    return ExpenseSummary._(by, total, distance);
  }

  bool get isEmpty => totalCents == 0;

  /// Catégories non nulles, de la plus coûteuse à la moins coûteuse.
  List<(ExpenseCategory, int)> get ranked => [
        for (final c in ExpenseCategory.values)
          if (byCategory[c]! != 0) (c, byCategory[c]!)
      ]..sort((a, b) => b.$2.compareTo(a.$2));

  /// Euros par km, null si les relevés ne couvrent pas assez de distance.
  double? get costPerKm => distanceKm == null || distanceKm! < minDistanceKm
      ? null
      : totalCents / 100 / distanceKm!;
}

String _groupThousands(int n, String sep) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(sep);
    b.write(s[i]);
  }
  return b.toString();
}

/// « 1 234,50 € » (espaces insécables : le montant ne se coupe pas).
String formatEuros(int cents) {
  final neg = cents < 0;
  final abs = cents.abs();
  final euros = _groupThousands(abs ~/ 100, '\u00a0');
  final rest = (abs % 100).toString().padLeft(2, '0');
  return '${neg ? '-' : ''}$euros,$rest\u00a0€';
}

/// « 0,123 €/km ».
String formatCostPerKm(double v) =>
    '${v.toStringAsFixed(3).replaceAll('.', ',')}\u00a0€/km';

/// Accepte « 79,5 », « 79.50 », « 1 234,56 » ; null si invalide ou négatif.
int? parseEurosToCents(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s\u00a0€]'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;
  return (double.parse(s) * 100).round();
}

/// Catégorie probable d'une intervention du carnet, l'utilisateur la corrige.
ExpenseCategory guessCategory(String title) {
  final t = title.toLowerCase();
  if (t.contains('contrôle technique') ||
      t.contains('controle technique') ||
      RegExp(r'\bct\b').hasMatch(t)) {
    return ExpenseCategory.inspection;
  }
  if (t.contains('main') && t.contains('œuvre')) return ExpenseCategory.labor;
  return ExpenseCategory.parts;
}
