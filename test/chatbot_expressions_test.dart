import 'dart:convert';
import 'dart:io';

import 'package:emv/chatbot/chatbot_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final kb = jsonDecode(File('assets/data/chatbot_kb.json').readAsStringSync()) as List<dynamic>;
  final tree = jsonDecode(File('assets/data/tree.json').readAsStringSync()) as List<dynamic>;
  final engine = ChatbotEngine.fromJson(kb: kb, tree: tree);

  test('expressions courantes des clients en atelier', () {
    const cases = {
      'ça sent le brûlé': 'burning-smell',
      'odeur de brûlé en roulant': 'burning-smell',
      'ça broute': 'hesitation-jerks',
      "ça tousse à l'accélération": 'hesitation-jerks',
      'ça tape dans le moteur': 'knock-idle',
      'ça tape sur les bosses': 'suspension-noise',
      "ça cogne à l'avant": 'suspension-noise',
      'ça tire à droite': 'pulls-to-side',
      'ça tire à gauche quand je freine': 'brake-pulls',
      'ça patine en côte': 'clutch-slipping',
      'voyant orange allumé': 'warning-light-colors',
      'voyant moteur orange': 'check-engine-light',
      'ça ronfle en roulant': 'wheel-bearing',
      'les vitesses craquent': 'gear-grinding',
      'ça couine au freinage': 'brake-squeal',
    };
    cases.forEach((q, id) => expect(engine.reply(q).intentId, id, reason: q));
  });

  test('odeur de brûlé : consigne de sécurité incendie', () {
    final r = engine.reply('ça sent le brûlé');
    expect(r.safety, contains('112'));
  });
}
