import 'package:flutter/services.dart';

import 'chatbot_engine.dart';

Future<ChatbotEngine> loadChatbotEngine([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  Future<String?> read(String name) async {
    try {
      return await b.loadString('assets/data/$name');
    } catch (_) {
      return null;
    }
  }

  final engine = ChatbotEngine.fromJsonStrings(
    kb: await b.loadString('assets/data/chatbot_kb.json'),
    tree: await read('tree.json'),
    dtc: await read('dtc.json'),
    vehicles: await read('vehicles.json'),
  );
  final lights = await read('dashboard_lights.json');
  if (lights != null) {
    engine.lightsByIntent = ChatbotEngine.lightsByIntentFromJson(lights);
  }
  return engine;
}
