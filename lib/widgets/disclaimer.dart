import 'package:flutter/material.dart';

const disclaimerText =
    'Electro Meca View informe et aide à comprendre le fonctionnement d\'un '
    'véhicule. Elle ne remplace pas le diagnostic ni l\'intervention d\'un '
    'professionnel qualifié.\n\n'
    'Les vues, descriptions et codes défaut sont génériques et rédigés par '
    'nous : aucune donnée, aucun dessin ni aucun texte constructeur n\'est '
    'utilisé. Ils peuvent différer de votre véhicule.\n\n'
    'Toute intervention (freinage, haute tension, carburant, airbag…) relève '
    'de votre seule responsabilité. En cas de doute, consultez un garage.';

Future<void> showDisclaimer(BuildContext context,
    {required bool firstLaunch, VoidCallback? onAccept}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: !firstLaunch,
      builder: (context) => PopScope(
        canPop: !firstLaunch,
        child: AlertDialog(
          title: const Text('Avertissement'),
          content: const SingleChildScrollView(child: Text(disclaimerText)),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onAccept?.call();
              },
              child: Text(firstLaunch ? 'J\'ai compris' : 'Fermer'),
            ),
          ],
        ),
      ),
    );
