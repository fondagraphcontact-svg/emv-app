import 'dart:async';
import 'dart:convert';

import 'package:emv/plate/plate_format.dart';
import 'package:emv/plate/plate_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final plate = parsePlate('ab-123-cd')!;

  HttpPlateLookup withResponse(int status, [Object body = const {}]) =>
      HttpPlateLookup(
          backendUrl: 'https://plate.example.test/',
          client: MockClient((req) async {
            expect(req.url.toString(), 'https://plate.example.test/plate');
            expect(jsonDecode(req.body), {'plate': 'AB-123-CD'});
            return http.Response(jsonEncode(body), status,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }));

  Future<PlateLookupError?> errorOf(PlateLookupService s) async {
    try {
      await s.lookup(plate);
      return null;
    } on PlateLookupException catch (e) {
      return e.error;
    }
  }

  test('backendUrl vide : service non configuré, sans appel', () async {
    final s = HttpPlateLookup(
        backendUrl: '',
        client: MockClient((_) async => fail('aucun appel attendu')));
    expect(s.isConfigured, isFalse);
    expect(await errorOf(s), PlateLookupError.notConfigured);
    expect(const PlateLookupException(PlateLookupError.notConfigured).message,
        contains('service non configuré'));
  });

  test('200 : données véhicule', () async {
    final info = await withResponse(200, {
      'make': 'Opel',
      'model': 'Meriva',
      'year': '2011',
      'engine': '1.7 CDTI 110',
      'fuel': 'diesel',
      'vin': 'W0LSD9EC5B4000000',
    }).lookup(plate);
    expect(info.make, 'Opel');
    expect(info.year, 2011);
    expect(info.vin, 'W0LSD9EC5B4000000');
  });

  test('codes HTTP → erreurs lisibles', () async {
    expect(await errorOf(withResponse(404)), PlateLookupError.unknownPlate);
    expect(await errorOf(withResponse(429)), PlateLookupError.rateLimited);
    expect(await errorOf(withResponse(400)), PlateLookupError.invalidPlate);
    expect(await errorOf(withResponse(502)), PlateLookupError.unavailable);
    expect(await errorOf(withResponse(200, {'make': ''})),
        PlateLookupError.unknownPlate);
    expect(const PlateLookupException(PlateLookupError.unavailable).message,
        contains('service indisponible'));
    expect(const PlateLookupException(PlateLookupError.unknownPlate).message,
        contains('Plaque inconnue'));
  });

  test('réseau coupé ou délai dépassé : service indisponible', () async {
    final offline = HttpPlateLookup(
        backendUrl: 'https://plate.example.test',
        client: MockClient((_) async => throw http.ClientException('offline')));
    expect(await errorOf(offline), PlateLookupError.unavailable);
    final slow = HttpPlateLookup(
        backendUrl: 'https://plate.example.test',
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future));
    expect(await errorOf(slow), PlateLookupError.unavailable);
  });
}
