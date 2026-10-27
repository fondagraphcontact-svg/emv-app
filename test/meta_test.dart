import 'dart:convert';
import 'dart:io';

import 'package:emv/screens/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('meta.json : data_version et changelog lisibles par l\'écran À propos', () {
    final j = jsonDecode(File('assets/data/meta.json').readAsStringSync()) as Map<String, dynamic>;
    final meta = DataMeta.fromJson(j);
    expect(meta.version, matches(RegExp(r'^\d{4}\.\d{2}\.\d{2}$')));
    expect(meta.changes, isNotEmpty);
    expect(meta.changes.every((c) => c.trim().isNotEmpty), isTrue);
  });
}
