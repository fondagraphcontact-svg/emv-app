import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'plate_format.dart';

/// Vehicle data returned by the backend for a plate (fields may be empty).
class PlateInfo {
  final String make;
  final String model;
  final int? year;
  final String engine;
  final String fuel;
  final String? vin;

  const PlateInfo({
    required this.make,
    this.model = '',
    this.year,
    this.engine = '',
    this.fuel = '',
    this.vin,
  });

  factory PlateInfo.fromJson(Map<String, dynamic> j) {
    final y = j['year'];
    final vin = j['vin']?.toString().trim();
    return PlateInfo(
      make: j['make']?.toString().trim() ?? '',
      model: j['model']?.toString().trim() ?? '',
      year: y is num ? y.toInt() : int.tryParse('${y ?? ''}'),
      engine: j['engine']?.toString().trim() ?? '',
      fuel: j['fuel']?.toString().trim() ?? '',
      vin: vin == null || vin.isEmpty ? null : vin,
    );
  }
}

enum PlateLookupError { notConfigured, unavailable, unknownPlate, invalidPlate, rateLimited }

class PlateLookupException implements Exception {
  final PlateLookupError error;

  const PlateLookupException(this.error);

  String get message => switch (error) {
        PlateLookupError.notConfigured =>
          'Recherche par plaque : service non configuré. Utilisez le VIN '
              '(carte grise, case E) ou la recherche manuelle.',
        PlateLookupError.unavailable =>
          'Recherche par plaque : service indisponible, réessayez plus tard.',
        PlateLookupError.unknownPlate =>
          'Plaque inconnue : aucun véhicule trouvé pour cette immatriculation.',
        PlateLookupError.invalidPlate => 'Plaque refusée par le service.',
        PlateLookupError.rateLimited =>
          'Trop de recherches depuis cet appareil, réessayez dans une heure.',
      };

  @override
  String toString() => message;
}

abstract class PlateLookupService {
  bool get isConfigured;

  /// Throws [PlateLookupException] with a French message on failure.
  Future<PlateInfo> lookup(Plate plate);
}

/// Calls our backend (`POST <backendUrl>/plate`), never the paid provider
/// directly: the provider key must stay out of the app.
class HttpPlateLookup implements PlateLookupService {
  final String backendUrl;
  final http.Client _client;
  final Duration timeout;

  HttpPlateLookup({
    String? backendUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  })  : backendUrl = (backendUrl ?? plateBackendUrl).trim(),
        _client = client ?? http.Client();

  @override
  bool get isConfigured => backendUrl.isNotEmpty;

  @override
  Future<PlateInfo> lookup(Plate plate) async {
    if (!isConfigured) {
      throw const PlateLookupException(PlateLookupError.notConfigured);
    }
    final base = backendUrl.endsWith('/')
        ? backendUrl.substring(0, backendUrl.length - 1)
        : backendUrl;
    final http.Response res;
    try {
      res = await _client
          .post(Uri.parse('$base/plate'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'plate': plate.value}))
          .timeout(timeout);
    } on TimeoutException {
      throw const PlateLookupException(PlateLookupError.unavailable);
    } on http.ClientException {
      throw const PlateLookupException(PlateLookupError.unavailable);
    } on FormatException {
      throw const PlateLookupException(PlateLookupError.notConfigured);
    }
    switch (res.statusCode) {
      case 200:
        break;
      case 404:
        throw const PlateLookupException(PlateLookupError.unknownPlate);
      case 400:
        throw const PlateLookupException(PlateLookupError.invalidPlate);
      case 429:
        throw const PlateLookupException(PlateLookupError.rateLimited);
      default:
        throw const PlateLookupException(PlateLookupError.unavailable);
    }
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final info = PlateInfo.fromJson(body as Map<String, dynamic>);
      if (info.make.isEmpty) {
        throw const PlateLookupException(PlateLookupError.unknownPlate);
      }
      return info;
    } on PlateLookupException {
      rethrow;
    } catch (_) {
      throw const PlateLookupException(PlateLookupError.unavailable);
    }
  }
}
