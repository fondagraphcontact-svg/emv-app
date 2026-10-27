import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/part_sheet.dart';
import 'faults.dart';

const modelDisclaimer =
    'Fiche rédigée par EMV à partir d\'informations publiques, à titre '
    'indicatif : la notice d\'utilisation et le carnet d\'entretien du '
    'véhicule font foi.';

class ModelSheetCard extends StatelessWidget {
  final Vehicle vehicle;

  const ModelSheetCard({super.key, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final data = context.read<AppState>().data;
    final spec = data.modelSpecFor(vehicle);
    if (spec == null) return const SizedBox.shrink();
    final issues = data.issuesFor(vehicle).length;
    return Card(
      key: const Key('model-sheet-card'),
      child: ListTile(
        leading: const Icon(Icons.description_outlined, color: EmvColors.accent),
        title: const Text('Fiche du modèle'),
        subtitle: Text('Freins, suspension, électricité, entretien'
            '${issues > 0 ? ' · $issues point${issues > 1 ? 's' : ''} faible${issues > 1 ? 's' : ''}' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ModelSheetScreen(vehicle: vehicle, spec: spec))),
      ),
    );
  }
}

class ModelSheetScreen extends StatelessWidget {
  final Vehicle vehicle;
  final ModelSpec spec;

  const ModelSheetScreen({super.key, required this.vehicle, required this.spec});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final data = state.data;
    final issues = data.issuesFor(vehicle);
    String years() => spec.yearFrom == null
        ? ''
        : ' (${spec.yearFrom}${spec.yearTo == null ? '+' : '–${spec.yearTo}'})';
    return Scaffold(
      appBar: AppBar(title: Text('Fiche ${vehicle.title}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _Section('Modèle', [
            _Row('Génération', '${vehicle.model}${years()}'),
            if (spec.platform.isNotEmpty) _Row('Plateforme', spec.platform),
            if (spec.body.isNotEmpty) _Row('Carrosserie', spec.body.join(', ')),
          ]),
          _Section('Freins', [
            for (final e in spec.brakes.entries) _Row(_side(e.key), e.value),
          ]),
          _Section('Suspension et direction', [
            for (final e in spec.suspension.entries) _Row(_side(e.key), e.value),
            if (spec.steering.isNotEmpty) _Row('Direction', spec.steering),
          ]),
          _Section('Électricité', [
            for (final f in spec.fuseBoxes) _Row('Boîte à fusibles', f),
            if (spec.battery.isNotEmpty) _Row('Batterie', spec.battery),
            if (spec.obdPort.isNotEmpty) _Row('Prise OBD', spec.obdPort),
          ]),
          if (issues.isNotEmpty)
            _Section('Points faibles connus · ${vehicle.engine}', [
              for (final i in issues) _IssueTile(issue: i),
            ]),
          if (spec.maintenance.isNotEmpty)
            _Section('Entretien', [
              for (final m in spec.maintenance) _Row(m.item, m.note),
            ]),
          if (spec.tips.isNotEmpty)
            _Section('Conseils', [
              for (final t in spec.tips)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('•  $t'),
                ),
            ]),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(modelDisclaimer,
                key: Key('model-disclaimer'),
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  static String _side(String k) => switch (k) {
        'front' => 'Avant',
        'rear' => 'Arrière',
        _ => k,
      };
}

class _IssueTile extends StatelessWidget {
  final ModelIssue issue;

  const _IssueTile({required this.issue});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final data = state.data;
    final parts = [for (final p in issue.parts) if (data.part(p) != null) p];
    final dtcs = [for (final c in issue.dtc) ?data.dtc(c)];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(issue.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (issue.symptoms.isNotEmpty)
          Text(issue.symptoms, style: const TextStyle(color: Colors.white70)),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final p in parts)
            ActionChip(
              avatar: const Icon(Icons.build_outlined, size: 16),
              label: Text(data.part(p)!.part.name),
              onPressed: () => showPartSheet(context, p),
            ),
          for (final d in dtcs)
            ActionChip(
              avatar: const Icon(Icons.warning_amber, size: 16),
              label: Text(d.code),
              onPressed: () => Navigator.of(context).push(DtcScreen.route(d)),
            ),
          if (parts.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.view_in_ar, size: 16),
              label: const Text('Voir dans une vue'),
              onPressed: () {
                if (state.showPartsInView(parts)) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
            ),
        ]),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: EmvColors.accent, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...children,
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
              child: Text(label, style: const TextStyle(color: Colors.white60))),
          Expanded(child: Text(value)),
        ]),
      );
}
