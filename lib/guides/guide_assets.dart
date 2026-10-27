import 'package:flutter/services.dart';

import 'guide_models.dart';

Future<List<Guide>>? _cached;
List<Guide>? _loaded;

/// Guides déjà chargés, pour afficher sans attendre une frame.
List<Guide>? get loadedGuides => _loaded;

Future<List<Guide>> loadGuides([AssetBundle? bundle]) {
  if (bundle != null) {
    return bundle.loadString('assets/data/guides.json').then(parseGuideList);
  }
  return _cached ??= rootBundle
      .loadString('assets/data/guides.json')
      .then((raw) => _loaded = parseGuideList(raw))
      .catchError((Object e) {
    _cached = null;
    throw e;
  });
}
