import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'code_entry.dart';

/// Journal des codes relevés, persisté comme le carnet (liste JSON dans
/// shared_preferences). Une instance par SharedPreferences pour ne pas
/// toucher AppState, partagé avec d'autres chantiers.
class CodeLogStore extends ChangeNotifier {
  static const prefsKey = 'codelog.entries';
  static final _instances = Expando<CodeLogStore>();
  static int _seq = 0;

  final SharedPreferences prefs;
  List<CodeLogEntry> _entries;

  CodeLogStore._(this.prefs) : _entries = _read(prefs);

  factory CodeLogStore.of(SharedPreferences prefs) =>
      _instances[prefs] ??= CodeLogStore._(prefs);

  static List<CodeLogEntry> _read(SharedPreferences prefs) => [
        for (final s in prefs.getStringList(prefsKey) ?? const <String>[])
          ?_decode(s)
      ];

  static CodeLogEntry? _decode(String raw) {
    try {
      return CodeLogEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static int _byDateDesc(CodeLogEntry a, CodeLogEntry b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : b.id.compareTo(a.id);
  }

  /// Entrées d'un véhicule, de la plus récente à la plus ancienne.
  List<CodeLogEntry> entriesFor(String vehicleKey) =>
      _entries.where((e) => e.vehicleKey == vehicleKey).toList()
        ..sort(_byDateDesc);

  List<CodeLogEntry> openFor(String vehicleKey) =>
      [for (final e in entriesFor(vehicleKey)) if (e.isOpen) e];

  List<CodeLogEntry> resolvedFor(String vehicleKey) =>
      [for (final e in entriesFor(vehicleKey)) if (!e.isOpen) e];

  Future<CodeLogEntry> add({
    required String vehicleKey,
    required String code,
    required DateTime date,
    int? km,
    String note = '',
  }) async {
    final entry = CodeLogEntry(
      // L'horloge seule peut se répéter entre deux ajouts rapprochés.
      id: '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_seq++}',
      vehicleKey: vehicleKey,
      code: normalizeCode(code),
      date: date,
      km: km,
      note: note.trim(),
    );
    await _replace([..._entries, entry]);
    return entry;
  }

  Future<void> markResolved(String id, {DateTime? at}) =>
      _update(id, (e) => e.resolved(at ?? DateTime.now()));

  Future<void> reopen(String id) => _update(id, (e) => e.resolved(null));

  Future<void> delete(String id) =>
      _replace([for (final e in _entries) if (e.id != id) e]);

  Future<void> _update(String id, CodeLogEntry Function(CodeLogEntry) f) =>
      _replace([for (final e in _entries) e.id == id ? f(e) : e]);

  /// Une seule écriture de la liste complète : pas d'état intermédiaire.
  Future<void> _replace(List<CodeLogEntry> next) async {
    final ok = await prefs.setStringList(
        prefsKey, [for (final e in next) jsonEncode(e.toJson())]);
    if (!ok) throw StateError('Écriture du journal des codes impossible');
    _entries = next;
    notifyListeners();
  }
}
