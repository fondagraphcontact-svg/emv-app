import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../maintenance/maintenance_entry.dart' show formatDate, formatKm;
import '../models.dart';
import '../screens/faults.dart' show DtcCodeBadge, DtcScreen;
import '../state.dart';
import '../theme.dart';
import 'code_entry.dart';
import 'code_log_store.dart';

CodeLogStore codeLogOf(BuildContext context) =>
    CodeLogStore.of(context.read<AppState>().prefs);

/// Ouvre le journal du véhicule courant, ou explique qu'il faut en choisir un.
void openCodeLog(BuildContext context, [Vehicle? vehicle]) {
  final v = vehicle ?? context.read<AppState>().current;
  if (v == null) {
    _needVehicle(context);
    return;
  }
  Navigator.of(context).push(CodeLogScreen.route(v));
}

void _needVehicle(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choisissez d\'abord un véhicule (onglet Véhicule).')));

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^0-9A-Z]'), '');
    final capped = text.length > 5 ? text.substring(0, 5) : text;
    return TextEditingValue(
        text: capped,
        selection: TextSelection.collapsed(offset: capped.length));
  }
}

/// Tuile d'accès depuis l'onglet Diagnostic.
class CodeLogTile extends StatelessWidget {
  const CodeLogTile({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final v = state.current;
    final store = CodeLogStore.of(state.prefs);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final open = v == null ? 0 : store.openFor(v.id).length;
        final all = v == null ? 0 : store.entriesFor(v.id).length;
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: ListTile(
            key: const Key('codelog-tile'),
            leading: const Icon(Icons.fact_check_outlined,
                color: EmvColors.accent),
            title: const Text('Mes codes relevés'),
            subtitle: Text(v == null
                ? 'Choisissez un véhicule pour noter les codes lus'
                : all == 0
                    ? 'Notez les codes lus au garage ou à la valise'
                    : '$open ouvert(s) · ${all - open} résolu(s)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openCodeLog(context),
          ),
        );
      },
    );
  }
}

class CodeLogScreen extends StatelessWidget {
  final Vehicle vehicle;

  const CodeLogScreen({super.key, required this.vehicle});

  static Route<void> route(Vehicle v) =>
      MaterialPageRoute(builder: (_) => CodeLogScreen(vehicle: v));

  @override
  Widget build(BuildContext context) {
    final store = codeLogOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes codes relevés')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final open = store.openFor(vehicle.id);
          final resolved = store.resolvedFor(vehicle.id);
          return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                ListTile(
                  leading: const Icon(Icons.garage, color: EmvColors.accent),
                  title: Text(vehicle.title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(vehicle.subtitle),
                ),
                QuickAddCode(vehicle: vehicle),
                _Title('Ouverts (${open.length})'),
                if (open.isEmpty)
                  const ListTile(
                    title: Text('Aucun code ouvert',
                        style: TextStyle(color: Colors.white60)),
                  ),
                for (final e in open) _EntryTile(entry: e),
                _Title('Résolus (${resolved.length})'),
                if (resolved.isEmpty)
                  const ListTile(
                    title: Text('Aucun code résolu',
                        style: TextStyle(color: Colors.white60)),
                  ),
                for (final e in resolved) _EntryTile(entry: e),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    'Codes saisis à la main, conservés uniquement sur cet '
                    'appareil. Un code effacé peut revenir si la cause reste.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ]);
        },
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;

  const _Title(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: EmvColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1)),
      );
}

/// Formulaire d'ajout rapide : code avec autocomplétion, km, note, date.
class QuickAddCode extends StatefulWidget {
  final Vehicle vehicle;

  const QuickAddCode({super.key, required this.vehicle});

  @override
  State<QuickAddCode> createState() => _QuickAddCodeState();
}

class _QuickAddCodeState extends State<QuickAddCode> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _km = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = _today();

  @override
  void initState() {
    super.initState();
    final km = context.read<AppState>().odometer(widget.vehicle.id);
    if (km != null) _km.text = km.toString();
  }

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    _km.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final entry = await codeLogOf(context).add(
      vehicleKey: widget.vehicle.id,
      code: _code.text,
      date: _date,
      km: int.tryParse(_km.text),
      note: _note.text,
    );
    if (!mounted) return;
    _code.clear();
    _note.clear();
    _codeFocus.unfocus();
    messenger.showSnackBar(
        SnackBar(content: Text('${entry.code} ajouté à vos codes relevés')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final data = state.data;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RawAutocomplete<Dtc>(
              textEditingController: _code,
              focusNode: _codeFocus,
              optionsBuilder: (value) {
                final q = normalizeCode(value.text);
                if (q.isEmpty) return const Iterable<Dtc>.empty();
                return data.searchDtc(q, vehicle: widget.vehicle, limit: 8);
              },
              displayStringForOption: (d) => d.code,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                  TextFormField(
                key: const Key('codelog-code'),
                controller: controller,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_CodeFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Code défaut',
                  hintText: 'P0301, U0100…',
                  prefixIcon: Icon(Icons.qr_code_2),
                ),
                validator: (v) => codeFormatError(v ?? ''),
                onFieldSubmitted: (_) => onSubmit(),
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: EmvColors.surfaceHigh,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 260, maxWidth: 420),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final d in options)
                          ListTile(
                            key: Key('codelog-option-${d.code}'),
                            dense: true,
                            title: Text(d.code,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(d.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => onSelected(d),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: _code,
              builder: (context, _) {
                final code = normalizeCode(_code.text);
                if (codeFormatError(code) != null) {
                  return const SizedBox.shrink();
                }
                final dtc = data.dtc(code);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    dtc?.title ??
                        'Code non répertorié dans EMV (souvent spécifique '
                            'au constructeur) : il sera noté tel quel.',
                    style: TextStyle(
                        color: dtc == null ? Colors.white60 : EmvColors.label,
                        fontSize: 13),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  key: const Key('codelog-km'),
                  controller: _km,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Km (optionnel)', suffixText: 'km'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                key: const Key('codelog-date'),
                icon: const Icon(Icons.event, size: 18),
                label: Text(formatDate(_date)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(1980),
                    lastDate: _today(),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('codelog-note'),
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Note (optionnel)',
                  hintText: 'Lu au garage, voyant allumé à froid…'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('codelog-add'),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter le code'),
              onPressed: _add,
            ),
          ]),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final CodeLogEntry entry;

  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final dtc = state.data.dtc(entry.code);
    final store = codeLogOf(context);
    final details = [
      'Relevé le ${formatDate(entry.date)}',
      if (entry.km != null) formatKm(entry.km!),
      if (entry.resolvedAt != null) 'résolu le ${formatDate(entry.resolvedAt!)}',
    ].join(' · ');
    return ListTile(
      key: Key('codelog-entry-${entry.id}'),
      leading: dtc == null
          ? SizedBox(
              width: 64,
              child: Text(entry.code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700)))
          : DtcCodeBadge(dtc: dtc),
      title: Text(dtc?.title ?? 'Code non répertorié'),
      subtitle: Text([details, if (entry.note.isNotEmpty) entry.note].join('\n')),
      isThreeLine: entry.note.isNotEmpty,
      onTap: dtc == null
          ? null
          : () => Navigator.of(context).push(DtcScreen.route(dtc)),
      trailing: PopupMenuButton<String>(
        key: Key('codelog-menu-${entry.id}'),
        tooltip: 'Actions',
        onSelected: (action) async {
          switch (action) {
            case 'resolve':
              await store.markResolved(entry.id);
            case 'reopen':
              await store.reopen(entry.id);
            case 'open':
              if (dtc != null && context.mounted) {
                await Navigator.of(context).push(DtcScreen.route(dtc));
              }
            case 'delete':
              if (context.mounted && await _confirmDelete(context)) {
                await store.delete(entry.id);
              }
          }
        },
        itemBuilder: (_) => [
          if (entry.isOpen)
            const PopupMenuItem(
                key: Key('codelog-resolve'),
                value: 'resolve',
                child: Text('Marquer résolu'))
          else
            const PopupMenuItem(
                key: Key('codelog-reopen'),
                value: 'reopen',
                child: Text('Rouvrir')),
          if (dtc != null)
            const PopupMenuItem(value: 'open', child: Text('Voir la fiche')),
          const PopupMenuItem(
              key: Key('codelog-delete'),
              value: 'delete',
              child: Text('Supprimer')),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Supprimer ${entry.code} ?'),
          content: const Text('Le code sera retiré de votre journal.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler')),
            FilledButton(
                key: const Key('codelog-delete-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Supprimer')),
          ],
        ),
      ) ??
      false;
}

/// Bouton de la fiche DTC : note le code pour le véhicule courant.
class AddToCodeLogButton extends StatelessWidget {
  final String code;

  const AddToCodeLogButton({super.key, required this.code});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: const Key('codelog-add-from-dtc'),
        icon: const Icon(Icons.playlist_add),
        label: const Text('Ajouter à mes codes'),
        onPressed: () => addCodeToLog(context, code),
      );
}

Future<void> addCodeToLog(BuildContext context, String code) async {
  final state = context.read<AppState>();
  final v = state.current;
  if (v == null) {
    _needVehicle(context);
    return;
  }
  final result = await showDialog<(int?, String)>(
    context: context,
    builder: (_) =>
        _AddCodeDialog(code: code, vehicle: v, km: state.odometer(v.id)),
  );
  if (result == null) return;
  final (kmValue, noteValue) = result;
  await CodeLogStore.of(state.prefs).add(
    vehicleKey: v.id,
    code: code,
    date: _today(),
    km: kmValue,
    note: noteValue,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$code ajouté à vos codes relevés'),
      action: SnackBarAction(
          label: 'Voir',
          onPressed: () {
            if (context.mounted) openCodeLog(context, v);
          }),
    ));
  }
}

class _AddCodeDialog extends StatefulWidget {
  final String code;
  final Vehicle vehicle;
  final int? km;

  const _AddCodeDialog({required this.code, required this.vehicle, this.km});

  @override
  State<_AddCodeDialog> createState() => _AddCodeDialogState();
}

class _AddCodeDialogState extends State<_AddCodeDialog> {
  late final _km = TextEditingController(text: widget.km?.toString());
  final _note = TextEditingController();

  @override
  void dispose() {
    _km.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Ajouter ${widget.code} à mes codes'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.vehicle.title,
              style: const TextStyle(color: Colors.white60)),
          TextField(
            key: const Key('codelog-dialog-km'),
            controller: _km,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Km (optionnel)', suffixText: 'km'),
          ),
          TextField(
            key: const Key('codelog-dialog-note'),
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optionnel)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler')),
          FilledButton(
              key: const Key('codelog-dialog-save'),
              onPressed: () => Navigator.of(context)
                  .pop((int.tryParse(_km.text), _note.text)),
              child: const Text('Ajouter')),
        ],
      );
}
