import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/feedback_bar.dart';
import 'guide_models.dart';

enum GuideAnswer { yes, no, unknown }

extension on GuideAnswer {
  String get label => switch (this) {
        GuideAnswer.yes => 'Oui',
        GuideAnswer.no => 'Non',
        GuideAnswer.unknown => 'Je ne sais pas',
      };
}

typedef GuideLink = void Function(String id);

/// Déroule un guide : consignes de sécurité, une question par écran, puis
/// le résultat. La navigation hors du guide passe par les callbacks ; un
/// callback absent masque les boutons correspondants.
class GuideRunnerScreen extends StatefulWidget {
  final Guide guide;
  final GuideLink? onOpenView;
  final GuideLink? onOpenPart;
  final GuideLink? onOpenDtc;

  const GuideRunnerScreen({
    super.key,
    required this.guide,
    this.onOpenView,
    this.onOpenPart,
    this.onOpenDtc,
  });

  static Route<void> route(Guide guide,
          {GuideLink? onOpenView, GuideLink? onOpenPart, GuideLink? onOpenDtc}) =>
      MaterialPageRoute(
          builder: (_) => GuideRunnerScreen(
              guide: guide,
              onOpenView: onOpenView,
              onOpenPart: onOpenPart,
              onOpenDtc: onOpenDtc));

  @override
  State<GuideRunnerScreen> createState() => _GuideRunnerScreenState();
}

class _GuideRunnerScreenState extends State<GuideRunnerScreen> {
  bool _started = false;
  final List<(GuideStep, GuideAnswer)> _path = [];
  late String _current = widget.guide.first?.id ?? '';

  Guide get guide => widget.guide;

  void _answer(GuideStep step, GuideAnswer a) => setState(() {
        _path.add((step, a));
        _current = switch (a) {
          GuideAnswer.yes => step.yes,
          GuideAnswer.no => step.no,
          GuideAnswer.unknown => step.unknownTarget,
        };
      });

  void _backTo(int index) => setState(() {
        _current = _path[index].$1.id;
        _path.removeRange(index, _path.length);
      });

  void _restart() => setState(() {
        _path.clear();
        _current = guide.first?.id ?? '';
      });

  @override
  Widget build(BuildContext context) {
    final step = guide.step(_current);
    final result = guide.result(_current);
    final Widget body;
    if (!_started) {
      body = _intro(context);
    } else if (step != null) {
      body = _question(context, step);
    } else if (result != null) {
      body = _result(context, result);
    } else {
      body = Center(child: Text('Étape introuvable : $_current'));
    }
    return PopScope(
      canPop: !_started || _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backTo(_path.length - 1);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(guide.title, maxLines: 2)),
        body: body,
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Expanded(
        child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        if (guide.summary.isNotEmpty) Text(guide.summary),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          Chip(
            avatar: Icon(Icons.circle,
                size: 12, color: EmvColors.severity(guide.difficulty)),
            label: Text(
                'Difficulté : ${const {1: 'Facile', 2: 'Moyenne', 3: 'Avancée'}[guide.difficulty.clamp(1, 3)]}'),
          ),
          if (guide.time.isNotEmpty)
            Chip(
                avatar: const Icon(Icons.schedule, size: 16),
                label: Text(guide.time)),
          Chip(label: Text('${guide.steps.length} étapes max')),
        ]),
        if (guide.tools.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Outillage', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(guide.tools.join(' · ')),
        ],
        _Bullets('Sécurité', guide.safety, Icons.health_and_safety_outlined,
            EmvColors.accent),
        _StopCard(guide.stopIf),
        const SizedBox(height: 16),
        const _Disclaimer(),
      ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('guide-start'),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Commencer le diagnostic'),
              onPressed: guide.first == null
                  ? null
                  : () => setState(() => _started = true),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _breadcrumb() {
    if (_path.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        key: const Key('guide-breadcrumb'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _path.length,
        separatorBuilder: (_, _) =>
            const Icon(Icons.chevron_right, size: 16, color: Colors.white38),
        itemBuilder: (context, i) {
          final (s, a) = _path[i];
          return Tooltip(
            message: '${s.question}\n→ ${a.label} (toucher pour revenir ici)',
            child: ActionChip(
              key: Key('guide-crumb-$i'),
              visualDensity: VisualDensity.compact,
              label: Text('${i + 1}. ${a.label}'),
              onPressed: () => _backTo(i),
            ),
          );
        },
      ),
    );
  }

  Widget _question(BuildContext context, GuideStep step) {
    final theme = Theme.of(context);
    final names = context.read<AppState>().data;
    return Column(children: [
      _breadcrumb(),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Text('Question ${_path.length + 1}',
                style: const TextStyle(color: EmvColors.accent)),
            const SizedBox(height: 6),
            Text(step.question,
                key: const Key('guide-question'),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (step.check.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.search, color: EmvColors.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Comment vérifier',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(step.check),
                              ]),
                        ),
                      ]),
                ),
              ),
            if (widget.onOpenPart != null && step.parts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final slug in step.parts)
                  ActionChip(
                    avatar: const Icon(Icons.settings_outlined, size: 16),
                    label: Text(names.part(slug)?.part.name ?? slug),
                    onPressed: () => widget.onOpenPart!(slug),
                  ),
              ]),
            ],
            if (guide.stopIf.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton.icon(
                  key: const Key('guide-stop-reminder'),
                  icon: const Icon(Icons.warning_amber, color: Colors.redAccent),
                  label: const Text('Quand faut-il arrêter ?'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: _StopCard(guide.stopIf),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      key: const Key('guide-yes'),
                      onPressed: () => _answer(step, GuideAnswer.yes),
                      child: const Text('Oui'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonal(
                      key: const Key('guide-no'),
                      onPressed: () => _answer(step, GuideAnswer.no),
                      child: const Text('Non'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('guide-unknown'),
                  onPressed: () => _answer(step, GuideAnswer.unknown),
                  child: const Text('Je ne sais pas'),
                ),
                if (_path.isNotEmpty)
                  TextButton.icon(
                    key: const Key('guide-back'),
                    icon: const Icon(Icons.undo),
                    label: const Text('Question précédente'),
                    onPressed: () => _backTo(_path.length - 1),
                  ),
              ]),
        ),
      ),
    ]);
  }

  Widget _result(BuildContext context, GuideResult r) {
    final theme = Theme.of(context);
    final data = context.read<AppState>().data;
    final views = [
      for (final id in r.views)
        if (data.view(id) != null) id
    ];
    return Column(children: [
      _breadcrumb(),
      Expanded(
        child: ListView(
          key: const Key('guide-result'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text('Piste la plus probable',
                style: TextStyle(color: EmvColors.accent)),
            const SizedBox(height: 6),
            Text(r.title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(r.text),
            if (r.pro)
              Card(
                margin: const EdgeInsets.only(top: 16),
                color: EmvColors.severity(3).withValues(alpha: 0.15),
                child: const ListTile(
                  leading: Icon(Icons.engineering, color: Colors.redAccent),
                  title: Text('Intervention d\'un professionnel conseillée'),
                  subtitle: Text(
                      'Outillage spécifique ou risque pour la sécurité : faites contrôler par un garage.'),
                ),
              ),
            if (widget.onOpenPart != null && r.parts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Pièces à contrôler', style: theme.textTheme.titleMedium),
              for (final slug in r.parts)
                ListTile(
                  key: Key('guide-part-$slug'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(data.part(slug)?.part.name ?? slug),
                  subtitle: data.part(slug) == null
                      ? null
                      : Text(data.part(slug)!.breadcrumb),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpenPart!(slug),
                ),
            ],
            if (widget.onOpenView != null && views.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final id in views)
                  OutlinedButton.icon(
                    key: Key('guide-view-$id'),
                    icon: const Icon(Icons.view_in_ar),
                    label: Text(data.view(id)!.name),
                    onPressed: () => widget.onOpenView!(id),
                  ),
              ]),
            ],
            if (widget.onOpenDtc != null && r.dtc.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Codes défaut liés', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final code in r.dtc)
                  ActionChip(
                    key: Key('guide-dtc-$code'),
                    avatar: const Icon(Icons.error_outline, size: 16),
                    label: Text(code),
                    tooltip: data.dtc(code)?.title,
                    onPressed: () => widget.onOpenDtc!(code),
                  ),
              ]),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('guide-back'),
                  icon: const Icon(Icons.undo),
                  label: const Text('Corriger'),
                  onPressed: _path.isEmpty
                      ? null
                      : () => _backTo(_path.length - 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('guide-restart'),
                  icon: const Icon(Icons.replay),
                  label: const Text('Recommencer'),
                  onPressed: _restart,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            const _Disclaimer(),
            FeedbackBar(type: 'guide', id: guide.id),
          ],
        ),
      ),
    ]);
  }
}

class _Bullets extends StatelessWidget {
  final String title;
  final List<String> items;
  final IconData icon;
  final Color color;

  const _Bullets(this.title, this.items, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ]),
        const SizedBox(height: 4),
        for (final s in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 20, child: Text('•', style: TextStyle(color: color))),
              Expanded(child: Text(s)),
            ]),
          ),
      ]),
    );
  }
}

class _StopCard extends StatelessWidget {
  final List<String> items;

  const _StopCard(this.items);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('guide-stopif'),
      margin: const EdgeInsets.only(top: 16),
      color: EmvColors.severity(3).withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _Bullets('Arrêtez tout et faites appel à un pro si…', items,
            Icons.dangerous_outlined, Colors.redAccent),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => const Text(
        'Guide générique : il oriente le diagnostic mais ne remplace pas '
        'l\'avis d\'un professionnel ni la documentation du constructeur.',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      );
}
