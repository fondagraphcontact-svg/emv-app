import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class Urgency {
  final int level;
  final String label;
  final String advice;
  final IconData icon;

  const Urgency._(this.level, this.label, this.advice, this.icon);

  Color get color => EmvColors.severity(level);

  static const caution =
      'Indication générale EMV : elle ne tient pas compte de l\'état réel de '
      'votre véhicule. Au moindre doute, demandez l\'avis d\'un professionnel.';

  static const _levels = {
    1: Urgency._(
        1,
        'Peut rouler, à surveiller',
        'En général, le véhicule peut continuer à rouler prudemment. Faites '
            'contrôler ce défaut à la prochaine occasion et surveillez '
            'l\'apparition de nouveaux symptômes.',
        Icons.visibility_outlined),
    2: Urgency._(
        2,
        'Garage sous peu',
        'Prenez rendez-vous rapidement. En attendant, limitez les trajets et '
            'évitez de solliciter le moteur ; arrêtez-vous si un voyant rouge '
            's\'allume ou si le comportement change.',
        Icons.build_circle_outlined),
    3: Urgency._(
        3,
        'Arrêt conseillé',
        'Arrêtez-vous dès que possible dans un endroit sûr et coupez le moteur. '
            'Continuer à rouler peut aggraver les dégâts ou présenter un risque : '
            'faites appel à un professionnel.',
        Icons.report_outlined),
  };

  factory Urgency.of(int severity) => _levels[severity.clamp(1, 3)]!;
}

class UrgencyBadge extends StatelessWidget {
  final Dtc dtc;
  final bool compact;

  const UrgencyBadge({super.key, required this.dtc, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final u = Urgency.of(dtc.severity);
    final title = Row(children: [
      Icon(u.icon, color: u.color, size: compact ? 18 : 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(u.label,
            style: TextStyle(
                color: u.color,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 14 : 16)),
      ),
    ]);
    return Container(
      key: Key('urgency-${u.level}'),
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: u.color.withValues(alpha: 0.12),
        border: Border.all(color: u.color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title,
        SizedBox(height: compact ? 4 : 6),
        Text(u.advice,
            style: TextStyle(color: Colors.white, fontSize: compact ? 12 : 14)),
        if (!compact) ...[
          const SizedBox(height: 4),
          const Text(Urgency.caution,
              style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ]),
    );
  }
}
