import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'precheck_models.dart';

/// Cases cochées du pré-contrôle, une clé `precheck.<vehicleId>` par véhicule
/// (objet JSON id du point → ok | todo ; absent = non vérifié). Hors AppState
/// pour ne pas toucher un fichier partagé avec d'autres chantiers.
class PrecheckStore extends ChangeNotifier {
  static const prefix = 'precheck.';
  static final _instances = Expando<PrecheckStore>();

  final SharedPreferences prefs;
  final Map<String, Map<String, PrecheckStatus>> _cache = {};

  PrecheckStore._(this.prefs);

  factory PrecheckStore.of(SharedPreferences prefs) =>
      _instances[prefs] ??= PrecheckStore._(prefs);

  static String keyFor(String vehicleId) => '$prefix$vehicleId';

  Map<String, PrecheckStatus> statuses(String vehicleId) =>
      Map.unmodifiable(_read(vehicleId));

  PrecheckStatus status(String vehicleId, String pointId) =>
      _read(vehicleId)[pointId] ?? PrecheckStatus.unchecked;

  Map<String, PrecheckStatus> _read(String vehicleId) =>
      _cache[vehicleId] ??= _decode(prefs.getString(keyFor(vehicleId)));

  static Map<String, PrecheckStatus> _decode(String? raw) {
    if (raw == null) return {};
    try {
      final out = <String, PrecheckStatus>{};
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries) {
        final s = switch (e.value) {
          'ok' => PrecheckStatus.ok,
          'todo' => PrecheckStatus.todo,
          _ => null,
        };
        if (s != null) out[e.key] = s;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> set(String vehicleId, String pointId, PrecheckStatus s) {
    final next = {..._read(vehicleId)}..remove(pointId);
    if (s != PrecheckStatus.unchecked) next[pointId] = s;
    return _write(vehicleId, next);
  }

  Future<void> reset(String vehicleId) async {
    final ok = await prefs.remove(keyFor(vehicleId));
    if (!ok) throw StateError('Remise à zéro du pré-contrôle impossible');
    _cache[vehicleId] = {};
    notifyListeners();
  }

  /// Une seule écriture de la carte complète : pas d'état intermédiaire.
  Future<void> _write(
      String vehicleId, Map<String, PrecheckStatus> next) async {
    final ok = next.isEmpty
        ? await prefs.remove(keyFor(vehicleId))
        : await prefs.setString(keyFor(vehicleId),
            jsonEncode({for (final e in next.entries) e.key: e.value.name}));
    if (!ok) throw StateError('Écriture du pré-contrôle impossible');
    _cache[vehicleId] = next;
    notifyListeners();
  }
}
