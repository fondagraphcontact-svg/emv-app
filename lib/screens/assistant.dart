import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chatbot/chatbot_assets.dart';
import '../chatbot/chatbot_engine.dart';
import '../chatbot/chatbot_screen.dart';
import '../insights/urgency.dart';
import '../lights/light_screen.dart';
import '../models.dart';
import '../precheck/precheck_screen.dart';
import '../state.dart';
import 'faults.dart';

VehicleCtx? vehicleCtxFrom(Vehicle? v) => v == null
    ? null
    : VehicleCtx(
        fuel: v.fuel,
        family: v.family,
        dpf: v.dpf,
        make: v.make,
        model: v.model,
        engine: v.engine,
        kind: v.kind == VehicleKind.both ? null : v.kind.name,
      );

Vehicle vehicleFromEntry(VehicleEntry v) => Vehicle(
      make: v.make,
      model: v.model,
      engine: v.engine,
      fuel: v.fuel,
      family: v.family,
      code: v.code ?? '',
      kind: parseKind(v.kind),
      yearFrom: v.yearFrom,
      yearTo: v.yearTo,
      dpf: v.dpf,
    );

Future<ChatbotEngine>? _sharedEngine;
ChatbotEngine? _loadedEngine;

/// Loaded once per app run; the assistant tab reuses it after rebuilds.
Future<ChatbotEngine> sharedChatbotEngine() => _sharedEngine ??=
    loadChatbotEngine().then((e) => _loadedEngine = e);

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  ChatbotEngine? _engine = _loadedEngine;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (_engine != null) return;
    sharedChatbotEngine().then(
      (e) {
        if (mounted) setState(() => _engine = e);
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Assistant')),
        body: Center(child: Text('Assistant indisponible :\n$_error')),
      );
    }
    final state = context.watch<AppState>();
    return ChatbotScreen(
      engine: _engine,
      vehicle: vehicleCtxFrom(state.current),
      onOpenView: (slug) => state.showPartsInView([slug]),
      onOpenPart: (slug) => state.showPartsInView([slug]),
      onOpenViewId: (id) {
        if (state.data.view(id) == null) return;
        state.openView(id);
        state.selectTab(AppTab.views);
      },
      onOpenDtc: (code) {
        final dtc = state.data.dtc(code);
        if (dtc != null) Navigator.of(context).push(DtcScreen.route(dtc));
      },
      onOpenGuide: (id) => openGuideById(context, id),
      onOpenLight: (id) => openLightById(context, id),
      onOpenPrecheck: () => openPrecheck(context),
      replyHeader: (reply) {
        final dtc = reply.dtcCode == null ? null : state.data.dtc(reply.dtcCode!);
        return dtc == null ? null : UrgencyBadge(dtc: dtc, compact: true);
      },
      onSelectVehicle: (v) => state.setVehicle(vehicleFromEntry(v)),
    );
  }
}
