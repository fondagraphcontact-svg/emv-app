import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../guides/guide_assets.dart';
import '../guides/guide_models.dart';
import '../screens/faults.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/feedback_bar.dart';
import '../widgets/part_sheet.dart';
import 'light_assets.dart';
import 'light_icon.dart';
import 'light_models.dart';

Future<void> openLightById(BuildContext context, String id) async {
  final lights = await loadLights();
  if (!context.mounted) return;
  for (final l in lights) {
    if (l.id == id) {
      Navigator.of(context).push(LightScreen.route(l));
      return;
    }
  }
}

class LightScreen extends StatelessWidget {
  final DashboardLight light;

  const LightScreen({super.key, required this.light});

  static Route<void> route(DashboardLight light) =>
      MaterialPageRoute(builder: (_) => LightScreen(light: light));

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final data = state.data;
    final theme = Theme.of(context);
    final dtcs = [
      for (final c in light.dtc) ?data.dtc(c),
    ];
    final parts = [
      for (final s in light.parts)
        if (data.part(s) != null) s,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Voyant')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(children: [
            LightIcon(light: light, size: 96),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(light.name,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(Icons.circle,
                            size: 12, color: lightColor(light.color)),
                        label: Text(lightColorNames[light.color] ?? ''),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(lightCategories[light.category] ?? ''),
                      ),
                    ]),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: UrgencyBadge(urgency: light.urgency)),
          _Section('Ce que ça signifie', [light.meaning], plain: true),
          _Section('Que faire maintenant', light.now, numbered: true),
          _Section('Causes fréquentes', light.causes),
          if (dtcs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Codes défaut liés', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in dtcs)
                InkWell(
                  key: Key('light-dtc-${d.code}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).push(DtcScreen.route(d)),
                  child: DtcCodeBadge(dtc: d),
                ),
            ]),
          ],
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Pièces liées', style: theme.textTheme.titleMedium),
            for (final slug in parts)
              ListTile(
                key: Key('light-part-$slug'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_outlined),
                title: Text(data.part(slug)!.part.name),
                subtitle: Text(data.part(slug)!.breadcrumb),
                onTap: () => showPartSheet(context, slug),
              ),
          ],
          if (light.guides.isNotEmpty) _GuideLinks(light.guides),
          const SizedBox(height: 24),
          const Text(
            'Pictogramme EMV schématique : la forme et la couleur exactes varient selon le véhicule, la notice fait foi. '
            'Information générique : ne remplace pas le diagnostic d\'un professionnel.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          FeedbackBar(type: 'voyant', id: light.id),
        ],
      ),
    );
  }
}

class _GuideLinks extends StatelessWidget {
  final List<String> ids;

  const _GuideLinks(this.ids);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Guide>>(
      initialData: loadedGuides,
      future: loadGuides(),
      builder: (context, snap) {
        final byId = {for (final g in snap.data ?? const <Guide>[]) g.id: g};
        final guides = [
          for (final id in ids) ?byId[id],
        ];
        if (guides.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('Guides pas-à-pas',
                style: Theme.of(context).textTheme.titleMedium),
            for (final g in guides)
              ListTile(
                key: Key('light-guide-${g.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.checklist, color: EmvColors.accent),
                title: Text(g.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openGuide(context, g),
              ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> items;
  final bool numbered;
  final bool plain;

  const _Section(this.title, this.items,
      {this.numbered = false, this.plain = false});

  @override
  Widget build(BuildContext context) {
    final shown = items.where((s) => s.trim().isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        for (var i = 0; i < shown.length; i++)
          plain
              ? Text(shown[i])
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(numbered ? '${i + 1}.' : '•',
                              style: const TextStyle(color: EmvColors.accent)),
                        ),
                        Expanded(child: Text(shown[i])),
                      ]),
                ),
      ]),
    );
  }
}
