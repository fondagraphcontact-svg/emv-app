import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import 'match.dart';
import 'plate_format.dart';
import 'plate_lookup.dart';
import 'vin_decoder.dart';

enum IdentifyMode { plate, vin }

/// "Identifier mon véhicule" block of the Véhicule screen: plate lookup via
/// our backend, or offline VIN decoding that prefills the manual search.
class IdentifyVehicleCard extends StatefulWidget {
  final PlateLookupService? lookup;
  final VinDecoder? vinDecoder;
  final void Function(String query, VehicleKind? kind) onSearch;
  final bool initiallyExpanded;

  const IdentifyVehicleCard({
    super.key,
    required this.onSearch,
    this.lookup,
    this.vinDecoder,
    this.initiallyExpanded = false,
  });

  @override
  State<IdentifyVehicleCard> createState() => _IdentifyVehicleCardState();
}

class _IdentifyVehicleCardState extends State<IdentifyVehicleCard> {
  final _controller = TextEditingController();
  late final PlateLookupService _lookup = widget.lookup ?? HttpPlateLookup();
  IdentifyMode _mode = IdentifyMode.plate;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show(String? message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = error;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    List<Vehicle>? choices;
    try {
      if (_mode == IdentifyMode.plate) {
        choices = await _searchPlate();
      } else {
        await _decodeVin();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (choices != null && mounted) await _pick(choices);
  }

  /// Engines to choose from when the plate matches several.
  Future<List<Vehicle>?> _searchPlate() async {
    final input = _controller.text;
    final error = plateError(input);
    if (error != null) {
      _show(error, error: true);
      return null;
    }
    final plate = parsePlate(input)!;
    _controller.text = plate.value;
    if (!_lookup.isConfigured) {
      _show(const PlateLookupException(PlateLookupError.notConfigured).message,
          error: true);
      return null;
    }
    final PlateInfo info;
    try {
      info = await _lookup.lookup(plate);
    } on PlateLookupException catch (e) {
      _show(e.message, error: true);
      return null;
    }
    if (!mounted) return null;
    final data = context.read<AppState>().data;
    final result = matchVehicles(data, VehicleQuery.fromPlate(info));
    final label = [info.make, info.model, if (info.year != null) '${info.year}']
        .where((s) => s.isNotEmpty)
        .join(' ');
    if (result.isEmpty) {
      widget.onSearch(result.make ?? info.make, null);
      _show('$label : pas encore dans EMV. Choisissez le modèle le plus '
          'proche dans la liste ci-dessous.');
      return null;
    }
    final single = result.single;
    if (single != null) {
      _show('$label → ${single.title} · ${single.engine}');
      await _select(single);
      return null;
    }
    _show('$label : ${result.candidates.length} motorisations possibles.');
    return result.vehicles;
  }

  Future<void> _decodeVin() async {
    final input = _controller.text;
    final error = vinError(input);
    if (error != null) return _show(error, error: true);
    final decoder = widget.vinDecoder ?? await VinDecoder.load();
    final info = decoder.decode(input)!;
    _controller.text = info.vin;
    final wmi = info.wmi;
    if (wmi == null) {
      return _show(
          'Constructeur non reconnu (code ${info.vin.substring(0, 3)}). '
          'Cherchez votre véhicule manuellement.',
          error: true);
    }
    widget.onSearch(
        [wmi.make, if (info.year != null) '${info.year}'].join(' '), wmi.kind);
    _show([
      '${wmi.make} · fabriqué en ${wmi.country}',
      info.year != null
          ? 'année modèle ${info.year}'
          : 'année non codée dans ce VIN',
      'choisissez le modèle ci-dessous',
    ].join(' · '));
  }

  Future<void> _select(Vehicle v) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    await state.setVehicle(v);
    messenger.showSnackBar(SnackBar(
      content: Text('${v.title} enregistré'),
      action: SnackBarAction(
        label: 'Voir les vues',
        onPressed: () => state.selectTab(AppTab.views),
      ),
    ));
  }

  Future<void> _pick(List<Vehicle> vehicles) async {
    final chosen = await showModalBottomSheet<Vehicle>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(
              title: Text('Quelle motorisation ?',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Vérifiez sur la carte grise (P.1 cylindrée, '
                  'P.2 puissance kW, P.3 énergie).'),
            ),
            Flexible(
              child: ListView(
                key: const Key('plate-candidates'),
                shrinkWrap: true,
                children: [
                  for (final v in vehicles)
                    ListTile(
                      leading: Icon(v.kind == VehicleKind.moto
                          ? Icons.two_wheeler
                          : Icons.directions_car),
                      title: Text(v.title),
                      subtitle: Text(v.subtitle),
                      onTap: () => Navigator.pop(context, v),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
    if (chosen != null && mounted) await _select(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final plate = _mode == IdentifyMode.plate;
    return Card(
      key: const Key('identify-card'),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        leading: const Icon(Icons.badge_outlined, color: EmvColors.accent),
        title: const Text('Identifier mon véhicule'),
        subtitle: const Text('Par plaque ou par VIN'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          SegmentedButton<IdentifyMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: IdentifyMode.plate,
                  icon: Icon(Icons.pin_outlined),
                  label: Text('Plaque')),
              ButtonSegment(
                  value: IdentifyMode.vin,
                  icon: Icon(Icons.qr_code_2),
                  label: Text('VIN')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _controller.clear();
              _message = null;
            }),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: Key(plate ? 'plate-field' : 'vin-field'),
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: plate ? 12 : 20,
                decoration: InputDecoration(
                  counterText: '',
                  labelText: plate ? 'Plaque (AA-123-AA)' : 'VIN (17 caractères)',
                  hintText: plate ? 'AB-123-CD' : 'VF1…',
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('identify-submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Rechercher'),
            ),
          ]),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                key: const Key('identify-message'),
                style: TextStyle(
                    color: _isError ? EmvColors.severity(3) : Colors.white70),
              ),
            ),
          if (plate && !_lookup.isConfigured && _message == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Recherche par plaque bientôt disponible. En attendant, '
                'le VIN (case E de la carte grise) fonctionne hors ligne.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
