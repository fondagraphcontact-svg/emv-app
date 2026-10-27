import '../data.dart';
import '../models.dart';

enum InsightSource { engine, model }

class Insight {
  final InsightSource source;
  final String text;
  final String detail;
  final int score;
  final List<String> topics;
  final EngineSpecInfo? engine;
  final ModelSpec? model;

  const Insight({
    required this.source,
    required this.text,
    this.detail = '',
    required this.score,
    this.topics = const [],
    this.engine,
    this.model,
  });

  String get sourceLabel => source == InsightSource.engine
      ? 'Fiche moteur ${engine?.code ?? ''}'.trim()
      : 'Fiche du modèle';
}

class InsightTopic {
  final String id;
  final String label;
  final int weight;
  final List<String> keywords;
  final Set<String> parts;

  const InsightTopic(this.id, this.label, this.weight, this.keywords, this.parts);
}

/// Keywords are matched at the start of a word on normalized text
/// (lowercase, no accents, punctuation as spaces).
const insightTopics = <InsightTopic>[
  InsightTopic('egr', 'vanne EGR', 3, ['egr', 'recirculation des gaz'],
      {'egr-valve', 'egr-cooler', 'egr-solenoid', 'egr-throttle-valve'}),
  InsightTopic('dpf', 'FAP', 3,
      ['fap', 'filtre a particules', 'gpf', 'regeneration', 'pression differentielle'],
      {'dpf', 'dpf-pressure-sensor', 'dpf-temp-sensor', 'gasoline-particulate-filter'}),
  InsightTopic('turbo', 'turbo', 3,
      ['turbo', 'suralimentation', 'geometrie variable', 'wastegate', 'ailettes', 'intercooler', 'echangeur air'],
      {'turbocharger', 'wastegate-actuator', 'boost-pressure-sensor', 'boost-solenoid',
       'diverter-valve', 'intercooler', 'intercooler-hose', 'turbo-oil-line'}),
  InsightTopic('injector', 'injecteurs', 3, ['injecteur'],
      {'injector', 'injector-seal', 'injector-return-line', 'injector-driver-module'}),
  InsightTopic('high-pressure', 'haute pression carburant', 3,
      ['pompe haute pression', 'pompe hp', 'pression de rampe', 'haute pression', 'rampe commune', 'pompe d injection'],
      {'high-pressure-pump', 'fuel-rail-pressure-sensor', 'fuel-pressure-control-valve',
       'common-rail', 'fuel-metering-valve', 'pressure-relief-valve', 'high-pressure-line'}),
  InsightTopic('chain', 'chaîne de distribution', 3, ['chaine', 'tendeur de chaine'],
      {'timing-chain', 'chain-tensioner', 'chain-guide', 'tensioner-rail', 'cam-chain', 'oil-pump-chain'}),
  InsightTopic('belt', 'courroie de distribution', 3, ['courroie de distribution', 'courroie a bain d huile'],
      {'timing-belt', 'tensioner', 'idler-pulley'}),
  InsightTopic('timing', 'distribution / calage', 2,
      ['distribution', 'calage', 'dephaseur', 'vvt', 'vanos', 'arbre a cames'],
      {'vvt-solenoid', 'vvt-actuator', 'camshaft', 'camshaft-sprocket', 'timing-belt', 'timing-chain'}),
  InsightTopic('coil', 'bobines d\'allumage', 3, ['bobine'], {'ignition-coil', 'spark-plug-wire'}),
  InsightTopic('ignition', 'allumage', 2, ['allumage', 'bougie d allumage', 'bougies d allumage', 'rates'],
      {'spark-plug', 'ignition-coil', 'spark-plug-wire', 'cdi-unit', 'distributor'}),
  InsightTopic('glow', 'préchauffage', 3, ['prechauffage'], {'glow-plug', 'glow-plug-control-unit'}),
  InsightTopic('lambda', 'sonde lambda', 3, ['lambda', 'sonde a oxygene', 'sonde o2'],
      {'lambda-sensor-upstream', 'lambda-sensor-downstream'}),
  InsightTopic('catalyst', 'catalyseur', 3, ['catalyseur', 'catalytique'],
      {'catalytic-converter', 'oxidation-catalyst'}),
  InsightTopic('maf', 'débitmètre', 3, ['debitmetre'], {'maf-sensor'}),
  InsightTopic('map', 'pression d\'admission', 2, ['pression d admission', 'capteur map'], {'map-sensor'}),
  InsightTopic('throttle', 'boîtier papillon', 3, ['papillon'], {'throttle-body'}),
  InsightTopic('swirl', 'volets d\'admission', 3,
      ['volets de turbulence', 'volet de turbulence', 'volets d admission', 'volet d admission', 'swirl'],
      {'swirl-flap', 'egr-throttle-valve'}),
  InsightTopic('intake', 'admission', 2, ['collecteur d admission', 'durite d admission', 'prise d air'],
      {'intake-manifold', 'intake-hose', 'intake-manifold-gasket'}),
  InsightTopic('scr', 'AdBlue / SCR', 3, ['adblue', 'scr', 'nox'],
      {'scr-catalyst', 'adblue-injector', 'nox-sensor', 'adblue-line', 'adblue-pump', 'adblue-tank', 'scr-mixer'}),
  InsightTopic('vacuum', 'circuit de dépression', 2, ['depression', 'pompe a vide'],
      {'vacuum-hose', 'vacuum-pump', 'brake-booster-sensor'}),
  InsightTopic('pcv', 'réaspiration des vapeurs d\'huile', 3,
      ['reaspiration', 'vapeurs d huile', 'reniflard', 'decanteur', 'recyclage des vapeurs'], {'pcv-valve'}),
  InsightTopic('evap', 'canister', 3, ['canister', 'purge'], {'evap-canister', 'purge-valve', 'evap-vent-valve', 'evap-hose'}),
  InsightTopic('fuel-supply', 'alimentation carburant', 2,
      ['pompe a carburant', 'pompe a essence', 'pompe de gavage', 'pompe d alimentation', 'filtre a gazole', 'filtre a carburant', 'regulateur de pression d essence'],
      {'fuel-pump', 'fuel-pump-relay', 'fuel-filter', 'fuel-pressure-regulator', 'fuel-line'}),
  InsightTopic('oil', 'lubrification', 1, ['huile', 'lubrification', 'pression d huile'],
      {'engine-oil', 'oil-pump', 'oil-pressure-sensor', 'oil-filter', 'oil-level-sensor', 'oil-strainer'}),
  InsightTopic('bearings', 'coussinets de bielle', 3, ['coussinet', 'bielle'], {'connecting-rod', 'main-bearing'}),
  InsightTopic('cooling', 'refroidissement', 2,
      ['pompe a eau', 'thermostat', 'calorstat', 'surchauffe', 'radiateur', 'liquide de refroidissement', 'motoventilateur'],
      {'water-pump', 'thermostat', 'radiator', 'coolant', 'expansion-tank', 'coolant-temp-sensor', 'cooling-fan',
       'thermostat-housing', 'electric-coolant-pump', 'radiator-hose'}),
  InsightTopic('head-gasket', 'joint de culasse', 3, ['joint de culasse', 'culasse fissuree'], {'head-gasket'}),
  InsightTopic('flywheel', 'volant moteur bimasse', 3, ['bi masse', 'bimasse', 'volant moteur'],
      {'dual-mass-flywheel', 'flywheel'}),
  InsightTopic('clutch', 'embrayage', 2, ['embrayage'],
      {'clutch-disc', 'pressure-plate', 'release-bearing', 'clutch-master-cylinder', 'clutch-slave-cylinder', 'clutch-actuator', 'clutch-position-sensor'}),
  InsightTopic('crank-cam-sensor', 'capteurs vilebrequin / arbre à cames', 3,
      ['capteur pmh', 'capteur de vilebrequin', 'capteur de position vilebrequin', 'capteur d arbre a cames', 'capteur de phase'],
      {'crankshaft-position-sensor', 'camshaft-position-sensor'}),
  InsightTopic('knock', 'cliquetis', 3, ['cliquetis'], {'knock-sensor'}),
  InsightTopic('charging', 'charge / batterie', 2, ['batterie 12', 'alternateur', 'regulateur de tension', 'demarreur'],
      {'battery', 'alternator', 'voltage-regulator', 'starter-motor', 'battery-sensor', 'rectifier-regulator', 'stator'}),
  InsightTopic('electrical', 'faisceau / connecteurs', 1, ['faisceau', 'connecteur', 'cosse', 'oxydation'],
      {'wiring-harness', 'connector', 'ground-strap', 'ground-point'}),
  InsightTopic('ecu', 'calculateur', 1, ['calculateur', 'ecu'], {'ecu', 'transmission-control-module'}),
  InsightTopic('gearbox', 'boîte de vitesses', 1, ['boite'], {'gearbox', 'transmission-fluid'}),
  InsightTopic('gearbox-auto', 'boîte automatique / robotisée', 3,
      ['boite automatique', 'boite auto', 'boites automatiques', 'robotisee', 'boite pilotee', 'double embrayage',
       'mecatronique', 'convertisseur de couple', 'pontage', 'edc', 'dsg', 'eat6', 'eat8', 'powershift', 'cvt', 'al4', 'tiptronic',
       'dct', 'multitronic', 'selespeed', 'easytronic', 'etg', 'bmp6', '2 tronic', 'variation continue'],
      {'valve-body', 'shift-solenoid', 'transmission-control-module', 'torque-converter', 'gearbox-actuator',
       'pressure-control-solenoid', 'transmission-pressure-sensor', 'torque-converter-clutch-solenoid',
       'transmission-fluid-temp-sensor', 'transmission-filter', 'shift-lock-solenoid', 'clutch-actuator',
       'intermediate-speed-sensor', 'transmission-cooler'}),
  InsightTopic('gearbox-manual', 'boîte manuelle', 2,
      ['boite manuelle', 'synchro', 'roulements de boite', 'commande de boite'],
      {'synchronizer', 'synchronizer-ring', 'shaft-bearing', 'gear-selector', 'shift-cable', 'shift-fork'}),
  InsightTopic('abs', 'ABS / ESP', 3, ['abs', 'esp', 'capteur de vitesse de roue'],
      {'abs-module', 'wheel-speed-sensor', 'abs-tone-ring'}),
  InsightTopic('steering', 'direction assistée', 2, ['direction assistee', 'assistance de direction', 'assistance electrique'],
      {'eps-motor', 'torque-sensor', 'power-steering-pump', 'steering-angle-sensor', 'power-steering-pressure-sensor'}),
  InsightTopic('hybrid', 'système hybride / haute tension', 3,
      ['batterie de traction', 'batterie hybride', 'onduleur', 'haute tension', 'hybride'],
      {'hv-battery', 'bms', 'inverter', 'electric-motor', 'dc-dc-converter', 'hv-contactor', 'battery-module'}),
  InsightTopic('climate', 'climatisation', 3, ['climatisation', 'clim'],
      {'ac-compressor', 'ac-condenser', 'evaporator', 'ac-pressure-sensor', 'ac-expansion-valve'}),
  InsightTopic('immobilizer', 'antidémarrage', 3,
      ['antidemarrage', 'transpondeur', 'carte non detectee', 'lecteur de carte'], {'immobilizer'}),
];

final _problem = RegExp(
    r'\b(encrass|usur|use\b|usee|fuite|gripp|casse|cass|defaillan|signale|frequent|surveill|panne|colmat|'
    r'ruptur|fissur|claqu|calamine|corrosion|bruit|perte|rapport|fragil|faibless|problem|defaut|'
    r'deteriore|bouch|dilution|allong|cogn|consommation|delamin|surchauffe|fatigu|controler|'
    r'degrade|a coups|fumee|voyant|cas\b|risque|sensible|grill|hs\b|s use)');

/// Parts listed by many unrelated codes and issues (wiring, ECU, battery,
/// oil...): sharing one of them is a weak hint, never enough on its own.
const genericInsightParts = {
  'wiring-harness', 'connector', 'ground-strap', 'ground-point', 'ecu', 'relay',
  'main-relay', 'fuse-mini', 'fuse-ato', 'fuse-maxi', 'main-fuse', 'fuse-box-engine',
  'fuse-box-cabin', 'battery', 'battery-terminal', 'battery-cable', 'engine-oil',
  'coolant', 'instrument-cluster', 'dashboard-warning-lamp', 'diagnostic-socket',
  'vacuum-hose', 'bolt', 'gearbox', 'transmission-fluid',
};

class _Candidate {
  final Insight insight;
  final Set<String> topics;
  final Set<String> parts;
  final Set<String> groups;
  final Set<String> dtc;
  final String text;
  final bool engineSpecific;
  final int order;

  _Candidate(this.insight, this.topics, this.parts, this.groups, this.dtc,
      this.text, this.engineSpecific, this.order);
}

class _Query {
  final String? code;
  final Set<String> parts;
  final Set<String> topics;
  final Set<String> groups;
  final List<String> names;

  _Query(this.code, this.parts, this.topics, this.groups, this.names);
}

class InsightEngine {
  final AppData data;
  final Map<String, List<_Candidate>> _byVehicle = {};
  final Map<String, _Query> _queries = {};

  InsightEngine(this.data);

  static final Expando<InsightEngine> _shared = Expando();

  static InsightEngine of(AppData data) => _shared[data] ??= InsightEngine(data);

  static Set<String> topicsInText(String normalized) {
    final padded = ' $normalized';
    return {
      for (final t in insightTopics)
        if (t.keywords.any((k) => padded.contains(' $k'))) t.id
    };
  }

  static Set<String> topicsForParts(Iterable<String> slugs) {
    final specific = slugs.where((p) => !genericInsightParts.contains(p));
    return {
      for (final t in insightTopics)
        if (specific.any(t.parts.contains)) t.id
    };
  }

  /// Words shared by two systems: an AdBlue injector is not a fuel injector,
  /// a CVT chain or a lock-up clutch is not a timing chain or a clutch, a
  /// gearbox overheating is not the engine cooling.
  static Set<String> _refine(Set<String> topics, Iterable<String> parts) {
    bool hasPart(String topic) => insightTopics
        .firstWhere((t) => t.id == topic)
        .parts
        .any(parts.contains);
    void drop(String topic, String when) {
      if (topics.contains(when) && !hasPart(topic)) topics.remove(topic);
    }

    drop('injector', 'scr');
    drop('chain', 'gearbox-auto');
    drop('clutch', 'gearbox-auto');
    drop('cooling', 'gearbox');
    return topics;
  }

  static int _weight(Iterable<String> ids) {
    var w = 0;
    for (final t in insightTopics) {
      if (ids.contains(t.id)) w += t.weight;
    }
    return w;
  }

  static int _maxWeight(Iterable<String> ids) {
    var w = 0;
    for (final t in insightTopics) {
      if (ids.contains(t.id) && t.weight > w) w = t.weight;
    }
    return w;
  }

  static List<String> _labels(Iterable<String> ids) =>
      [for (final t in insightTopics) if (ids.contains(t.id)) t.label];

  Set<String> _groupsOf(Iterable<String> parts) => {
        for (final p in parts) ?data.part(p)?.group.slug,
      };

  List<Insight> forDtc(Dtc dtc, Vehicle? vehicle, {int max = 3}) {
    if (vehicle == null) return const [];
    final q = _queries['dtc:${dtc.code}'] ??= _query(
        dtc.code,
        dtc.parts.toSet(),
        _refine({...topicsForParts(dtc.parts), ...topicsInText(normalize(dtc.title))},
            dtc.parts));
    return _match(vehicle, q, max);
  }

  List<Insight> forPart(String slug, Vehicle? vehicle, {int max = 3}) {
    if (vehicle == null) return const [];
    final q = _queries['part:$slug'] ??= _query(
        null,
        {slug},
        _refine({
          ...topicsForParts([slug]),
          ...topicsInText(normalize(data.part(slug)?.part.name ?? '')),
        }, [slug]));
    return _match(vehicle, q, max);
  }

  _Query _query(String? code, Set<String> parts, Set<String> topics) => _Query(
        code,
        parts,
        topics,
        _groupsOf(parts.where((p) => !genericInsightParts.contains(p))),
        [
          for (final p in parts)
            if (!genericInsightParts.contains(p))
              if (data.part(p)?.part.name case final n? when n.length >= 6)
                ' ${normalize(n)}'
        ],
      );

  /// Weak points of the vehicle's engine sheet and known issues of its model
  /// sheet (already filtered on the engine), computed once per vehicle.
  List<_Candidate> _candidates(Vehicle v) =>
      _byVehicle['${v.id}|${v.code}|${v.dpf}'] ??= () {
        final out = <_Candidate>[];
        final spec = data.engineSpecFor(v);
        if (spec != null) {
          for (final note in spec.notes) {
            final text = normalize(note);
            if (!_problem.hasMatch(text)) continue;
            out.add(_Candidate(
                Insight(source: InsightSource.engine, text: note, score: 0, engine: spec),
                topicsInText(text), const {}, const {}, const {}, ' $text', false, 1));
          }
        }
        final model = data.modelSpecFor(v);
        if (model != null) {
          for (final i in data.issuesFor(v)) {
            out.add(_Candidate(
                Insight(
                    source: InsightSource.model,
                    text: i.title,
                    detail: i.symptoms,
                    score: 0,
                    model: model),
                _refine({
                  ...topicsInText(normalize('${i.title} ${i.symptoms}')),
                  ...topicsForParts(i.parts),
                }, i.parts),
                i.parts.toSet(),
                _groupsOf(i.parts.where((p) => !genericInsightParts.contains(p))),
                i.dtc.toSet(),
                '',
                i.engines.isNotEmpty,
                0));
          }
        }
        return out;
      }();

  /// Scores each candidate against the code or part: same code cited (+6),
  /// same specific part (+3, max 2), shared topics (their weight), same tree
  /// group or generic part (+1), engine-specific issue (+1). A candidate needs
  /// a strong link (code, specific part or one topic of weight >= 2) and 3 points.
  List<Insight> _match(Vehicle vehicle, _Query q, int max) {
    final scored = <(_Candidate, int, Set<String>, int)>[];
    final candidates = _candidates(vehicle);
    for (var index = 0; index < candidates.length; index++) {
      final c = candidates[index];
      final shared = c.topics.intersection(q.topics);
      final topicWeight = _weight(shared);
      var specificParts = 0, genericParts = 0;
      for (final p in c.parts) {
        if (!q.parts.contains(p)) continue;
        genericInsightParts.contains(p) ? genericParts++ : specificParts++;
      }
      final sameCode = q.code != null && c.dtc.contains(q.code);
      final strong = sameCode || specificParts > 0 || _maxWeight(shared) >= 2;
      if (!strong) continue;
      var score = topicWeight + 3 * specificParts.clamp(0, 2);
      if (sameCode) score += 6;
      if (genericParts > 0) score += 1;
      if (specificParts == 0 && c.groups.any(q.groups.contains)) score += 1;
      if (c.text.isNotEmpty && q.names.any(c.text.contains)) score += 1;
      if (c.engineSpecific) score += 1;
      if (score >= 3) scored.add((c, score, shared, index));
    }
    scored.sort((a, b) {
      final s = b.$2.compareTo(a.$2);
      if (s != 0) return s;
      final src = a.$1.order.compareTo(b.$1.order);
      return src != 0 ? src : a.$4.compareTo(b.$4);
    });
    return [
      for (final (c, score, shared, _) in scored.take(max))
        Insight(
            source: c.insight.source,
            text: c.insight.text,
            detail: c.insight.detail,
            score: score,
            topics: _labels(shared),
            engine: c.insight.engine,
            model: c.insight.model)
    ];
  }
}
