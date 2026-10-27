import 'package:flutter/material.dart';

import '../data.dart';
import '../models.dart';
import '../theme.dart';
import 'guide_assets.dart';
import 'guide_models.dart';

/// Liste des guides, filtrée sur le véhicule courant (bascule « Tous »).
/// Sans Scaffold : s'insère dans un onglet ou une page existante.
class GuideListScreen extends StatefulWidget {
  final Vehicle? vehicle;
  final void Function(Guide guide) onOpen;

  /// Pour les tests ; sinon `assets/data/guides.json` chargé une fois.
  final Future<List<Guide>>? guides;

  const GuideListScreen(
      {super.key, this.vehicle, required this.onOpen, this.guides});

  @override
  State<GuideListScreen> createState() => _GuideListScreenState();
}

class _GuideListScreenState extends State<GuideListScreen> {
  late final Future<List<Guide>> _guides = widget.guides ?? loadGuides();
  bool _all = false;
  String _query = '';

  List<Guide> _filter(List<Guide> guides) {
    final tokens = normalize(_query).split(' ').where((t) => t.isNotEmpty);
    return [
      for (final g in guides)
        if ((_all || g.appliesTo(widget.vehicle)) &&
            tokens.every(normalize('${g.title} ${g.summary}').contains))
          g
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Guide>>(
      future: _guides,
      initialData: widget.guides == null ? loadedGuides : null,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Guides indisponibles :\n${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final shown = _filter(snap.data!);
        final hidden = snap.data!.length -
            snap.data!.where((g) => g.appliesTo(widget.vehicle)).length;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              key: const Key('guide-search'),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Symptôme (démarre pas, fumée, frein…)',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (widget.vehicle != null && hidden > 0)
            SwitchListTile(
              key: const Key('guide-show-all'),
              dense: true,
              title: Text(_all
                  ? 'Tous les guides'
                  : 'Guides adaptés à ${widget.vehicle!.make} ${widget.vehicle!.model}'),
              subtitle: Text('$hidden guide(s) non adapté(s) masqué(s)'),
              value: _all,
              onChanged: (v) => setState(() => _all = v),
            ),
          Expanded(
            child: shown.isEmpty
                ? const Center(
                    child: Text('Aucun guide trouvé',
                        style: TextStyle(color: Colors.white60)))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final g = shown[i];
                      return ListTile(
                        key: Key('guide-${g.id}'),
                        leading: Icon(
                            g.kind == VehicleKind.moto
                                ? Icons.two_wheeler
                                : Icons.checklist,
                            color: EmvColors.severity(g.difficulty)),
                        title: Text(g.title),
                        subtitle: Text(
                            '${guideCategoryLabel(g.category)} · ${g.steps.length} étapes · ${g.time}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onOpen(g),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }
}
