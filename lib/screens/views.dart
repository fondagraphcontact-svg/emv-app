import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/engine_sheet.dart';
import '../widgets/exploded_view.dart';
import '../widgets/feedback_bar.dart';
import '../widgets/part_sheet.dart';

class ViewsScreen extends StatelessWidget {
  const ViewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final view = state.activeView;
    if (view != null) {
      return ViewDetail(
          key: ValueKey(view.id), view: view, highlighted: state.highlighted);
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vues'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Vues éclatées'),
            Tab(text: 'Arborescence'),
          ]),
        ),
        body: const TabBarView(children: [_ViewList(), _TreeBrowser()]),
      ),
    );
  }
}

class _ViewList extends StatelessWidget {
  const _ViewList();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;
    final vehicle = state.current;
    final family = vehicle == null ? null : data.family(vehicle.family);
    final engine = data.engineSpecFor(vehicle);
    final specific = data.specificViewsFor(vehicle);
    final model = data.modelViewsFor(vehicle);
    final generic = vehicle == null ? state.availableViews : data.familyViewsFor(vehicle);
    final groups = groupViewsByCategory(generic);
    final filtered = family != null && generic.length != data.genericViews.length;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (specific.isNotEmpty) ...[
          _Header('Vues spécifiques à ton moteur',
              key: const Key('views-specific'),
              action: engine == null
                  ? null
                  : TextButton.icon(
                      key: const Key('engine-sheet-button'),
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: Text('Fiche ${engine.code}'),
                      onPressed: () => showEngineSheet(context, engine),
                    )),
          for (final v in specific) _ViewTile(view: v),
        ],
        if (model.isNotEmpty) ...[
          _Header('Vues adaptées à ton modèle', key: const Key('views-model')),
          for (final v in model) _ViewTile(view: v),
        ],
        _Header(
          specific.isEmpty && model.isEmpty
              ? (filtered
                  ? '${vehicle!.title} · ${family.name}'
                  : vehicle == null
                      ? 'Toutes les vues (aucun véhicule choisi)'
                      : 'Toutes les vues (famille sans vue dédiée)')
              : 'Vues génériques de la famille${family == null ? '' : ' · ${family.name}'}',
          key: const Key('views-generic'),
        ),
        if (generic.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Aucune vue disponible')),
          ),
        for (final (category, views) in groups)
          ExpansionTile(
            key: PageStorageKey('views-cat-$category'),
            initiallyExpanded: groups.length == 1,
            title: Text(category,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${views.length} vue${views.length > 1 ? 's' : ''}'),
            children: [for (final v in views) _ViewTile(view: v)],
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  final Widget? action;

  const _Header(this.text, {super.key, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(children: [
          Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white60))),
          ?action,
        ]),
      );
}

class _ViewTile extends StatelessWidget {
  final ExplodedView view;

  const _ViewTile({required this.view});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Card(
      child: ListTile(
        leading: ViewThumbnail(view: view, size: 56),
        title: Text(view.name),
        subtitle: Text(view.specific
            ? '${view.parts.length} pièces · schéma pédagogique EMV'
            : '${view.parts.length} pièces'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => state.openView(view.id),
      ),
    );
  }
}

class _TreeBrowser extends StatefulWidget {
  const _TreeBrowser();

  @override
  State<_TreeBrowser> createState() => _TreeBrowserState();
}

class _TreeBrowserState extends State<_TreeBrowser> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;
    final searching = normalize(_query).isNotEmpty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Rechercher une pièce',
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      Expanded(
        child: searching
            ? ListView(children: [
                for (final p in data.searchParts(_query, vehicle: state.current))
                  _PartTile(part: p, subtitle: data.part(p.slug)?.breadcrumb),
              ])
            : ListView(children: [
                for (final s in data.treeFor(state.current?.kind, vehicle: state.current))
                  ExpansionTile(
                    key: PageStorageKey(s.slug),
                    title: Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    children: [
                      for (final g in s.children)
                        ExpansionTile(
                          key: PageStorageKey('${s.slug}/${g.slug}'),
                          tilePadding: const EdgeInsets.only(left: 32, right: 16),
                          title: Text(g.name),
                          subtitle: Text('${g.parts.length} pièces'),
                          children: [
                            for (final p in g.parts) _PartTile(part: p),
                          ],
                        ),
                    ],
                  ),
              ]),
      ),
    ]);
  }
}

class _PartTile extends StatelessWidget {
  final TreePart part;
  final String? subtitle;

  const _PartTile({required this.part, this.subtitle});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.only(left: 48, right: 16),
        dense: true,
        title: Text(part.name),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: part.dtc.isEmpty
            ? null
            : Text('${part.dtc.length} code${part.dtc.length > 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.white54)),
        onTap: () => showPartSheet(context, part.slug),
      );
}

class ViewDetail extends StatefulWidget {
  final ExplodedView view;
  final Set<String> highlighted;

  const ViewDetail({super.key, required this.view, this.highlighted = const {}});

  @override
  State<ViewDetail> createState() => _ViewDetailState();
}

class _ViewDetailState extends State<ViewDetail> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.highlighted.length == 1) _selected = widget.highlighted.first;
  }

  void _select(String? slug, {bool openSheet = true}) {
    setState(() => _selected = slug);
    if (slug != null && openSheet) showPartSheet(context, slug);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final view = widget.view;
    final selectedPart = _selected == null
        ? null
        : view.parts.where((p) => p.slug == _selected).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back),
          onPressed: state.closeView,
        ),
        title: Text(view.name, overflow: TextOverflow.ellipsis),
      ),
      body: Column(children: [
        Expanded(
          child: Container(
            color: EmvColors.background,
            child: ExplodedViewWidget(
              view: view,
              selected: _selected,
              highlighted: widget.highlighted,
              onPartTap: _select,
            ),
          ),
        ),
        Container(
          color: EmvColors.surface,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              selectedPart?.label ??
                  'Touchez une pièce · pincez pour zoomer',
              style: TextStyle(
                color: selectedPart == null ? Colors.white60 : EmvColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final p in view.parts)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(p.label.isEmpty ? p.slug : p.label),
                        selected: p.slug == _selected,
                        side: widget.highlighted.contains(p.slug)
                            ? const BorderSide(color: EmvColors.accent)
                            : null,
                        onSelected: (on) => _select(on ? p.slug : null),
                      ),
                    ),
                ],
              ),
            ),
            FeedbackBar(type: 'vue', id: view.id, dense: true),
          ]),
        ),
      ]),
    );
  }
}
