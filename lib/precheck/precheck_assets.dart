import 'package:flutter/services.dart';

import 'precheck_models.dart';

Future<PrecheckData>? _cached;
PrecheckData? _loaded;

PrecheckData? get loadedPrecheck => _loaded;

Future<PrecheckData> loadPrecheck([AssetBundle? bundle]) {
  if (bundle != null) {
    return bundle.loadString('assets/data/precheck.json').then(parsePrecheck);
  }
  return _cached ??= rootBundle
      .loadString('assets/data/precheck.json')
      .then((raw) => _loaded = parsePrecheck(raw))
      .catchError((Object e) {
    _cached = null;
    throw e;
  });
}
