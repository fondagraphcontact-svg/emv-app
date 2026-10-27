import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

const engineDisclaimer =
    'Schéma pédagogique EMV, indépendant du constructeur : la disposition '
    'réelle des pièces peut différer. Vérifie le code moteur (plaque, carte '
    'grise, documentation) avant toute commande de pièce.';

Future<void> showEngineSheet(BuildContext context, EngineSpecInfo spec) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            EngineSheet(spec: spec, controller: controller),
      ),
    );

class EngineSheet extends StatelessWidget {
  final EngineSpecInfo spec;
  final ScrollController? controller;

  const EngineSheet({super.key, required this.spec, this.controller});

  @override
  Widget build(BuildContext context) {
    final s = spec;
    final rows = <(String, String)>[
      ('Architecture', s.layoutLabel),
      if (s.displacement != null) ('Cylindrée', '${s.displacement} cm³'),
      ('Soupapes', '${s.valves}'),
      ('Distribution', s.timingLabel),
      ('Carburant', fuelLabel(s.fuel)),
      ('Injection', s.injectionLabel),
      ('Suralimentation', s.turboLabel),
      if (s.kind != VehicleKind.moto) ('Vanne EGR', s.egr ? 'oui' : 'non'),
      if (s.particleFilterName case final name?) (name, s.dpfLabel),
      ('Refroidissement', s.coolingLabel),
      if (s.aliases.isNotEmpty) ('Codes proches', s.aliases.join(', ')),
    ];
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Moteur ${s.code}',
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: EmvColors.accent)),
        Text(s.name, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 150,
                  child: Text(k, style: const TextStyle(color: Colors.white60))),
              Expanded(child: Text(v)),
            ]),
          ),
        if (s.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Points à surveiller',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final n in s.notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  '),
                Expanded(child: Text(n)),
              ]),
            ),
        ],
        if (s.vehicles.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Monté notamment sur',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(s.vehicles.join(' · '),
              style: const TextStyle(color: Colors.white70)),
        ],
        const SizedBox(height: 16),
        const Text(engineDisclaimer,
            key: Key('engine-disclaimer'),
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
