import 'package:flutter/services.dart';

import 'light_models.dart';

Future<List<DashboardLight>>? _cached;
List<DashboardLight>? _loaded;

List<DashboardLight>? get loadedLights => _loaded;

Future<List<DashboardLight>> loadLights([AssetBundle? bundle]) {
  if (bundle != null) {
    return bundle
        .loadString('assets/data/dashboard_lights.json')
        .then(parseLights);
  }
  return _cached ??= rootBundle
      .loadString('assets/data/dashboard_lights.json')
      .then((raw) => _loaded = parseLights(raw))
      .catchError((Object e) {
    _cached = null;
    throw e;
  });
}
