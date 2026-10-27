import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'expense.dart';

/// Dépenses par véhicule, persistées comme le carnet (liste JSON dans
/// shared_preferences). Une instance par SharedPreferences pour ne pas
/// toucher AppState, partagé avec d'autres chantiers.
class ExpenseStore extends ChangeNotifier {
  static const prefsKey = 'expenses.entries';
  static final _instances = Expando<ExpenseStore>();
  static int _seq = 0;

  final SharedPreferences prefs;
  List<Expense> _entries;

  ExpenseStore._(this.prefs) : _entries = _read(prefs);

  factory ExpenseStore.of(SharedPreferences prefs) =>
      _instances[prefs] ??= ExpenseStore._(prefs);

  static List<Expense> _read(SharedPreferences prefs) => [
        for (final s in prefs.getStringList(prefsKey) ?? const <String>[])
          ?_decode(s)
      ];

  static Expense? _decode(String raw) {
    try {
      return Expense.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_seq++}';

  static int _byDateDesc(Expense a, Expense b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : b.id.compareTo(a.id);
  }

  /// Dépenses d'un véhicule, de la plus récente à la plus ancienne.
  List<Expense> entriesFor(String vehicleId) =>
      _entries.where((e) => e.vehicleId == vehicleId).toList()
        ..sort(_byDateDesc);

  Expense? linkedTo(String maintenanceId) {
    for (final e in _entries) {
      if (e.maintenanceId == maintenanceId) return e;
    }
    return null;
  }

  /// Ajoute ou remplace (même id).
  Future<void> save(Expense expense) {
    final i = _entries.indexWhere((e) => e.id == expense.id);
    return _replace(i < 0
        ? [..._entries, expense]
        : ([..._entries]..[i] = expense));
  }

  Future<void> delete(String id) =>
      _replace([for (final e in _entries) if (e.id != id) e]);

  /// Une seule écriture de la liste complète : pas d'état intermédiaire.
  Future<void> _replace(List<Expense> next) async {
    final ok = await prefs.setStringList(
        prefsKey, [for (final e in next) jsonEncode(e.toJson())]);
    if (!ok) throw StateError('Écriture des dépenses impossible');
    _entries = next;
    notifyListeners();
  }
}
