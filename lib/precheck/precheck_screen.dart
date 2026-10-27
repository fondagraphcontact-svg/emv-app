import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../lights/light_assets.dart';
import '../lights/light_screen.dart';
import '../models.dart';
import '../screens/faults.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/part_sheet.dart';
import 'precheck_assets.dart';
import 'precheck_models.dart';
import 'precheck_store.dart';

const precheckCaution = 'Pré-contrôle indicatif, ne remplace pas le contrôle '
    'technique : seul le centre agréé constate les défaillances.';

void openPrecheck(BuildContext context, [Vehicle? vehicle]) {
  final v = vehicle ?? context.read<AppState>().current;
  if (v == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choisissez d\'abord un véhicule (onglet Véhicule).')));
    return;
  }
  Navigator.of(context).push(PrecheckScreen.route(v));
}

const _levelNames = {
  'mineure': 'Mineure',
  'majeure': 'Majeure',
  'critique': 'Critique',
};

Color precheckLevelColor(String level) =>
    EmvColors.severity(precheckLevelRank(level));

class PrecheckEntryCard extends StatelessWidget {
  const PrecheckEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final v = state.current;
    final store = PrecheckStore.of(state.prefs);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final marked = v == null ? const {} : store.statuses(v.id);
        final todo = marked.values.where((s) => s == PrecheckStatus.todo).length;
        return Card(
          key: const Key('precheck-entry'),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.verified_outlined,
                color: EmvColors.accent, size: 28),
            title: const Text('Pré-contrôle technique',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(v == null
                ? 'Préparez le passage au contrôle technique'
                : marked.isEmpty
                    ? 'Vérifiez vous-même avant le passage'
                    : '${marked.length} point(s) vérifié(s) · $todo à voir'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPrecheck(context),
          ),
        );
      },
    );
  }
}

class PrecheckScreen extends StatefulWidget {
  final Vehicle vehicle;

  const PrecheckScreen({super.key, required this.vehicle});

  static Route<void> route(Vehicle v) =>
      MaterialPageRoute(builder: (_) => PrecheckScreen(vehicle: v));

  @override
  State<PrecheckScreen> createState() => _PrecheckScreenState();
}

class _PrecheckScreenState extends State<PrecheckScreen> {
  // Voyants chargés aussi, pour nommer les liens « Voyant : … ».
  late final Future<PrecheckData> _future = loadPrecheck().then((d) async {
    try {
      await loadLights();
    } catch (_) {}
    return d;
  });

  Future<void> _confirmReset(PrecheckStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remettre à zéro ?'),
        content: const Text(
            'Toutes les cases de ce véhicule repasseront à « non vérifié ».'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              key: const Key('precheck-reset-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remettre à zéro')),
        ],
      ),
    );
    if (ok == true) await store.reset(widget.vehicle.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = PrecheckStore.of(context.read<AppState>().prefs);
    final v = widget.vehicle;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pré-contrôle technique'),
        actions: [
          IconButton(
            key: const Key('precheck-reset'),
            tooltip: 'Remettre à zéro',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _confirmReset(store),
          ),
        ],
      ),
      body: FutureBuilder<PrecheckData>(
        initialData: loadedPrecheck,
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return Center(
              child: snap.hasError
                  ? const Text('Pré-contrôle indisponible',
                      style: TextStyle(color: Colors.white60))
                  : const CircularProgressIndicator(),
            );
          }
          final points = data.pointsFor(v);
          return ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              PrecheckStatus status(String id) => store.status(v.id, id);
              return ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  ListTile(
                    leading: Icon(
                        v.kind == VehicleKind.moto
                            ? Icons.two_wheeler
                            : Icons.directions_car,
                        color: EmvColors.accent),
                    title: Text(v.title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(v.subtitle),
                  ),
                  PrecheckSummaryCard(
                    summary: PrecheckSummary.of(points, status),
                    levels: data.levels,
                  ),
                  for (final f in data.functions)
                    if (points.any((p) => p.function == f.id))
                      _FunctionSection(
                        function: f,
                        points: [
                          for (final p in points)
                            if (p.function == f.id) p
                        ],
                        status: status,
                        onSet: (id, s) => store.set(v.id, id, s),
                      ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(data.disclaimer,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class PrecheckSummaryCard extends StatelessWidget {
  final PrecheckSummary summary;
  final List<PrecheckLevel> levels;

  const PrecheckSummaryCard(
      {super.key, required this.summary, this.levels = const []});

  @override
  Widget build(BuildContext context) {
    final done = summary.total == 0
        ? 0.0
        : (summary.ok + summary.todo) / summary.total;
    return Card(
      key: const Key('precheck-summary'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${summary.ok + summary.todo}/${summary.total} points vérifiés',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: done,
            color: EmvColors.accent,
            backgroundColor: EmvColors.surfaceHigh,
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _Pill('OK : ${summary.ok}', EmvColors.severity(1),
                key: const Key('precheck-count-ok')),
            for (final l in precheckLevels)
              Tooltip(
                message: _levelText(l),
                child: _Pill(
                    'À voir ${_levelNames[l]!.toLowerCase()} : '
                    '${summary.todoByLevel[l] ?? 0}',
                    precheckLevelColor(l),
                    key: Key('precheck-count-$l')),
              ),
            _Pill('Non vérifié : ${summary.unchecked}', Colors.white38,
                key: const Key('precheck-count-unchecked')),
          ]),
          if ((summary.todoByLevel['critique'] ?? 0) > 0) ...[
            const SizedBox(height: 10),
            const Text(
                'Un point critique est à voir : faites-le réparer avant de rouler.',
                style: TextStyle(color: Color(0xFFE5484D))),
          ],
          const SizedBox(height: 10),
          const Text(precheckCaution,
              style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      ),
    );
  }

  String _levelText(String id) {
    for (final l in levels) {
      if (l.id == id) return l.text;
    }
    return '';
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );
}

class _FunctionSection extends StatelessWidget {
  final PrecheckFunction function;
  final List<PrecheckPoint> points;
  final PrecheckStatus Function(String id) status;
  final void Function(String id, PrecheckStatus s) onSet;

  const _FunctionSection({
    required this.function,
    required this.points,
    required this.status,
    required this.onSet,
  });

  @override
  Widget build(BuildContext context) {
    final checked = points.where((p) => status(p.id) != PrecheckStatus.unchecked);
    final todo = points.where((p) => status(p.id) == PrecheckStatus.todo).length;
    return Card(
      child: ExpansionTile(
        key: PageStorageKey('precheck-fn-${function.id}'),
        shape: const Border(),
        title: Text(function.name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          '${checked.length}/${points.length} vérifié(s)',
          if (todo > 0) '$todo à voir',
        ].join(' · ')),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          if (function.intro.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(function.intro,
                  style: const TextStyle(color: Colors.white60)),
            ),
          for (final p in points)
            PrecheckPointTile(
              point: p,
              status: status(p.id),
              onChanged: (s) => onSet(p.id, s),
            ),
        ],
      ),
    );
  }
}

class PrecheckPointTile extends StatelessWidget {
  final PrecheckPoint point;
  final PrecheckStatus status;
  final ValueChanged<PrecheckStatus> onChanged;

  const PrecheckPointTile({
    super.key,
    required this.point,
    required this.status,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final partName =
        point.part == null ? null : state.data.part(point.part!)?.part.name;
    final lightName = point.light == null
        ? null
        : loadedLights
            ?.where((l) => l.id == point.light)
            .map((l) => l.name)
            .firstOrNull;
    final color = precheckLevelColor(point.level);
    return Padding(
      key: Key('precheck-point-${point.id}'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(point.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Défaillance ${point.level}',
                style: TextStyle(color: color, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(point.check),
        const SizedBox(height: 4),
        Text('Conseil : ${point.advice}',
            style: const TextStyle(color: Colors.white70)),
        if (point.part != null || point.guide != null || point.light != null)
          Wrap(spacing: 8, children: [
            if (point.part != null)
              ActionChip(
                avatar: const Icon(Icons.build_outlined, size: 16),
                label: Text(partName ?? 'Pièce liée'),
                onPressed: () => showPartSheet(context, point.part!),
              ),
            if (point.guide != null)
              ActionChip(
                avatar: const Icon(Icons.checklist, size: 16),
                label: const Text('Guide pas-à-pas'),
                onPressed: () => openGuideById(context, point.guide!),
              ),
            if (point.light != null)
              ActionChip(
                avatar: const Icon(Icons.dashboard_outlined, size: 16),
                label: Text(lightName == null ? 'Voyant lié' : 'Voyant : $lightName'),
                onPressed: () => openLightById(context, point.light!),
              ),
          ]),
        const SizedBox(height: 6),
        SegmentedButton<PrecheckStatus>(
          key: Key('precheck-status-${point.id}'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: PrecheckStatus.ok,
                icon: Icon(Icons.check, size: 16),
                label: Text('OK')),
            ButtonSegment(
                value: PrecheckStatus.todo,
                icon: Icon(Icons.priority_high, size: 16),
                label: Text('À voir')),
            ButtonSegment(
                value: PrecheckStatus.unchecked,
                label: Text('Non vérifié')),
          ],
          selected: {status},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
        const Divider(height: 20),
      ]),
    );
  }
}
