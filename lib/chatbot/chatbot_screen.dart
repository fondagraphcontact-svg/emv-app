import 'package:flutter/material.dart';

import 'chatbot_engine.dart';

class _ChatColors {
  static const accent = Color(0xFFFF8A00);
  static const background = Color(0xFF121417);
  static const botBubble = Color(0xFF1C1F24);
  static const userBubble = Color(0xFF3A2A12);
  static const surfaceHigh = Color(0xFF262A31);
  static const muted = Color(0xFFB8BDC5);
  static const warning = Color(0xFFF2C94C);
}

class _ChatMessage {
  final bool fromUser;
  final String text;
  final BotReply? reply;
  const _ChatMessage.user(this.text)
      : fromUser = true,
        reply = null;
  _ChatMessage.bot(BotReply this.reply)
      : fromUser = false,
        text = reply.text;
}

class ChatbotScreen extends StatefulWidget {
  final ChatbotEngine? engine;
  final VehicleCtx? vehicle;
  final void Function(String partSlug) onOpenView;
  final void Function(String code) onOpenDtc;
  final void Function(VehicleEntry vehicle) onSelectVehicle;
  final void Function(String partSlug)? onOpenPart;
  final void Function(String viewId)? onOpenViewId;
  final void Function(String guideId)? onOpenGuide;
  final void Function(String lightId)? onOpenLight;
  final VoidCallback? onOpenPrecheck;
  final Widget? Function(BotReply reply)? replyHeader;
  final bool showAppBar;

  const ChatbotScreen({
    super.key,
    required this.engine,
    required this.onOpenView,
    required this.onOpenDtc,
    required this.onSelectVehicle,
    this.vehicle,
    this.onOpenPart,
    this.onOpenViewId,
    this.onOpenGuide,
    this.onOpenLight,
    this.onOpenPrecheck,
    this.replyHeader,
    this.showAppBar = true,
  });

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[];
  VehicleCtx? _sessionVehicle;

  VehicleCtx? get _ctx => widget.vehicle ?? _sessionVehicle;

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage.bot(const BotReply(
      text: 'Bonjour ! Décrivez un symptôme, un code défaut (ex. P0401), une pièce ou votre véhicule. '
          'Je réponds hors ligne à partir des données de l\'application.',
      suggestions: ChatbotEngine.fallbackSuggestions,
    )));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String raw) {
    final text = raw.trim();
    final engine = widget.engine;
    if (text.isEmpty || engine == null) return;
    final reply = engine.reply(text, ctx: _ctx);
    setState(() {
      _messages.add(_ChatMessage.user(text));
      _messages.add(_ChatMessage.bot(reply));
      if (widget.vehicle == null && reply.ctx?.engine != null && reply.vehicles.isNotEmpty) {
        _sessionVehicle = reply.ctx;
      }
    });
    _input.clear();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  void _onAction(BotAction a) {
    switch (a.type) {
      case BotActionType.openView:
        widget.onOpenView(a.payload);
      case BotActionType.openPart:
        (widget.onOpenPart ?? widget.onOpenView)(a.payload);
      case BotActionType.openDtc:
        widget.onOpenDtc(a.payload);
      case BotActionType.openViewId:
        widget.onOpenViewId?.call(a.payload);
      case BotActionType.openGuide:
        widget.onOpenGuide?.call(a.payload);
      case BotActionType.openLight:
        widget.onOpenLight?.call(a.payload);
      case BotActionType.openPrecheck:
        widget.onOpenPrecheck?.call();
      case BotActionType.selectVehicle:
        final v = a.vehicle;
        if (v == null) return;
        widget.onSelectVehicle(v);
        setState(() {
          _sessionVehicle = VehicleCtx.fromEntry(v);
          _messages.add(_ChatMessage.bot(BotReply(
            text: 'Véhicule choisi : ${_sessionVehicle!.label}. Les réponses sont maintenant adaptées.',
            suggestions: ChatbotEngine.fallbackSuggestions,
          )));
        });
        _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _VehicleBanner(ctx: _ctx),
        Expanded(
          child: widget.engine == null
              ? const Center(child: CircularProgressIndicator(color: _ChatColors.accent))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    return m.fromUser
                        ? _UserBubble(text: m.text)
                        : _BotBubble(
                            reply: m.reply!,
                            onAction: _onAction,
                            onSuggestion: _send,
                            showViewIds: widget.onOpenViewId != null,
                            showGuides: widget.onOpenGuide != null,
                            showLights: widget.onOpenLight != null,
                            showPrecheck: widget.onOpenPrecheck != null,
                            header: widget.replyHeader?.call(m.reply!),
                          );
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Informatif : ne remplace pas le diagnostic d\'un professionnel.',
            style: TextStyle(color: _ChatColors.muted, fontSize: 11),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: widget.engine != null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Ex. « claque au ralenti », « P0401 », « Laguna 3 dCi 150 »',
                      filled: true,
                      fillColor: _ChatColors.surfaceHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Envoyer',
                  style: IconButton.styleFrom(
                      backgroundColor: _ChatColors.accent, foregroundColor: Colors.black),
                  onPressed: widget.engine == null ? null : () => _send(_input.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    if (!widget.showAppBar) return ColoredBox(color: _ChatColors.background, child: body);
    return Scaffold(
      backgroundColor: _ChatColors.background,
      appBar: AppBar(title: const Text('Assistant')),
      body: body,
    );
  }
}

class _VehicleBanner extends StatelessWidget {
  final VehicleCtx? ctx;
  const _VehicleBanner({required this.ctx});

  @override
  Widget build(BuildContext context) {
    final label = ctx == null ? 'Aucun véhicule choisi : réponses générales' : ctx!.label;
    return Container(
      width: double.infinity,
      color: _ChatColors.botBubble,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(ctx?.effectiveKind == 'moto' ? Icons.two_wheeler : Icons.directions_car,
              size: 18, color: ctx == null ? _ChatColors.muted : _ChatColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _ChatColors.muted, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 6, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: _ChatColors.userBubble,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _BotBubble extends StatelessWidget {
  final BotReply reply;
  final void Function(BotAction) onAction;
  final void Function(String) onSuggestion;
  final bool showViewIds;
  final bool showGuides;
  final bool showLights;
  final bool showPrecheck;
  final Widget? header;

  const _BotBubble({
    required this.reply,
    required this.onAction,
    required this.onSuggestion,
    required this.showViewIds,
    this.showGuides = false,
    this.showLights = false,
    this.showPrecheck = false,
    this.header,
  });

  static IconData _icon(BotActionType t) => switch (t) {
        BotActionType.openView => Icons.view_in_ar,
        BotActionType.openViewId => Icons.electrical_services,
        BotActionType.openDtc => Icons.error_outline,
        BotActionType.openPart => Icons.build_outlined,
        BotActionType.selectVehicle => Icons.directions_car,
        BotActionType.openGuide => Icons.checklist,
        BotActionType.openLight => Icons.dashboard_outlined,
        BotActionType.openPrecheck => Icons.verified_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final actions = reply.actions
        .where((a) => showViewIds || a.type != BotActionType.openViewId)
        .where((a) => showGuides || a.type != BotActionType.openGuide)
        .where((a) => showLights || a.type != BotActionType.openLight)
        .where((a) => showPrecheck || a.type != BotActionType.openPrecheck)
        .toList();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 6, right: 24),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _ChatColors.botBubble,
          border: Border(left: BorderSide(color: _ChatColors.accent.withValues(alpha: 0.8), width: 3)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null) ...[header!, const SizedBox(height: 8)],
            Text(reply.text, style: const TextStyle(color: Colors.white, height: 1.35)),
            if (reply.checks.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('À contrôler, dans l\'ordre :',
                  style: TextStyle(color: _ChatColors.accent, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (var i = 0; i < reply.checks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${i + 1}.',
                            style: const TextStyle(color: _ChatColors.accent, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(child: Text(reply.checks[i], style: const TextStyle(color: _ChatColors.muted))),
                    ],
                  ),
                ),
            ],
            if (reply.safety != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: _ChatColors.warning, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(reply.safety!,
                          style: const TextStyle(color: _ChatColors.warning, fontSize: 13))),
                ],
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in actions)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _ChatColors.accent,
                        side: const BorderSide(color: _ChatColors.accent),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => onAction(a),
                      icon: Icon(_icon(a.type), size: 16),
                      label: Text(a.label, style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ],
            if (reply.suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in reply.suggestions)
                    ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      backgroundColor: _ChatColors.surfaceHigh,
                      side: BorderSide.none,
                      onPressed: () => onSuggestion(s),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
