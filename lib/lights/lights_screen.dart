import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import 'light_assets.dart';
import 'light_icon.dart';
import 'light_models.dart';
import 'light_screen.dart';

class LightsEntryCard extends StatelessWidget {
  const LightsEntryCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('lights-entry'),
        child: ListTile(
          leading: const Icon(Icons.dashboard_outlined,
              color: EmvColors.accent, size: 32),
          title: const Text('Un voyant est allumé ?',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Identifie-le : sens, urgence, que faire'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(LightsScreen.route()),
        ),
      );
}

class LightsScreen extends StatefulWidget {
  const LightsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const LightsScreen());

  @override
  State<LightsScreen> createState() => _LightsScreenState();
}

class _LightsScreenState extends State<LightsScreen> {
  late final Future<List<DashboardLight>> _future = loadLights();
  String _query = '';
  String? _color;
  String? _category;
  bool _vehicleOnly = true;

  List<DashboardLight> _filter(List<DashboardLight> all, AppState state) {
    final v = _vehicleOnly ? state.current : null;
    final out = [
      for (final l in all)
        if ((_color == null || l.color == _color) &&
            (_category == null || l.category == _category) &&
            (v == null || l.appliesTo(v)) &&
            l.matches(_query))
          l,
    ];
    // Stable: most urgent first, data order otherwise.
    final index = {for (var i = 0; i < all.length; i++) all[i].id: i};
    out.sort((a, b) => b.urgency != a.urgency
        ? b.urgency.compareTo(a.urgency)
        : index[a.id]!.compareTo(index[b.id]!));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Voyants du tableau de bord')),
      body: FutureBuilder<List<DashboardLight>>(
        initialData: loadedLights,
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Voyants indisponibles : ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lights = _filter(snap.data!, state);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: TextField(
                key: const Key('lights-search'),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Forme ou mot (huile, batterie, tortue…)',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            _chips(state),
            Expanded(
              child: lights.isEmpty
                  ? const Center(
                      child: Text('Aucun voyant ne correspond',
                          style: TextStyle(color: Colors.white60)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 170,
                        mainAxisExtent: 150,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: lights.length,
                      itemBuilder: (context, i) => _LightTile(lights[i]),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _chips(AppState state) {
    final vehicle = state.current;
    Widget chip(String key, String label, bool selected, VoidCallback onTap,
            {Color? dot}) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            key: Key(key),
            avatar: dot == null
                ? null
                : Icon(Icons.circle, size: 14, color: dot),
            label: Text(label),
            selected: selected,
            showCheckmark: dot == null,
            onSelected: (_) => onTap(),
          ),
        );
    return SizedBox(
      height: 96,
      child: Column(children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              if (vehicle != null)
                chip('lights-vehicle', 'Mon véhicule', _vehicleOnly,
                    () => setState(() => _vehicleOnly = !_vehicleOnly)),
              for (final e in lightColorNames.entries)
                chip('lights-color-${e.key}', e.value, _color == e.key,
                    () => setState(
                        () => _color = _color == e.key ? null : e.key),
                    dot: lightColor(e.key)),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in lightCategories.entries)
                chip('lights-cat-${e.key}', e.value, _category == e.key,
                    () => setState(() =>
                        _category = _category == e.key ? null : e.key)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _LightTile extends StatelessWidget {
  final DashboardLight light;

  const _LightTile(this.light);

  @override
  Widget build(BuildContext context) {
    final u = UrgencyBadge.colorFor(light.urgency);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: Key('light-${light.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(LightScreen.route(light)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            LightIcon(light: light, size: 60),
            const SizedBox(height: 6),
            Expanded(
              child: Text(light.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.circle, size: 9, color: u),
              const SizedBox(width: 4),
              Flexible(
                child: Text(urgencyLabels[light.urgency]!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: u)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
