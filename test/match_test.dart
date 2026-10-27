import 'package:emv/data.dart';
import 'package:emv/plate/match.dart';
import 'package:emv/plate/plate_lookup.dart';
import 'package:emv/plate/vin_decoder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await AppData.load(rootBundle);
  });

  test('Meriva B 1.7 CDTI 2011 (réponse type SIV en majuscules)', () {
    final r = matchVehicles(
        data,
        VehicleQuery.fromPlate(PlateInfo.fromJson({
          'make': 'OPEL',
          'model': 'MERIVA',
          'year': 2011,
          'engine': '1.7 CDTI 110',
          'fuel': 'GO',
        })));
    expect(r.single?.model, 'Meriva B');
    expect(r.single?.engine, '1.7 CDTI 110');
  });

  test('Meriva 1.7 CDTI sans puissance : choix des motorisations', () {
    final r = matchVehicles(
        data,
        const VehicleQuery(
            make: 'Opel', model: 'Meriva', year: 2011, engine: '1.7 CDTI',
            fuel: 'diesel'));
    expect(r.candidates.length, greaterThan(1));
    expect(r.vehicles.every((v) => v.model == 'Meriva B'), isTrue);
    expect(r.vehicles.every((v) => v.engine.startsWith('1.7 CDTI')), isTrue);
  });

  test('Laguna 2.0 dCi 150 de 2009 : Laguna III, avec ou sans FAP', () {
    final r = matchVehicles(
        data,
        const VehicleQuery(
            make: 'RENAULT', model: 'LAGUNA', year: 2009,
            engine: '2.0 DCI 150', fuel: 'DIESEL'));
    expect(r.vehicles.map((v) => v.engine).toSet(),
        {'2.0 dCi 150', '2.0 dCi 150 FAP'});
    expect(r.vehicles.every((v) => v.model == 'Laguna III'), isTrue);
  });

  test('Laguna 2.0 dCi 150 sans FAP : une seule motorisation', () {
    final r = matchVehicles(
        data,
        const VehicleQuery(
            make: 'Renault', model: 'Laguna', year: 2009,
            engine: '2.0 dCi 150 sans FAP', fuel: 'diesel'));
    expect(r.single?.model, 'Laguna III');
    expect(r.single?.engine, '2.0 dCi 150');
  });

  test('Laguna de 2005 : Laguna II', () {
    final r = matchVehicles(
        data,
        const VehicleQuery(
            make: 'Renault', model: 'Laguna', year: 2005,
            engine: '1.9 dCi 120', fuel: 'GO'));
    expect(r.single?.model, 'Laguna II');
  });

  test('marque absente ou modèle inconnu', () {
    expect(matchVehicles(data, const VehicleQuery(make: 'Trabant')).isEmpty,
        isTrue);
    final r = matchVehicles(
        data, const VehicleQuery(make: 'Renault', model: 'Zzzmodel'));
    expect(r.isEmpty, isTrue);
    expect(r.make, 'Renault');
  });

  test('alias de marque et carburants SIV', () {
    expect(resolveMake(data, 'MERCEDES'), 'Mercedes-Benz');
    expect(resolveMake(data, 'CITROEN'), 'Citroën');
    expect(resolveMake(data, 'VW'), 'Volkswagen');
    expect(canonicalFuel('GO'), 'diesel');
    expect(canonicalFuel('ESSENCE'), 'petrol');
    expect(canonicalFuel('EE'), 'hybrid');
    expect(canonicalFuel('EL'), 'electric');
    expect(canonicalFuel('?'), '');
  });

  test('VIN Yamaha : marque moto', () async {
    final vin = (await VinDecoder.load(rootBundle)).decode('JYARN23E00A000123')!;
    final r = matchVehicles(data, VehicleQuery.fromVin(vin));
    expect(r.make, 'Yamaha');
    expect(r.vehicles, isNotEmpty);
  });
}
