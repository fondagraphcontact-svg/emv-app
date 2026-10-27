# Assistant (onglet 5) — intégration

Module isolé, hors ligne, sans réseau ni IA externe. Il ne dépend d'aucun fichier de `lib/` hors `lib/chatbot/`.

| Fichier | Rôle |
|---|---|
| `chatbot_engine.dart` | Moteur pur Dart (aucun import Flutter) : normalisation, DTC, pièces, véhicules, intentions, filtrage carburant/FAP/moto. |
| `chatbot_screen.dart` | UI chat (bulles sombre/orange, saisie, chips, boutons d'action). Tout passe par des callbacks. |
| `chatbot_assets.dart` | `loadChatbotEngine([AssetBundle])` : charge `assets/data/{chatbot_kb,tree,dtc,vehicles}.json`. |
| `assets/data/chatbot_kb.json` | 128 intentions FR (déjà couvert par `assets/data/` dans pubspec). |
| `test/chatbot_engine_test.dart` | Tests du moteur + un test widget. |

## 1. Charger le moteur (une fois, au démarrage)

```dart
import 'chatbot/chatbot_assets.dart';
import 'chatbot/chatbot_engine.dart';

final ChatbotEngine engine = await loadChatbotEngine();   // ~100 ms pour 1000 DTC + vehicles.json
```

Ou, si `AppData` a déjà les JSON décodés : `ChatbotEngine.fromJson(kb: kbList, tree: treeList, dtc: dtcList, vehicles: vehiclesMap)`.
Le moteur construit lui-même ses index (`PartInfo.listFromTree`, `DtcInfo.fromJson`, `VehicleEntry.listFromJson`) à partir des formats de la SPEC : aucune dépendance à `models.dart`.

## 2. Brancher l'onglet

`main.dart` : ajouter `AppTab.assistant` dans `state.dart`, un 5e `NavigationDestination` (`Icons.forum_outlined`, label « Assistant ») et :

```dart
ChatbotScreen(
  engine: engine,                       // null => spinner pendant le chargement
  vehicle: _ctxFrom(state.current),     // null => réponses générales
  onOpenView: (slug) => state.showPartsInView([slug]),
  onOpenPart: (slug) => state.showPartsInView([slug]),        // ou une fiche pièce si vous en avez une
  onOpenViewId: (viewId) { state.openView(viewId); state.selectTab(AppTab.views); },
  onOpenDtc: (code) { /* sélectionner l'onglet Diagnostic et pousser la fiche state.data.dtc(code) */ },
  onSelectVehicle: (v) => state.setVehicle(Vehicle(
    make: v.make, model: v.model, engine: v.engine, fuel: v.fuel, family: v.family,
    code: v.code ?? '', kind: parseKind(v.kind), yearFrom: v.yearFrom, yearTo: v.yearTo)),
)
```

Conversion véhicule courant → contexte :

```dart
VehicleCtx? _ctxFrom(Vehicle? v) => v == null ? null : VehicleCtx(
  fuel: v.fuel, family: v.family, make: v.make, model: v.model, engine: v.engine,
  kind: v.kind.name,     // 'car' | 'moto'
  dpf: null,             // voir ci-dessous
);
```

**FAP** : `vehicles.json` contient `"dpf": true|false` sur les moteurs diesel, mais `EngineSpec` / `Vehicle` ne le lisent pas encore.
Ajoutez `bool? dpf` (lu dans `EngineSpec.fromJson`, copié dans `Vehicle`, sérialisé dans `toJson/fromJson`) puis passez `dpf: v.dpf`.
Tant que `dpf` vaut `null`, le moteur considère le FAP « possible » et le propose sur diesel.

`showAppBar: false` si l'onglet est déjà dans un Scaffold avec AppBar.

## 3. Contrat du moteur

```dart
BotReply reply = engine.reply('ma meriva 1.7 cdti fume noir', ctx: vehicleCtx);
```

- `reply.text`, `reply.checks` (3-5 contrôles dans l'ordre, déjà filtrés), `reply.safety` (nullable), `reply.suggestions` (chips qui renvoient le texte).
- `reply.actions` : `BotAction {label, type, payload, vehicle?}`
  - `openView` → slug de pièce (vue éclatée, pièce surlignée) — 1re pièce pertinente
  - `openPart` → slug de pièce liée
  - `openViewId` → id de vue (`fuse-box-generic`, `wiring-*`) ; masqué par l'UI si `onOpenViewId` n'est pas fourni
  - `openDtc` → code (uniquement si présent dans `dtc.json`)
  - `selectVehicle` → `payload = "make|model|engine"`, `vehicle` = `VehicleEntry`
- `reply.intentId`, `reply.dtcCode`, `reply.partSlug`, `reply.vehicles` (candidats détectés), `reply.ctx` (contexte réellement utilisé : un véhicule cité dans le message prime sur le véhicule courant).

Filtrage par contexte :
- Intention : `fuel` (vide = tous ; `hybrid`/`lpg` acceptent `petrol`), `kind` (`car`/`moto`), `requires: ["dpf"]`. Une intention exclue donne une remarque (« Votre véhicule est déclaré sans FAP… »).
- Contrôles : préfixe optionnel `[diesel]`, `[petrol]`, `[dpf]`, `[moto]`, `[car]`, `[electric]` (combinables : `[diesel,dpf]`), retiré à l'affichage.
- Pièces : bougies d'allumage/bobines/carburation masquées sur diesel, préchauffage/FAP/AdBlue/circuit diesel sur essence, `dpf*` si `dpf == false`, haute tension hors hybride/électrique, pièces moto/voiture selon `kind`. Un champ optionnel `fuel`/`kind` par pièce dans `tree.json` est aussi respecté.
- DTC FAP (P2002, P244x, P2452-P2463) masqués si pas de FAP.

## 4. Format `chatbot_kb.json`

Format de la SPEC + champs optionnels : `kind`, `requires`, `priority` (départage, ex. −1 pour les intentions génériques), `safety`, `views` (ids de vues `wiring-*` / `fuse-box-generic`).
`parts` = slugs de `tree.json` ; `section` = slug de sous-section de `tree.json` (vérifié par les tests).

## 5. À savoir

- `dtc_parts.txt` utilise des slugs absents de `tree.json` (ex. `crankshaft-sensor` vs `crankshaft-position-sensor`, `camshaft-sensor`, `fuse`, `glow-plug-relay`, `oil-pressure-switch`) : la KB s'aligne sur `tree.json`. Les pièces d'une fiche DTC absentes de l'arbre ne génèrent pas de bouton.
- Si un slug est renommé dans `tree.json`, le test « pièces et sections existent dans tree.json » échoue : mettre à jour la KB.
