import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../state.dart';
import '../theme.dart';

/// Retour sur une fiche : vote 👍/👎 conservé sur l'appareil, et signalement
/// d'erreur par e-mail pré-rempli (aucune collecte côté serveur).
class FeedbackBar extends StatelessWidget {
  /// `dtc`, `piece`, `vue` ou `guide`.
  final String type;
  final String id;
  final bool dense;

  const FeedbackBar(
      {super.key, required this.type, required this.id, this.dense = false});

  static Future<bool> Function(Uri uri) launcher =
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  String get _key => '$type:$id';

  static Uri mailtoUri(String type, String id, String? dataVersion) {
    final subject = 'EMV $type $id v${dataVersion ?? '?'}';
    final body = 'Fiche : $type $id\n'
        'Version des données : ${dataVersion ?? 'inconnue'}\n\n'
        'Décrivez l\'erreur constatée :\n';
    // Uri(queryParameters:) encode les espaces en « + », mal affichés par
    // certains clients mail : on encode en %20.
    return Uri.parse('mailto:$contactEmail'
        '?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}');
  }

  Future<void> _report(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = mailtoUri(type, id, await loadDataVersion());
    var opened = false;
    try {
      opened = await launcher(uri);
    } on Exception {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(SnackBar(
          content: Text('Aucune application mail : écrivez à $contactEmail')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final vote = state.feedbackVote(_key);
    Widget voteButton(int value, String emoji, String tooltip) => IconButton(
          key: Key('feedback-$value'),
          tooltip: tooltip,
          isSelected: vote == value,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: vote == value
                ? EmvColors.accent.withValues(alpha: 0.25)
                : null,
          ),
          icon: Text(emoji, style: const TextStyle(fontSize: 18)),
          onPressed: () =>
              state.setFeedbackVote(_key, vote == value ? 0 : value),
        );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 0 : 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        children: [
          Text(vote == 0 ? 'Cette fiche vous a aidé ?' : 'Merci pour votre avis',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          voteButton(1, '👍', 'Utile'),
          voteButton(-1, '👎', 'Pas utile'),
          const Text('·', style: TextStyle(color: Colors.white38)),
          TextButton(
            key: const Key('feedback-report'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => _report(context),
            child: const Text('Signaler une erreur'),
          ),
        ],
      ),
    );
  }
}
