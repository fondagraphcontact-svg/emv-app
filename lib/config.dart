import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Adresse provisoire : à remplacer par la boîte définitive avant publication.
const contactEmail = 'contact@electromecaview.app';

const metaAsset = 'assets/data/meta.json';

String? _dataVersion;
bool _dataVersionLoaded = false;

/// `data_version` de assets/data/meta.json, null si le fichier est absent.
Future<String?> loadDataVersion([AssetBundle? bundle]) async {
  if (_dataVersionLoaded) return _dataVersion;
  try {
    final meta = jsonDecode(await (bundle ?? rootBundle).loadString(metaAsset));
    final v = meta is Map ? meta['data_version'] : null;
    _dataVersion = v?.toString();
  } on FlutterError {
    // Asset absent : meta.json est optionnel tant que la QA ne l'a pas livré.
    _dataVersion = null;
  } on FormatException {
    _dataVersion = null;
  }
  _dataVersionLoaded = true;
  return _dataVersion;
}

// URL du Worker plaque (backend/plate-worker), ex. https://emv-plate.<compte>.workers.dev.
// Vide : la recherche par plaque affiche « service non configuré ».
const plateBackendUrl = '';
