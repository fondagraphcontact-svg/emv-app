import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../screens/model_sheet.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/engine_sheet.dart';
import 'insight_engine.dart';

const insightsTitle = 'Fréquemment observé sur votre moteur';

const insightsCaution =
    'Pistes fréquemment observées d\'après les fiches EMV de votre moteur et '
    'de votre modèle : elles ne confirment pas la cause, d\'autres pannes '
    'restent possibles. Seul un diagnostic permet de conclure.';

class InsightsSection extends StatelessWidget {
  final Dtc? dtc;
  final String? partSlug;

  const InsightsSection.dtc(Dtc this.dtc, {super.key}) : partSlug = null;

  const InsightsSection.part(String this.partSlug, {super.key}) : dtc = null;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final vehicle = state.current;
    final engine = InsightEngine.of(state.data);
    if (vehicle == null) {
      return dtc == null ? const SizedBox.shrink() : const _ChooseVehicle();
    }
    final items = dtc != null
        ? engine.forDtc(dtc!, vehicle)
        : engine.forPart(partSlug!, vehicle);
    if (items.isEmpty) {
      if (dtc == null) return const SizedBox.shrink();
      return const _Frame(children: [
        Text(
          'Aucun point fréquemment observé en lien avec ce code dans les '
          'fiches EMV de votre moteur et de votre modèle.',
          key: Key('insights-empty'),
          style: TextStyle(color: Colors.white60),
        ),
      ]);
    }
    return _Frame(children: [
      for (final i in items) _InsightTile(insight: i, vehicle: vehicle),
      const SizedBox(height: 6),
      const Text(insightsCaution,
          style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }
}

class _Frame extends StatelessWidget {
  final List<Widget> children;

  const _Frame({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('insights-section'),
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: EmvColors.surface,
          border: Border.all(color: EmvColors.grid),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.insights_outlined, color: EmvColors.accent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(insightsTitle,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 6),
          ...children,
        ]),
      );
}

class _InsightTile extends StatelessWidget {
  final Insight insight;
  final Vehicle vehicle;

  const _InsightTile({required this.insight, required this.vehicle});

  void _open(BuildContext context) {
    final engine = insight.engine;
    final model = insight.model;
    if (engine != null) {
      showEngineSheet(context, engine);
    } else if (model != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ModelSheetScreen(vehicle: vehicle, spec: model)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = insight;
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
              i.source == InsightSource.engine
                  ? Icons.precision_manufacturing_outlined
                  : Icons.description_outlined,
              size: 18,
              color: EmvColors.guide),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.text, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (i.detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(i.detail,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              const SizedBox(height: 2),
              Text(
                  [
                    i.sourceLabel,
                    if (i.topics.isNotEmpty) 'lien : ${i.topics.join(', ')}',
                  ].join(' · '),
                  style: const TextStyle(color: EmvColors.accent, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
        ]),
      ),
    );
  }
}

class _ChooseVehicle extends StatelessWidget {
  const _ChooseVehicle();

  @override
  Widget build(BuildContext context) => _Frame(children: [
        const Text(
          'Choisissez votre véhicule pour voir les pannes fréquemment '
          'observées sur votre moteur et votre modèle en lien avec ce code.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('insights-choose-vehicle'),
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('Choisir mon véhicule'),
          onPressed: () {
            context.read<AppState>().selectTab(AppTab.vehicle);
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      ]);
}
