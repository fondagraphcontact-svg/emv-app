import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../expenses/expenses_screen.dart';
import '../models.dart';
import '../precheck/precheck_screen.dart';
import '../state.dart';
import '../theme.dart';
import 'maintenance_entry.dart';
import 'reminders.dart';

/// Ouvre le carnet du véhicule courant, ou explique qu'il faut en choisir un.
void openMaintenance(BuildContext context, [Vehicle? vehicle]) {
  final v = vehicle ?? context.read<AppState>().current;
  if (v == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choisissez d\'abord un véhicule (onglet Véhicule).')));
    return;
  }
  Navigator.of(context).push(MaintenanceScreen.route(v));
}

class MaintenanceScreen extends StatelessWidget {
  final Vehicle vehicle;

  const MaintenanceScreen({super.key, required this.vehicle});

  static Route<void> route(Vehicle v) =>
      MaterialPageRoute(builder: (_) => MaintenanceScreen(vehicle: v));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.maintenanceFor(vehicle.id);
    final km = state.odometer(vehicle.id);
    final due = state.dueKmReminders(vehicle.id);
    final upcoming = [
      for (final e in entries)
        if (e.hasReminder && !due.contains(e)) e
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Carnet d\'entretien'), actions: [
        IconButton(
          key: const Key('maintenance-expenses'),
          tooltip: 'Dépenses',
          icon: const Icon(Icons.euro),
          onPressed: () =>
              Navigator.of(context).push(ExpensesScreen.route(vehicle)),
        ),
        IconButton(
          key: const Key('maintenance-precheck'),
          tooltip: 'Pré-contrôle technique',
          icon: const Icon(Icons.verified_outlined),
          onPressed: () => openPrecheck(context, vehicle),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('maintenance-add'),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
        onPressed: () => Navigator.of(context)
            .push(MaintenanceFormScreen.route(vehicle)),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        ListTile(
          leading: const Icon(Icons.garage, color: EmvColors.accent),
          title: Text(vehicle.title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(vehicle.subtitle),
        ),
        ListTile(
          key: const Key('odometer'),
          leading: const Icon(Icons.speed),
          title: Text(km == null ? 'Kilométrage non renseigné' : formatKm(km)),
          subtitle: const Text('Kilométrage actuel · touchez pour modifier'),
          onTap: () => _editOdometer(context, km),
        ),
        if (due.isNotEmpty) ...[
          const _Title('Échéances atteintes'),
          for (final e in due)
            _EntryTile(entry: e, vehicle: vehicle, highlight: true),
        ],
        if (upcoming.isNotEmpty) ...[
          const _Title('Rappels à venir'),
          for (final e in upcoming) _EntryTile(entry: e, vehicle: vehicle),
        ],
        const _Title('Historique'),
        if (entries.isEmpty)
          const ListTile(
            title: Text('Aucune intervention enregistrée'),
            subtitle: Text('Vidange, plaquettes, courroie… ajoutez vos '
                'interventions pour garder un historique.'),
          ),
        for (final e in entries) _EntryTile(entry: e, vehicle: vehicle),
      ]),
    );
  }

  Future<void> _editOdometer(BuildContext context, int? current) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: current?.toString() ?? '');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kilométrage actuel'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'km'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(int.tryParse(controller.text)),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final before = state.dueKmReminders(vehicle.id).toSet();
    await state.setOdometer(vehicle.id, value);
    for (final e in state.dueKmReminders(vehicle.id)) {
      if (!before.contains(e)) await ReminderScheduler.instance.notifyKmDue(e);
    }
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

String reminderLabel(MaintenanceEntry e) => [
      if (e.reminderDate != null) 'le ${formatDate(e.reminderDate!)}',
      if (e.reminderKm != null) 'à ${formatKm(e.reminderKm!)}',
    ].join(' ou ');

class _EntryTile extends StatelessWidget {
  final MaintenanceEntry entry;
  final Vehicle vehicle;
  final bool highlight;

  const _EntryTile(
      {required this.entry, required this.vehicle, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final details = [
      formatDate(entry.date),
      if (entry.km != null) formatKm(entry.km!),
      if (entry.cost != null) formatCost(entry.cost!),
    ].join(' · ');
    return ListTile(
      leading: Icon(
          highlight ? Icons.notification_important : Icons.build_circle_outlined,
          color: highlight ? EmvColors.accent : null),
      title: Text(entry.title),
      subtitle: Text([
        details,
        if (entry.parts.isNotEmpty) entry.parts.join(', '),
        if (entry.hasReminder) 'Rappel ${reminderLabel(entry)}',
      ].join('\n')),
      isThreeLine: entry.parts.isNotEmpty || entry.hasReminder,
      onTap: () => Navigator.of(context)
          .push(MaintenanceFormScreen.route(vehicle, entry: entry)),
    );
  }
}

class MaintenanceFormScreen extends StatefulWidget {
  final Vehicle vehicle;
  final MaintenanceEntry? entry;

  const MaintenanceFormScreen({super.key, required this.vehicle, this.entry});

  static Route<void> route(Vehicle v, {MaintenanceEntry? entry}) =>
      MaterialPageRoute(
          builder: (_) => MaintenanceFormScreen(vehicle: v, entry: entry));

  @override
  State<MaintenanceFormScreen> createState() => _MaintenanceFormScreenState();
}

class _MaintenanceFormScreenState extends State<MaintenanceFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.entry?.title);
  late final _km =
      TextEditingController(text: widget.entry?.km?.toString() ?? '');
  late final _parts =
      TextEditingController(text: widget.entry?.parts.join(', ') ?? '');
  late final _cost = TextEditingController(
      text: widget.entry?.cost?.toString().replaceAll('.', ',') ?? '');
  late final _note = TextEditingController(text: widget.entry?.note);
  late final _reminderKm =
      TextEditingController(text: widget.entry?.reminderKm?.toString() ?? '');
  late DateTime _date = widget.entry?.date ?? _today();
  late DateTime? _reminderDate = widget.entry?.reminderDate;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    for (final c in [_title, _km, _parts, _cost, _note, _reminderKm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1980),
        lastDate: DateTime(2100),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final scheduler = ReminderScheduler.instance;
    final entry = MaintenanceEntry(
      id: widget.entry?.id ??
          DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      vehicleKey: widget.vehicle.id,
      date: _date,
      km: int.tryParse(_km.text),
      title: _title.text.trim(),
      parts: [
        for (final p in _parts.text.split(','))
          if (p.trim().isNotEmpty) p.trim()
      ],
      cost: double.tryParse(_cost.text.replaceAll(',', '.').trim()),
      note: _note.text.trim(),
      reminderDate: _reminderDate,
      reminderKm: int.tryParse(_reminderKm.text),
    );
    await state.saveMaintenance(entry);
    if (entry.reminderDate != null && scheduler.supported) {
      if (await scheduler.requestPermission()) {
        await scheduler.sync(entry);
      } else {
        messenger.showSnackBar(const SnackBar(
            content: Text('Notifications refusées : le rappel reste visible '
                'dans le carnet.')));
      }
    } else if (widget.entry?.reminderDate != null) {
      await scheduler.cancel(entry);
    }
    offerLinkedExpense(
        messenger: messenger,
        navigator: navigator,
        prefs: state.prefs,
        vehicle: widget.vehicle,
        entry: entry);
    navigator.pop();
  }

  Future<void> _delete() async {
    final entry = widget.entry!;
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette intervention ?'),
        content: Text(entry.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await ReminderScheduler.instance.cancel(entry);
    await state.deleteMaintenance(entry.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'Nouvelle intervention' : 'Intervention'),
        actions: [
          if (widget.entry != null)
            IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            key: const Key('maintenance-title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Intervention *', hintText: 'Vidange + filtre à huile'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Indiquez l\'intervention' : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: InkWell(
                  onTap: () async {
                    final d = await _pick(_date);
                    if (d != null) setState(() => _date = d);
                  },
                  child: Text(formatDate(_date)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('maintenance-km'),
                controller: _km,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(
                    labelText: 'Kilométrage', suffixText: 'km'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _parts,
            decoration: const InputDecoration(
                labelText: 'Pièces', hintText: 'Séparées par des virgules'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('maintenance-cost'),
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration:
                const InputDecoration(labelText: 'Coût', suffixText: '€'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 20),
          Text('Rappel (prochaine échéance)',
              style: Theme.of(context).textTheme.titleMedium),
          if (!ReminderScheduler.instance.supported)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'Notifications indisponibles ici : le rappel sera affiché '
                  'dans le carnet.',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date',
                  suffixIcon: _reminderDate == null
                      ? null
                      : IconButton(
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _reminderDate = null)),
                ),
                child: InkWell(
                  onTap: () async {
                    final d = await _pick(_reminderDate ??
                        DateTime(_date.year + 1, _date.month, _date.day));
                    if (d != null) setState(() => _reminderDate = d);
                  },
                  child: Text(_reminderDate == null
                      ? 'Aucune'
                      : formatDate(_reminderDate!)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('maintenance-reminder-km'),
                controller: _reminderKm,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(
                    labelText: 'ou à', suffixText: 'km'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('maintenance-save'),
            icon: const Icon(Icons.save),
            label: const Text('Enregistrer'),
            onPressed: _save,
          ),
        ]),
      ),
    );
  }
}
