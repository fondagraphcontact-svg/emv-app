import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import 'package:provider/provider.dart';

import '../maintenance/maintenance_screen.dart';
import '../report/report_screen.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/disclaimer.dart';
import '../widgets/part_sheet.dart';

const appVersion = '1.0.0';

const legalText =
    'Electro Meca View — application d\'information technique générique.\n\n'
    'Contenus : arborescence, vues schématiques et fiches de codes défaut '
    'rédigés par l\'éditeur. Les codes génériques suivent la structure publique '
    'SAE J2012 / ISO 15031-6. Aucune documentation, aucun dessin ni aucune '
    'donnée constructeur n\'est reproduit. Les noms de marques et de modèles '
    'sont cités à titre d\'identification uniquement et appartiennent à leurs '
    'propriétaires.\n\n'
    'Données personnelles : les véhicules, favoris et le carnet d\'entretien '
    'sont stockés uniquement '
    'sur cet appareil. Aucune donnée n\'est transmise.';

const privacyText =
    'Electro Meca View fonctionne hors ligne : pas de compte, pas de publicité, '
    'pas de mesure d\'audience.\n\n'
    'Données stockées uniquement sur cet appareil : véhicule sélectionné, carnet '
    'd\'entretien, codes défaut saisis (journal « Mes codes relevés »), '
    'dépenses saisies (montants, catégories, kilométrages), '
    'cases cochées du pré-contrôle technique, '
    'préférences et rappels. Elles sont effaçables depuis cet écran '
    'ou en désinstallant l\'application.\n\n'
    'VIN : décodé sur l\'appareil à partir d\'une table publique, jamais envoyé. '
    'Plaque d\'immatriculation : service non actif dans cette version ; en cas '
    'd\'activation, la plaque sera transmise à un prestataire d\'identification '
    'sans conservation côté EMV, et cette politique sera mise à jour.\n\n'
    'Rapport PDF et e-mails : générés sur l\'appareil et transmis par vos '
    'propres applications de partage.\n\n'
    'Notifications : rappels locaux, aucun serveur.\n\n'
    'Contact : $contactEmail';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;
    final favorites = state.favorites.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        const _Header('Mes véhicules'),
        if (state.saved.isEmpty)
          const ListTile(
            title: Text('Aucun véhicule enregistré'),
            subtitle: Text('Choisissez un véhicule dans l\'onglet Véhicule.'),
          ),
        for (final v in state.saved)
          ListTile(
            leading: Icon(
              v.id == state.current?.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: v.id == state.current?.id ? EmvColors.accent : null,
            ),
            title: Text(v.title),
            subtitle: Text(v.subtitle),
            onTap: () => state.setVehicle(v),
            trailing: IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => state.removeSaved(v),
            ),
          ),
        Card(
          child: ListTile(
            key: const Key('profile-maintenance'),
            leading: const Icon(Icons.menu_book_outlined,
                color: EmvColors.accent),
            title: const Text('Carnet d\'entretien'),
            subtitle: Text(state.current == null
                ? 'Choisissez d\'abord un véhicule'
                : '${state.current!.title} · '
                    '${state.maintenanceFor(state.current!.id).length} '
                    'intervention(s)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openMaintenance(context),
          ),
        ),
        Card(
          child: ListTile(
            key: const Key('profile-report'),
            leading: const Icon(Icons.picture_as_pdf_outlined,
                color: EmvColors.accent),
            title: const Text('Rapport pour le garage'),
            subtitle: const Text('PDF : véhicule, symptômes, codes, carnet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openReport(context),
          ),
        ),
        const _Header('Pièces favorites'),
        if (favorites.isEmpty)
          const ListTile(title: Text('Aucune pièce favorite')),
        for (final slug in favorites)
          ListTile(
            leading: const Icon(Icons.star, color: EmvColors.accent),
            title: Text(data.part(slug)?.part.name ?? slug),
            subtitle: Text(data.part(slug)?.breadcrumb ?? ''),
            onTap: () => showPartSheet(context, slug),
          ),
        const _Header('Réglages'),
        const ListTile(
          leading: Icon(Icons.language),
          title: Text('Langue'),
          subtitle: Text('Français (anglais bientôt disponible)'),
        ),
        const _Header('Informations'),
        ListTile(
          leading: const Icon(Icons.warning_amber_rounded),
          title: const Text('Avertissement'),
          onTap: () => showDisclaimer(context, firstLaunch: false),
        ),
        ListTile(
          leading: const Icon(Icons.gavel),
          title: const Text('Mentions légales'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Mentions légales'),
              content: const SingleChildScrollView(child: Text(legalText)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fermer')),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Politique de confidentialité'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Politique de confidentialité'),
              content: const SingleChildScrollView(child: Text(privacyText)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fermer')),
              ],
            ),
          ),
        ),
        FutureBuilder<DataMeta?>(
          future: _dataMeta,
          builder: (context, snap) {
            final meta = snap.data;
            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('À propos'),
              subtitle: Text('Version $appVersion'
                  '${meta == null ? '' : ' · données ${meta.version}'} · '
                  '${data.partSlugs.length} pièces · '
                  '${data.views.length} vues · ${data.dtcs.length} codes'),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Electro Meca View',
                applicationVersion: meta == null
                    ? appVersion
                    : '$appVersion · données ${meta.version}',
                applicationLegalese: 'Contenus génériques, hors ligne. '
                    'Ne remplace pas un professionnel.',
                children: [
                  if (meta != null && meta.changes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Nouveautés des données',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final c in meta.changes) Text('• $c'),
                  ],
                ],
              ),
            );
          },
        ),
      ]),
    );
  }
}

class DataMeta {
  final String version;
  final List<String> changes;

  const DataMeta(this.version, this.changes);

  factory DataMeta.fromJson(Map<String, dynamic> j) => DataMeta(
        j['data_version'] as String,
        [
          for (final e in (j['changelog'] as List? ?? const []))
            if (e is Map)
              for (final c in (e['changes'] as List? ?? const [])) c.toString()
            else
              e.toString(),
        ],
      );

  static Future<DataMeta?> load([AssetBundle? bundle]) async {
    try {
      final raw = await (bundle ?? rootBundle).loadString('assets/data/meta.json');
      return DataMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FlutterError {
      return null;
    }
  }
}

final Future<DataMeta?> _dataMeta = DataMeta.load();

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: EmvColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1)),
      );
}
