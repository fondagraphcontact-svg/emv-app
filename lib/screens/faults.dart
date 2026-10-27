import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../codelog/code_log_screen.dart';
import '../guides/guide_assets.dart';
import '../guides/guide_list_screen.dart';
import '../guides/guide_models.dart';
import '../guides/guide_runner_screen.dart';
import '../insights/insights_section.dart';
import '../insights/urgency.dart';
import '../lights/lights_screen.dart';
import '../models.dart';
import '../precheck/precheck_screen.dart';
import '../report/report_screen.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/feedback_bar.dart';
import '../widgets/part_sheet.dart';

class FaultsScreen extends StatefulWidget {
  const FaultsScreen({super.key});

  @override
  State<FaultsScreen> createState() => _FaultsScreenState();
}

class _FaultsScreenState extends State<FaultsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final results = state.data.searchDtc(_query, vehicle: state.current);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Diagnostic'),
          bottom: const TabBar(tabs: [
            Tab(key: Key('tab-codes'), text: 'Codes'),
            Tab(key: Key('tab-guides'), text: 'Guides'),
          ]),
        ),
        body: Column(children: [
          const LightsEntryCard(),
          const PrecheckEntryCard(),
          Expanded(
            child: TabBarView(children: [
              _codes(results),
              GuideListScreen(
                vehicle: state.current,
                onOpen: (g) => openGuide(context, g),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _codes(List<Dtc> results) {
    return Column(children: [
        const CodeLogTile(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            key: const Key('dtc-search'),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Code (P0301) ou mot (raté, catalyseur…)',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? const Center(
                  child: Text('Aucun code trouvé',
                      style: TextStyle(color: Colors.white60)))
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final d = results[i];
                    return ListTile(
                      leading: DtcCodeBadge(dtc: d),
                      title: Text(d.title.isEmpty ? d.code : d.title),
                      subtitle: d.system.isEmpty
                          ? null
                          : Text(systemLabel(d.system)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).push(DtcScreen.route(d)),
                    );
                  },
                ),
        ),
      ]);
  }
}

void openGuide(BuildContext context, Guide guide) {
  final state = context.read<AppState>();
  final navigator = Navigator.of(context);
  navigator.push(GuideRunnerScreen.route(
    guide,
    onOpenView: (id) {
      state.openView(id);
      state.selectTab(AppTab.views);
      navigator.popUntil((r) => r.isFirst);
    },
    onOpenPart: (slug) => showPartSheet(context, slug),
    onOpenDtc: (code) {
      final dtc = state.data.dtc(code);
      if (dtc != null) navigator.push(DtcScreen.route(dtc));
    },
  ));
}

Future<void> openGuideById(BuildContext context, String id) async {
  final guides = await loadGuides();
  if (!context.mounted) return;
  for (final g in guides) {
    if (g.id == id) return openGuide(context, g);
  }
}

class DtcCodeBadge extends StatelessWidget {
  final Dtc dtc;

  const DtcCodeBadge({super.key, required this.dtc});

  @override
  Widget build(BuildContext context) {
    final color = EmvColors.severity(dtc.severity);
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(dtc.code,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

class DtcScreen extends StatefulWidget {
  final Dtc dtc;

  const DtcScreen({super.key, required this.dtc});

  static Route<void> route(Dtc dtc) =>
      MaterialPageRoute(builder: (_) => DtcScreen(dtc: dtc));

  @override
  State<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends State<DtcScreen> {
  Dtc get dtc => widget.dtc;

  @override
  void initState() {
    super.initState();
    // Après la frame : l'historique notifie des écrans déjà construits.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().recordDtcViewed(dtc.code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final data = state.data;
    final theme = Theme.of(context);
    final parts = data.partsFor(dtc.parts, state.current);
    final hasView = data.bestViewFor(parts, vehicle: state.current) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(dtc.code),
        actions: [
          IconButton(
            key: const Key('codelog-add-appbar'),
            tooltip: 'Ajouter à mes codes',
            icon: const Icon(Icons.playlist_add),
            onPressed: () => addCodeToLog(context, dtc.code),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(dtc.title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          UrgencyBadge(dtc: dtc),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (dtc.system.isNotEmpty)
              Chip(label: Text(systemLabel(dtc.system))),
            for (final f in dtc.fuel) Chip(label: Text(fuelLabel(f))),
          ]),
          _Section('Symptômes', dtc.symptoms),
          _Section('Causes probables', dtc.causes),
          InsightsSection.dtc(dtc),
          _Section('Ordre de diagnostic', dtc.diagnostic, numbered: true),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Pièces concernées', style: theme.textTheme.titleMedium),
            for (final slug in parts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_outlined),
                title: Text(data.part(slug)?.part.name ?? slug),
                subtitle: data.part(slug) == null
                    ? null
                    : Text(data.part(slug)!.breadcrumb),
                onTap: () => showPartSheet(context, slug),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('show-parts'),
              icon: const Icon(Icons.view_in_ar),
              label: const Text('Voir les pièces'),
              onPressed: hasView
                  ? () {
                      if (state.showPartsInView(parts)) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    }
                  : null,
            ),
            if (!hasView)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Aucune vue éclatée ne contient encore ces pièces.',
                    style: TextStyle(color: Colors.white60)),
              ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('prepare-report'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Préparer pour le garage'),
            onPressed: () => openReport(context, dtc: dtc),
          ),
          const SizedBox(height: 8),
          AddToCodeLogButton(code: dtc.code),
          const SizedBox(height: 24),
          const Text(
            'Information générique : ne remplace pas le diagnostic d\'un professionnel.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          FeedbackBar(type: 'dtc', id: dtc.code),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> items;
  final bool numbered;

  const _Section(this.title, this.items, {this.numbered = false});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 24,
                child: Text(numbered ? '${i + 1}.' : '•',
                    style: const TextStyle(color: EmvColors.accent)),
              ),
              Expanded(child: Text(items[i])),
            ]),
          ),
      ]),
    );
  }
}
