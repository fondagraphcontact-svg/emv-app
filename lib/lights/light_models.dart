import 'dart:convert';

import 'package:flutter/material.dart';

import '../data.dart';
import '../models.dart';

const lightCategories = {
  'moteur': 'Moteur',
  'freinage': 'Freinage',
  'securite': 'Sécurité',
  'electrique': 'Électrique',
  'confort': 'Confort',
  'hybride-ev': 'Hybride / électrique',
  'moto': 'Moto / scooter',
};

const lightColorNames = {
  'rouge': 'Rouge',
  'orange': 'Orange',
  'vert': 'Vert',
  'bleu': 'Bleu',
};

Color lightColor(String color) => switch (color) {
      'rouge' => const Color(0xFFE5484D),
      'orange' => const Color(0xFFFF8A00),
      'vert' => const Color(0xFF3DBE6B),
      _ => const Color(0xFF4C8DFF),
    };

const urgencyLabels = {
  1: 'Peut rouler',
  2: 'Garage sous peu',
  3: 'Arrêt immédiat',
};

class DashboardLight {
  final String id;
  final String name;
  final String category;
  final String color;
  final int urgency;
  final VehicleKind kind;
  final List<String> fuel;
  final List<String> keywords;
  final String meaning;
  final List<String> now;
  final List<String> causes;
  final List<String> dtc;
  final List<String> parts;
  final List<String> guides;
  final List<String> intents;
  final String _search;

  DashboardLight({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.urgency,
    required this.kind,
    required this.fuel,
    this.keywords = const [],
    this.meaning = '',
    this.now = const [],
    this.causes = const [],
    this.dtc = const [],
    this.parts = const [],
    this.guides = const [],
    this.intents = const [],
  }) : _search = normalize([name, ...keywords, meaning].join(' '));

  factory DashboardLight.fromJson(Map<String, dynamic> j) {
    List<String> list(String k) =>
        [for (final v in (j[k] as List? ?? const [])) '$v'];
    return DashboardLight(
      id: j['id'] as String,
      name: j['name'] as String,
      category: j['category'] as String,
      color: j['color'] as String,
      urgency: (j['urgency'] as num).toInt().clamp(1, 3),
      kind: parseKind(j['kind'] as String?),
      fuel: list('fuel'),
      keywords: list('keywords'),
      meaning: j['meaning'] as String? ?? '',
      now: list('now'),
      causes: list('causes'),
      dtc: list('dtc'),
      parts: list('parts'),
      guides: list('guides'),
      intents: list('intents'),
    );
  }

  String get iconAsset => 'assets/lights/$id.svg';

  /// Moto lights only for motorcycles; diesel hybrids count as diesel.
  bool appliesTo(Vehicle v) {
    if (kind != VehicleKind.both &&
        v.kind != VehicleKind.both &&
        kind != v.kind) {
      return false;
    }
    if (fuel.contains(v.fuel)) return true;
    return v.isDiesel && fuel.contains('diesel');
  }

  bool matches(String query) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    return q.split(' ').every(_search.contains);
  }
}

List<DashboardLight> parseLights(String raw) => [
      for (final j in jsonDecode(raw) as List)
        DashboardLight.fromJson(j as Map<String, dynamic>),
    ];
