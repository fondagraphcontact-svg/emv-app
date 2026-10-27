import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../insights/insights_section.dart';
import '../screens/faults.dart';
import '../state.dart';
import '../theme.dart';
import 'feedback_bar.dart';

Future<void> showPartSheet(BuildContext context, String slug) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartSheet(slug: slug),
    );

class PartSheet extends StatelessWidget {
  final String slug;

  const PartSheet({super.key, required this.slug});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;
    final loc = data.part(slug);
    final dtcs = data.dtcsForPart(slug, vehicle: state.current);
    final unknown = data.unknownDtcCodesForPart(slug);
    final openView = state.activeView;
    final inOpenView = openView?.containsPart(slug) ?? false;
    final hasView = data.bestViewFor([slug], vehicle: state.current) != null;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(loc?.part.name ?? slug,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Favori',
              icon: Icon(state.isFavorite(slug) ? Icons.star : Icons.star_border,
                  color: EmvColors.accent),
              onPressed: () => state.toggleFavorite(slug),
            ),
          ]),
          if (loc != null)
            Text(loc.breadcrumb,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white60)),
          if (loc == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Pièce absente de l\'arborescence.'),
            ),
          if (loc != null && loc.part.role.isNotEmpty)
            _Block(icon: Icons.build_outlined, title: 'Rôle', text: loc.part.role),
          if (loc != null && loc.part.wear.isNotEmpty)
            _Block(
                icon: Icons.warning_amber_rounded,
                title: 'Usure et symptômes',
                text: loc.part.wear),
          InsightsSection.part(slug),
          const SizedBox(height: 16),
          Text('Pannes liées', style: theme.textTheme.titleMedium),
          if (dtcs.isEmpty && unknown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun code défaut référencé.',
                  style: TextStyle(color: Colors.white60)),
            ),
          for (final d in dtcs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: DtcCodeBadge(dtc: d),
              title: Text(d.title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(DtcScreen.route(d)),
            ),
          if (unknown.isNotEmpty)
            Wrap(spacing: 6, children: [
              for (final c in unknown) Chip(label: Text(c)),
            ]),
          if (hasView && !inOpenView) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.view_in_ar),
              label: const Text('Voir dans la vue éclatée'),
              onPressed: () {
                Navigator.of(context).pop();
                state.showPartsInView([slug]);
              },
            ),
          ],
          const SizedBox(height: 16),
          FeedbackBar(type: 'piece', id: slug),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _Block({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: EmvColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(color: Colors.white70)),
            ]),
          ),
        ]),
      );
}
