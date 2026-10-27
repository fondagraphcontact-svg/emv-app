import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../maintenance/maintenance_screen.dart';
import '../models.dart';
import '../plate/identify_card.dart';
import '../state.dart';
import '../theme.dart';
import 'model_sheet.dart';

class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  String _query = '';
  VehicleKind? _kind;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _prefill(String query, VehicleKind? kind) => setState(() {
        _search.text = query;
        _query = query;
        if (kind != null) _kind = kind;
      });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final results = state.data.searchVehicles(_query, kind: _kind);
    final current = state.current;

    return Scaffold(
      appBar: AppBar(title: const Text('Véhicule')),
      body: CustomScrollView(slivers: [
        SliverList.list(children: [
          if (current != null) _CurrentVehicleCard(vehicle: current),
          if (current != null) ModelSheetCard(vehicle: current),
          IdentifyVehicleCard(onSearch: _prefill),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              key: const Key('vehicle-search'),
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Marque, modèle, année, moteur…',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SegmentedButton<VehicleKind?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: null, label: Text('Tous')),
                ButtonSegment(
                    value: VehicleKind.car,
                    icon: Icon(Icons.directions_car),
                    label: Text('Voiture')),
                ButtonSegment(
                    value: VehicleKind.moto,
                    icon: Icon(Icons.two_wheeler),
                    label: Text('Moto')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ),
        ]),
        results.isEmpty
            ? const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('Aucun véhicule trouvé',
                      style: TextStyle(color: Colors.white60))))
            : SliverList.builder(
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final v = results[i];
                  final isCurrent = v.id == current?.id;
                  return ListTile(
                    leading: Icon(
                        v.kind == VehicleKind.moto
                            ? Icons.two_wheeler
                            : Icons.directions_car,
                        color: isCurrent ? EmvColors.accent : null),
                    title: Text(v.title),
                    subtitle: Text(v.subtitle),
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle,
                            color: EmvColors.accent)
                        : null,
                    onTap: () async {
                      await state.setVehicle(v);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${v.title} enregistré'),
                        action: SnackBarAction(
                          label: 'Voir les vues',
                          onPressed: () => state.selectTab(AppTab.views),
                        ),
                      ));
                    },
                  );
                },
              ),
      ]),
    );
  }
}

class _CurrentVehicleCard extends StatelessWidget {
  final Vehicle vehicle;

  const _CurrentVehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final family = state.data.family(vehicle.family);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: EmvColors.accent),
      ),
      child: ListTile(
        leading: const Icon(Icons.garage, color: EmvColors.accent),
        title: Text(vehicle.title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          vehicle.subtitle,
          family?.name ?? vehicle.family,
        ].where((s) => s.isNotEmpty).join('\n')),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key: const Key('vehicle-maintenance'),
            tooltip: 'Carnet d\'entretien',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => openMaintenance(context, vehicle),
          ),
          IconButton(
            tooltip: 'Retirer le véhicule courant',
            icon: const Icon(Icons.close),
            onPressed: () => state.setVehicle(null),
          ),
        ]),
        onTap: () => state.selectTab(AppTab.views),
      ),
    );
  }
}
