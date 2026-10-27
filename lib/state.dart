import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'maintenance/maintenance_entry.dart';
import 'models.dart';

enum AppTab { vehicle, views, faults, profile, assistant }

class AppState extends ChangeNotifier {
  static const _kCurrent = 'vehicle.current';
  static const _kSaved = 'vehicle.saved';
  static const _kFavorites = 'parts.favorites';
  static const _kDisclaimer = 'disclaimer.accepted';
  static const _kMaintenance = 'maintenance.entries';
  static const _kOdometer = 'vehicle.odometer';
  static const _kRecentDtc = 'dtc.recent';
  static const _kFeedback = 'feedback.votes';
  static const recentDtcLimit = 20;

  final AppData data;
  final SharedPreferences prefs;

  Vehicle? _current;
  List<Vehicle> _saved = [];
  Set<String> _favorites = {};
  bool _disclaimerAccepted = false;
  List<MaintenanceEntry> _maintenance = [];
  Map<String, int> _odometer = {};
  List<RecentDtc> _recentDtc = [];
  Map<String, int> _feedback = {};

  AppTab _tab = AppTab.vehicle;
  String? _openViewId;
  Set<String> _highlighted = {};

  AppState(this.data, this.prefs) {
    _current = _decode(prefs.getString(_kCurrent));
    _saved = [
      for (final s in prefs.getStringList(_kSaved) ?? const <String>[])
        ?_decode(s)
    ];
    _favorites = (prefs.getStringList(_kFavorites) ?? const []).toSet();
    _disclaimerAccepted = prefs.getBool(_kDisclaimer) ?? false;
    _maintenance = [
      for (final s in prefs.getStringList(_kMaintenance) ?? const <String>[])
        ?_decodeEntry(s)
    ];
    _odometer = _intMap(prefs.getString(_kOdometer));
    _recentDtc = [
      for (final s in prefs.getStringList(_kRecentDtc) ?? const <String>[])
        ?RecentDtc.tryParse(s)
    ];
    _feedback = _intMap(prefs.getString(_kFeedback));
    if (_current != null) _tab = AppTab.views;
  }

  static Vehicle? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return Vehicle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static MaintenanceEntry? _decodeEntry(String raw) {
    try {
      return MaintenanceEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Map<String, int> _intMap(String? raw) {
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          if (e.value is num) e.key: (e.value as num).toInt()
      };
    } catch (_) {
      return {};
    }
  }

  Vehicle? get current => _current;
  List<Vehicle> get saved => List.unmodifiable(_saved);
  Set<String> get favorites => Set.unmodifiable(_favorites);
  bool get disclaimerAccepted => _disclaimerAccepted;
  AppTab get tab => _tab;
  ExplodedView? get activeView =>
      _openViewId == null ? null : data.view(_openViewId!);
  Set<String> get highlighted => Set.unmodifiable(_highlighted);

  List<ExplodedView> get availableViews => data.viewsFor(_current);

  Future<void> setVehicle(Vehicle? v) async {
    _current = v;
    _openViewId = null;
    _highlighted = {};
    if (v == null) {
      await prefs.remove(_kCurrent);
    } else {
      await prefs.setString(_kCurrent, jsonEncode(v.toJson()));
      if (!_saved.any((s) => s.id == v.id)) {
        _saved = [v, ..._saved];
        await _persistSaved();
      }
    }
    notifyListeners();
  }

  Future<void> removeSaved(Vehicle v) async {
    _saved = _saved.where((s) => s.id != v.id).toList();
    await _persistSaved();
    if (_current?.id == v.id) {
      await setVehicle(null);
    } else {
      notifyListeners();
    }
  }

  Future<void> _persistSaved() => prefs.setStringList(
      _kSaved, [for (final s in _saved) jsonEncode(s.toJson())]);

  bool isFavorite(String slug) => _favorites.contains(slug);

  Future<void> toggleFavorite(String slug) async {
    if (!_favorites.remove(slug)) _favorites.add(slug);
    await prefs.setStringList(_kFavorites, _favorites.toList()..sort());
    notifyListeners();
  }

  Future<void> acceptDisclaimer() async {
    _disclaimerAccepted = true;
    await prefs.setBool(_kDisclaimer, true);
    notifyListeners();
  }

  void selectTab(AppTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  void openView(String id, {Set<String> highlight = const {}}) {
    _openViewId = id;
    _highlighted = highlight;
    notifyListeners();
  }

  void closeView() {
    _openViewId = null;
    _highlighted = {};
    notifyListeners();
  }

  /// Opens the view holding most of [slugs], highlights them and switches to
  /// the Vues tab. Returns false when no view contains any of them.
  bool showPartsInView(Iterable<String> slugs) {
    final view = data.bestViewFor(slugs, vehicle: _current);
    if (view == null) return false;
    final inView = {
      for (final s in slugs)
        if (view.containsPart(s)) s
    };
    _openViewId = view.id;
    _highlighted = inView;
    _tab = AppTab.views;
    notifyListeners();
    return true;
  }

  /// Entrées du carnet pour un véhicule, de la plus récente à la plus ancienne.
  List<MaintenanceEntry> maintenanceFor(String vehicleKey) =>
      _maintenance.where((e) => e.vehicleKey == vehicleKey).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> saveMaintenance(MaintenanceEntry entry) async {
    final i = _maintenance.indexWhere((e) => e.id == entry.id);
    if (i < 0) {
      _maintenance = [..._maintenance, entry];
    } else {
      _maintenance = [..._maintenance]..[i] = entry;
    }
    await _persistMaintenance();
    notifyListeners();
  }

  Future<void> deleteMaintenance(String id) async {
    _maintenance = _maintenance.where((e) => e.id != id).toList();
    await _persistMaintenance();
    notifyListeners();
  }

  Future<void> _persistMaintenance() => prefs.setStringList(_kMaintenance,
      [for (final e in _maintenance) jsonEncode(e.toJson())]);

  /// Kilométrage connu : saisi manuellement ou le plus élevé du carnet.
  int? odometer(String vehicleKey) {
    final kms = [
      ?_odometer[vehicleKey],
      for (final e in _maintenance)
        if (e.vehicleKey == vehicleKey) ?e.km,
    ];
    return kms.isEmpty ? null : kms.reduce((a, b) => a > b ? a : b);
  }

  Future<void> setOdometer(String vehicleKey, int km) async {
    _odometer = {..._odometer, vehicleKey: km};
    await prefs.setString(_kOdometer, jsonEncode(_odometer));
    notifyListeners();
  }

  /// Rappels kilométriques atteints ou dépassés.
  List<MaintenanceEntry> dueKmReminders(String vehicleKey) {
    final km = odometer(vehicleKey);
    if (km == null) return const [];
    return [
      for (final e in maintenanceFor(vehicleKey))
        if (e.reminderKm != null && e.reminderKm! <= km) e
    ];
  }

  List<RecentDtc> get recentDtcs => List.unmodifiable(_recentDtc);

  Future<void> recordDtcViewed(String code, {DateTime? at}) async {
    _recentDtc = [
      RecentDtc(code, at ?? DateTime.now()),
      for (final r in _recentDtc)
        if (r.code != code) r
    ].take(recentDtcLimit).toList();
    await prefs.setStringList(
        _kRecentDtc, [for (final r in _recentDtc) r.encode()]);
    notifyListeners();
  }

  Future<void> clearRecentDtcs() async {
    _recentDtc = [];
    await prefs.remove(_kRecentDtc);
    notifyListeners();
  }

  /// Vote local sur une fiche : 1 (utile), -1 (pas utile), 0 (aucun).
  int feedbackVote(String key) => _feedback[key] ?? 0;

  Future<void> setFeedbackVote(String key, int vote) async {
    _feedback = {..._feedback}..remove(key);
    if (vote != 0) _feedback[key] = vote.sign;
    await prefs.setString(_kFeedback, jsonEncode(_feedback));
    notifyListeners();
  }
}

class RecentDtc {
  final String code;
  final DateTime at;

  const RecentDtc(this.code, this.at);

  String encode() => '$code|${at.toIso8601String()}';

  static RecentDtc? tryParse(String raw) {
    final i = raw.indexOf('|');
    if (i <= 0) return null;
    final at = DateTime.tryParse(raw.substring(i + 1));
    return at == null ? null : RecentDtc(raw.substring(0, i), at);
  }
}
