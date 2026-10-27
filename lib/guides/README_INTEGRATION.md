# Guides de diagnostic pas-à-pas — intégration

Module isolé : `guide_models.dart`, `guide_assets.dart`, `guide_list_screen.dart`,
`guide_runner_screen.dart`. Données : `assets/data/guides.json` (généré, ne pas
éditer à la main : sources dans `docs/guides_src/`, `python3 build_guides.py`
reconstruit et valide, `--check` valide seulement).

## Format

Guide : `id, title, summary, category, kind (car|moto|both), fuel[], requires[]
("dpf"), difficulty 1-3, tools[], time, safety[], stopIf[], steps[], results[]`.
La première étape de `steps` est le point d'entrée.

Étape : `id, q, check, yes, no, unknown?, parts[], dtc[]` — `yes`/`no`/`unknown`
pointent vers une étape ou un résultat du même guide. Sans `unknown`,
« Je ne sais pas » suit la branche `no` (vérification suivante, jamais une
conclusion hâtive).

Résultat : `id, title, text, parts[], dtc[], views[], pro` (`pro: true` affiche
« Intervention d'un professionnel conseillée »).

## Utilisation

```dart
GuideListScreen(vehicle: state.current, onOpen: (g) => openGuide(context, g));

Navigator.push(context, GuideRunnerScreen.route(guide,
    onOpenView: (viewId) {...}, onOpenPart: (slug) {...}, onOpenDtc: (code) {...}));
```

Un callback `null` masque les boutons correspondants. Le résultat affiche
`FeedbackBar(type: 'guide', id: guide.id)` : un `AppState` doit être fourni
par `Provider` (c'est le cas dans l'app). `Guide.appliesTo(vehicle)` écarte
les guides d'un autre type (voiture/moto), d'une autre énergie (hybride et GPL
comptent comme essence) ou exigeant un FAP absent.

## Branché dans l'app

- `screens/faults.dart` : onglets **Codes / Guides** (`Key('tab-codes')`,
  `Key('tab-guides')`) ; `openGuide(context, guide)` et
  `openGuideById(context, id)` câblent vue (onglet Vues), pièce
  (`showPartSheet`) et fiche DTC.
- Chatbot : champ KB `guide` (chaîne, ou objet `{"diesel": id, "petrol": id}`
  pour un guide dépendant de l'énergie) → action `BotActionType.openGuide`
  « Ouvrir le guide pas-à-pas », placée en tête ; `ChatbotScreen.onOpenGuide`
  (masquée si absent), branché dans `screens/assistant.dart`.

## Tests

`test/guides_test.dart` : validité et références du JSON (pièces, codes, vues,
aucune étape orpheline), liens KB → guides, filtre véhicule, réponses chatbot,
runner (questions, « Je ne sais pas », fil d'Ariane, résultat, callbacks) et
onglet Guides.

En widget test, précharger avec `await loadGuides()` dans `setUpAll` : la liste
lit alors `loadedGuides` sans attendre un futur hors fake-async.
