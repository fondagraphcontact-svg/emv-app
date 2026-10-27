import 'dart:convert';
import 'dart:io';

import 'package:emv/chatbot/chatbot_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// Non-régression du chatbot sur la vraie base (assets/data) : phrase réaliste -> intention attendue.
// Une phrase qui échoue ici se corrige en ajoutant un pattern dans chatbot_kb.json (jamais en retirant).

const _diesel = VehicleCtx(fuel: 'diesel', family: 'diesel-i4-turbo-cr', dpf: true);
const _petrol = VehicleCtx(fuel: 'petrol', family: 'petrol-i4-na');
const _moto = VehicleCtx(fuel: 'petrol', family: 'moto-twin', kind: 'moto');

class _Case {
  final String phrase;
  final String intent;
  final VehicleCtx? ctx;
  const _Case(this.phrase, this.intent, [this.ctx]);
}

const _golden = <_Case>[
  // Conversation / aide
  _Case('bonjour', 'greeting'),
  _Case('merci beaucoup pour ton aide', 'thanks'),
  _Case('tu sers à quoi ?', 'help'),
  _Case('comment lire les codes défaut avec un elm327', 'obd-read-codes'),
  _Case('que veut dire un voyant rouge au tableau de bord', 'warning-light-colors'),
  _Case('quelle huile mettre pour la vidange', 'service-oil-change'),
  // Moteur : voyants, puissance, ralenti
  _Case('j\'ai le voyant moteur allumé depuis hier', 'check-engine-light'),
  _Case('le voyant moteur clignote quand j\'accélère', 'check-engine-flashing'),
  _Case('la voiture passe en mode dégradé sur l\'autoroute', 'limp-mode'),
  _Case('ma voiture n\'a plus de puissance dans les montées', 'power-loss'),
  _Case('des à-coups quand j\'accélère à froid', 'hesitation-jerks'),
  _Case('le ralenti est instable, il monte et descend', 'rough-idle'),
  _Case('le moteur cale au feu rouge', 'stalling'),
  _Case('raté d\'allumage sur le cylindre 2', 'misfire'),
  _Case('le moteur tremble', 'misfire', _petrol),
  _Case('mon diesel tourne mal, un injecteur qui fuit ?', 'diesel-misfire'),
  _Case('le moteur tremble', 'diesel-misfire', _diesel),
  _Case('mon diesel s\'emballe tout seul', 'engine-runaway'),
  _Case('elle consomme beaucoup trop d\'essence', 'high-fuel-consumption'),
  _Case('mélange trop pauvre d\'après la valise', 'lean-rich-mixture'),
  // Fumées, bruits
  _Case('grosse fumée noire à l\'accélération', 'black-smoke'),
  _Case('fumée blanche qui sent le sucré', 'white-smoke'),
  _Case('fumée bleue à l\'échappement le matin', 'blue-smoke'),
  _Case('ça claque au ralenti', 'knock-idle'),
  _Case('cliquetis en montée quand je relance', 'pinking-knock'),
  _Case('bruit de chaîne de distribution au démarrage à froid', 'timing-chain-rattle'),
  _Case('à quel kilométrage changer la courroie de distribution', 'timing-belt'),
  _Case('la courroie siffle au démarrage quand il pleut', 'belt-squeal'),
  _Case('le turbo siffle fort en accélération', 'turbo-whistle'),
  _Case('le moteur vibre beaucoup, support moteur cassé ?', 'engine-vibration'),
  // Huile, joint de culasse
  _Case('de la mayonnaise sous le bouchon d\'huile', 'head-gasket'),
  _Case('tache d\'huile sous la voiture le matin', 'oil-leak'),
  _Case('le voyant d\'huile s\'allume dans les virages', 'oil-pressure-light'),
  _Case('je dois rajouter de l\'huile tous les 1000 km', 'oil-consumption'),
  _Case('le niveau d\'huile monte et ça sent le gasoil', 'oil-level-rising'),
  // Démarrage
  _Case('ma voiture ne démarre pas, ça fait juste clic', 'no-start-click'),
  _Case('le démarreur tourne mais le moteur ne part pas', 'no-start-cranks'),
  _Case('elle démarre mal le matin quand il fait froid', 'hard-start-cold'),
  _Case('ne redémarre pas à chaud après l\'autoroute', 'hard-start-hot'),
  _Case('voyant préchauffage qui clignote en roulant', 'glow-plug-light'),
  _Case('voyant clé qui clignote et antidémarrage actif', 'immobilizer'),
  // Carburant
  _Case('on n\'entend pas la pompe à essence au contact', 'fuel-pump'),
  _Case('manque de pression rail sur mon diesel', 'rail-pressure'),
  _Case('voyant eau dans le gasoil allumé', 'diesel-fuel-filter'),
  _Case('panne sèche avec mon diesel, comment réamorcer', 'diesel-out-of-fuel'),
  _Case('j\'ai mis de l\'essence dans mon diesel', 'wrong-fuel'),
  _Case('forte odeur d\'essence dans l\'habitacle', 'fuel-smell'),
  _Case('électrovanne de purge canister défectueuse', 'evap-system'),
  _Case('la jauge à carburant reste bloquée', 'fuel-gauge'),
  // Air, allumage, capteurs
  _Case('le débitmètre est HS ?', 'maf-sensor'),
  _Case('le turbo ne pousse plus', 'underboost'),
  _Case('surpression turbo, la géométrie variable est grippée', 'overboost'),
  _Case('nettoyer le boîtier papillon encrassé', 'throttle-body'),
  _Case('volets de turbulence bloqués', 'swirl-flaps'),
  _Case('quand changer le filtre à air', 'air-filter'),
  _Case('tous les combien changer les bougies d\'allumage', 'spark-plugs'),
  _Case('bobine d\'allumage grillée', 'ignition-coil'),
  _Case('capteur vilebrequin défaillant, compte tours qui ne bouge pas', 'crankshaft-sensor'),
  _Case('capteur arbre à cames HS', 'camshaft-sensor'),
  _Case('l\'aiguille de température affiche n\'importe quoi', 'coolant-temp-sensor'),
  // Dépollution
  _Case('vanne EGR encrassée, faut-il la nettoyer', 'egr-valve'),
  _Case('j\'ai le code P0401', 'egr-valve'),
  _Case('FAP colmaté', 'dpf-clogged'),
  _Case('régénération en cours, ralenti élevé tout seul', 'dpf-regeneration'),
  _Case('pot catalytique bouché, odeur d\'oeuf pourri', 'catalyst'),
  _Case('sonde lambda HS', 'lambda-sensor'),
  _Case('mon pot d\'échappement est troué', 'exhaust-noise'),
  _Case('voyant AdBlue avec compte à rebours', 'adblue'),
  _Case('refusé au contrôle technique pour l\'opacité', 'emissions-test-fail'),
  _Case('j\'ai le code P0299 sur ma voiture', 'underboost'),
  // Refroidissement, chauffage
  _Case('le moteur chauffe dans les bouchons', 'overheating'),
  _Case('je perds du liquide de refroidissement', 'coolant-loss'),
  _Case('le motoventilateur ne se déclenche jamais', 'cooling-fan'),
  _Case('le moteur ne monte pas en température', 'engine-stays-cold'),
  _Case('le chauffage souffle froid', 'no-heating'),
  // Électricité
  _Case('ma batterie est morte', 'battery-dead'),
  _Case('comment brancher les câbles pour démarrer avec une autre voiture', 'jump-start'),
  _Case('voyant batterie allumé en roulant', 'battery-light'),
  _Case('ma batterie se vide pendant la nuit', 'battery-drain'),
  _Case('le démarreur tourne lentement', 'starter-slow'),
  _Case('le fusible des feux grille à répétition', 'fuse-blown'),
  _Case('comment tester un fusible avec un multimètre', 'fuse-test'),
  _Case('où se trouve la boîte à fusibles', 'fuse-box-location'),
  _Case('un relais claque sous le tableau de bord', 'relay-clicking'),
  _Case('mes phares éclairent mal la nuit', 'dim-lights'),
  _Case('ampoule de feu de croisement grillée', 'headlight-out'),
  _Case('le clignotant gauche clignote très vite', 'indicator-fast'),
  _Case('les feux stop restent allumés', 'brake-lights'),
  _Case('le klaxon ne marche plus', 'horn-wipers'),
  _Case('tous les voyants du tableau de bord s\'allument d\'un coup', 'dash-lights-all-on'),
  _Case('faux contact électrique aléatoire', 'electrical-random'),
  _Case('le compteur de vitesse est bloqué à zéro', 'speedometer'),
  // Transmission
  _Case('l\'embrayage patine en quatrième', 'clutch-slipping'),
  _Case('la pédale d\'embrayage reste au plancher', 'clutch-pedal'),
  _Case('ça craque quand je passe la seconde', 'gear-grinding'),
  _Case('bruit de ferraille au ralenti, volant bimasse ?', 'dual-mass-flywheel'),
  _Case('la boîte automatique passe les vitesses brutalement', 'auto-gearbox'),
  _Case('claquement en braquant à fond', 'cv-joint'),
  _Case('bruit de roulement qui augmente avec la vitesse', 'wheel-bearing'),
  // Freins
  _Case('mes freins grincent', 'brake-squeal'),
  _Case('le volant vibre quand je freine', 'brake-vibration'),
  _Case('la pédale de frein s\'enfonce jusqu\'au plancher', 'brake-pedal-soft'),
  _Case('la voiture tire à gauche au freinage', 'brake-pulls'),
  _Case('voyant ABS allumé', 'abs-light'),
  _Case('voyant frein rouge allumé', 'brake-warning-light'),
  _Case('le frein à main électrique est bloqué', 'parking-brake'),
  _Case('quand changer les plaquettes de frein', 'brake-pads-wear'),
  // Train roulant, direction
  _Case('cloc sur les bosses à l\'avant', 'suspension-noise'),
  _Case('amortisseurs usés, la voiture rebondit', 'shock-absorber'),
  _Case('ressort de suspension cassé', 'broken-spring'),
  _Case('la direction est devenue dure d\'un coup', 'steering-heavy'),
  _Case('il y a du jeu dans le volant', 'steering-play'),
  _Case('la voiture tire à droite en ligne droite', 'pulls-to-side'),
  _Case('le volant vibre à 130 sur autoroute', 'wheel-vibration-speed'),
  _Case('voyant pression des pneus allumé', 'tyres'),
  // Climatisation, ventilation
  _Case('la clim ne fait plus de froid', 'ac-not-cold'),
  _Case('la clim sent le moisi', 'ac-smell'),
  _Case('la ventilation marche seulement en 4', 'blower'),
  // Hybride / électrique
  _Case('voyant système hybride allumé', 'hybrid-warning'),
  _Case('ma voiture électrique ne charge pas à la borne', 'ev-not-charging'),
  // Moto / scooter
  _Case('comment régler la tension de chaîne de ma moto', 'moto-chain-maintenance'),
  _Case('kit chaîne usé, la chaîne saute', 'moto-chain-worn'),
  _Case('ma moto ne démarre pas', 'moto-no-start'),
  _Case('carburateur encrassé sur ma 125', 'moto-carburetor'),
  _Case('ma moto broute à bas régime', 'moto-injection'),
  _Case('l\'embrayage de ma moto patine', 'moto-clutch'),
  _Case('l\'embrayage patine', 'moto-clutch', _moto),
  _Case('galets de variateur usés sur mon scooter', 'scooter-cvt'),
  _Case('batterie moto à plat, le régulateur ?', 'moto-charging'),
  _Case('spi de fourche qui fuit', 'fork-seal'),
  _Case('la moto guidonne à haute vitesse', 'moto-steering-head'),
  _Case('levier de frein mou sur la moto', 'moto-brakes'),
  _Case('mon scooter chauffe', 'moto-overheating'),
  // Divers
  _Case('ça sent le brûlé après avoir roulé', 'burning-smell'),
];

// Négation : la partie niée d'une proposition n'alimente pas l'intention (ni ne doit donner [forbidden]).
class _NegCase {
  final String phrase;
  final String? intent;
  final String forbidden;
  const _NegCase(this.phrase, this.intent, this.forbidden);
}

const _negation = <_NegCase>[
  _NegCase('le moteur ne chauffe pas', 'engine-stays-cold', 'overheating'),
  _NegCase('le moteur chauffe', 'overheating', 'engine-stays-cold'),
  _NegCase('pas de fumée mais le voyant moteur est allumé', 'check-engine-light', 'black-smoke'),
  _NegCase('pas de fumée noire, juste une perte de puissance', 'power-loss', 'black-smoke'),
  _NegCase('il n\'y a pas de fumée noire', null, 'black-smoke'),
  _NegCase('aucun voyant allumé mais elle cale au feu rouge', 'stalling', 'check-engine-light'),
  _NegCase('sans fumée, le turbo siffle fort', 'turbo-whistle', 'black-smoke'),
  _NegCase('le moteur ne cale jamais mais le ralenti est instable', 'rough-idle', 'stalling'),
  _NegCase('ça chauffe pas mais ça sent le brûlé', 'burning-smell', 'overheating'),
  _NegCase('je n\'ai pas de fuite d\'huile mais le voyant d\'huile s\'allume', 'oil-pressure-light', 'oil-leak'),
  _NegCase('les freins ne grincent pas mais la pédale s\'enfonce', 'brake-pedal-soft', 'brake-squeal'),
  _NegCase('elle ne consomme pas d\'huile mais fume bleu', 'blue-smoke', 'oil-consumption'),
  _NegCase('la batterie n\'est pas à plat, le démarreur tourne lentement', 'starter-slow', 'battery-dead'),
  _NegCase('elle ne vibre pas au freinage, mais elle tire à gauche', 'brake-pulls', 'brake-vibration'),
  _NegCase('pas de mayonnaise sous le bouchon mais fumée blanche', 'white-smoke', 'head-gasket'),
  _NegCase('le voyant moteur ne clignote pas, il est fixe', 'check-engine-light', 'check-engine-flashing'),
  _NegCase('la clim ne fait plus de froid', 'ac-not-cold', 'no-heating'),
  // negated_patterns : la forme niée mène à l'intention « inverse »
  _NegCase('le ventilateur ne se déclenche jamais', 'cooling-fan', 'overheating'),
  _NegCase('le chauffage ne souffle pas chaud', 'no-heating', 'ac-not-cold'),
  _NegCase('la clim ne souffle pas froid', 'ac-not-cold', 'no-heating'),
];

// FAP inconnu (engine.dpf absent) sur moteur diesel, y compris hybride diesel : contrôles [dpf] « (si équipé) ».
const _dieselDpfUnknown = VehicleCtx(fuel: 'diesel', family: 'diesel-i4-turbo-cr');
const _hybridDieselDpfUnknown = VehicleCtx(fuel: 'hybrid', family: 'diesel-i4-turbo-cr');

const _dpfUnknown = <_Case>[
  _Case('perte de puissance', 'power-loss', _dieselDpfUnknown),
  _Case('le niveau d\'huile monte', 'oil-level-rising', _hybridDieselDpfUnknown),
  _Case('quelle huile mettre pour la vidange', 'service-oil-change', _dieselDpfUnknown),
];

List<dynamic> _list(String path) => jsonDecode(File(path).readAsStringSync()) as List<dynamic>;

void main() {
  final engine = ChatbotEngine.fromJson(
    kb: _list('assets/data/chatbot_kb.json'),
    tree: _list('assets/data/tree.json'),
    dtc: _list('assets/data/dtc.json'),
    vehicles: jsonDecode(File('assets/data/vehicles.json').readAsStringSync()) as Map<String, dynamic>,
  );

  test('le golden couvre au moins 100 phrases et chaque intention attendue existe', () {
    expect(_golden.length, greaterThanOrEqualTo(100));
    final ids = engine.intents.map((i) => i.id).toSet();
    expect(_golden.map((c) => c.intent).where((i) => !ids.contains(i)).toSet(), isEmpty);
  });

  test('chaque phrase du golden mène à l\'intention attendue', () {
    final failures = <String>[];
    for (final c in _golden) {
      final got = engine.reply(c.phrase, ctx: c.ctx).intentId;
      if (got != c.intent) {
        failures.add('« ${c.phrase} »${c.ctx == null ? '' : ' [${c.ctx!.label}]'} : '
            'attendu ${c.intent}, obtenu ${got ?? 'aucune intention'}');
      }
    }
    expect(failures, isEmpty, reason: '${failures.length} échec(s) :\n${failures.join('\n')}');
  });

  test('négation : la partie niée ne déclenche pas l\'intention', () {
    expect(_negation.length, greaterThanOrEqualTo(15));
    final ids = engine.intents.map((i) => i.id).toSet();
    expect(
        _negation.expand((c) => [?c.intent, c.forbidden]).where((i) => !ids.contains(i)).toSet(), isEmpty);
    final failures = <String>[];
    for (final c in _negation) {
      final got = engine.reply(c.phrase).intentId;
      if (got != c.intent || got == c.forbidden) {
        failures.add('« ${c.phrase} » : attendu ${c.intent ?? 'aucune intention'}, obtenu ${got ?? 'aucune intention'}');
      }
    }
    expect(failures, isEmpty, reason: '${failures.length} échec(s) :\n${failures.join('\n')}');
  });

  test('FAP inconnu sur moteur diesel : contrôles FAP avec « (si équipé) »', () {
    for (final c in _dpfUnknown) {
      final r = engine.reply(c.phrase, ctx: c.ctx);
      expect(r.intentId, c.intent, reason: c.phrase);
      final fap = r.checks.where((x) => x.contains('FAP')).toList();
      expect(fap, isNotEmpty, reason: c.phrase);
      expect(fap.every((x) => x.endsWith(ChatbotEngine.dpfUnknownSuffix)), isTrue, reason: '${c.phrase} : $fap');
    }
  });
}
