import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../maintenance/maintenance_entry.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import 'expense.dart';
import 'expense_csv.dart';
import 'expense_store.dart';

/// Ouvre les dépenses du véhicule courant, ou explique qu'il faut en choisir un.
void openExpenses(BuildContext context, [Vehicle? vehicle]) {
  final v = vehicle ?? context.read<AppState>().current;
  if (v == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choisissez d\'abord un véhicule (onglet Véhicule).')));
    return;
  }
  Navigator.of(context).push(ExpensesScreen.route(v));
}

/// Après l'enregistrement d'une intervention chiffrée : propose de créer
/// (ou de mettre à jour) la dépense liée, sans bloquer le retour au carnet.
void offerLinkedExpense({
  required ScaffoldMessengerState messenger,
  required NavigatorState navigator,
  required SharedPreferences prefs,
  required Vehicle vehicle,
  required MaintenanceEntry entry,
}) {
  final cost = entry.cost;
  if (cost == null || cost <= 0) return;
  final cents = (cost * 100).round();
  final store = ExpenseStore.of(prefs);
  final linked = store.linkedTo(entry.id);
  if (linked != null && linked.cents == cents) return;
  messenger.showSnackBar(SnackBar(
    key: const Key('expense-offer'),
    content: Text(linked == null
        ? 'Ajouter ${formatEuros(cents)} à vos dépenses ?'
        : 'Mettre à jour la dépense liée (${formatEuros(cents)}) ?'),
    action: SnackBarAction(
      label: linked == null ? 'Ajouter' : 'Mettre à jour',
      onPressed: () {
        if (linked != null) {
          store.save(linked.copyWith(cents: cents, date: entry.date, km: entry.km));
          return;
        }
        navigator.push(ExpenseFormScreen.route(vehicle,
            draft: Expense(
              id: ExpenseStore.newId(),
              vehicleId: vehicle.id,
              date: entry.date,
              category: guessCategory(entry.title),
              cents: cents,
              km: entry.km,
              label: entry.title,
              maintenanceId: entry.id,
            )));
      },
    ),
  ));
}

String _fileName(DateTime n) =>
    'emv-depenses-${n.year}${n.month.toString().padLeft(2, '0')}'
    '${n.day.toString().padLeft(2, '0')}.csv';

class ExpensesScreen extends StatefulWidget {
  final Vehicle vehicle;

  const ExpensesScreen({super.key, required this.vehicle});

  static Route<void> route(Vehicle v) =>
      MaterialPageRoute(builder: (_) => ExpensesScreen(vehicle: v));

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  ExpensePeriod _period = ExpensePeriod.last12Months;

  Map<String, String> _maintenanceTitles(AppState state) => {
        for (final m in state.maintenanceFor(widget.vehicle.id)) m.id: m.title
      };

  Future<void> _export(List<Expense> list) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    if (list.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Aucune dépense à exporter.')));
      return;
    }
    final csv = expensesCsv(list,
        vehicleTitle: widget.vehicle.title,
        maintenanceTitles: _maintenanceTitles(state));
    final name = _fileName(DateTime.now());
    try {
      // Sur le web, share_plus télécharge le fichier si le partage échoue.
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(csvBytes(csv), mimeType: 'text/csv')],
        fileNameOverrides: [name],
        subject: 'Dépenses ${widget.vehicle.title}',
        downloadFallbackEnabled: true,
      ));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      messenger.showSnackBar(const SnackBar(
          content: Text('Partage indisponible : CSV copié dans le '
              'presse-papiers.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = ExpenseStore.of(state.prefs);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = store.entriesFor(widget.vehicle.id);
        final list = inPeriod(all, _period, DateTime.now());
        final summary = ExpenseSummary.of(list);
        final titles = _maintenanceTitles(state);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Dépenses'),
            actions: [
              IconButton(
                key: const Key('expenses-export'),
                tooltip: 'Exporter en CSV (${_period.label.toLowerCase()})',
                icon: const Icon(Icons.file_download_outlined),
                onPressed: () => _export(list),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('expenses-add'),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter'),
            onPressed: () => Navigator.of(context)
                .push(ExpenseFormScreen.route(widget.vehicle)),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            ListTile(
              leading: const Icon(Icons.garage, color: EmvColors.accent),
              title: Text(widget.vehicle.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(widget.vehicle.subtitle),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<ExpensePeriod>(
                key: const Key('expenses-period'),
                showSelectedIcon: false,
                segments: [
                  for (final p in ExpensePeriod.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
            _SummaryCard(summary: summary),
            const _Title('Détail'),
            if (list.isEmpty)
              ListTile(
                title: Text(all.isEmpty
                    ? 'Aucune dépense enregistrée'
                    : 'Aucune dépense sur cette période'),
                subtitle: const Text('Carburant, pièces, contrôle technique… '
                    'notez vos dépenses pour suivre le coût du véhicule.'),
              ),
            for (final e in list)
              _ExpenseTile(
                expense: e,
                maintenanceTitle:
                    e.maintenanceId == null ? null : titles[e.maintenanceId],
                onTap: () => Navigator.of(context)
                    .push(ExpenseFormScreen.route(widget.vehicle, expense: e)),
              ),
          ]),
        );
      },
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

class _SummaryCard extends StatelessWidget {
  final ExpenseSummary summary;

  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final perKm = summary.costPerKm;
    final ranked = summary.ranked;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total', style: TextStyle(color: Colors.white70)),
          Text(formatEuros(summary.totalCents),
              key: const Key('expenses-total'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          if (perKm != null)
            Text(
                'Environ ${formatCostPerKm(perKm)} · indicatif, '
                '${summary.distanceKm} km entre le premier et le dernier '
                'relevé saisi',
                key: const Key('expenses-per-km'),
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          if (ranked.isNotEmpty) ...[
            const SizedBox(height: 12),
            CategoryBars(data: ranked, total: summary.totalCents),
          ],
        ]),
      ),
    );
  }
}

/// Une barre horizontale par catégorie, proportionnelle à la plus grosse.
class CategoryBars extends StatelessWidget {
  final List<(ExpenseCategory, int)> data;
  final int total;

  const CategoryBars({super.key, required this.data, required this.total});

  @override
  Widget build(BuildContext context) {
    final max = data.first.$2;
    return Column(children: [
      for (final (c, cents) in data)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(c.icon, size: 18, color: c.color),
            const SizedBox(width: 8),
            SizedBox(
                width: 120,
                child: Text(c.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))),
            Expanded(
              child: SizedBox(
                height: 10,
                child: CustomPaint(
                    painter: _BarPainter(
                        max <= 0 ? 0 : (cents / max).clamp(0, 1), c.color)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: Text(formatEuros(cents),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
    ]);
  }
}

class _BarPainter extends CustomPainter {
  final double ratio;
  final Color color;

  _BarPainter(this.ratio, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r),
        Paint()..color = EmvColors.grid.withValues(alpha: 0.35));
    if (ratio <= 0) return;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width * ratio, size.height), r),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.ratio != ratio || old.color != color;
}

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  final String? maintenanceTitle;
  final VoidCallback onTap;

  const _ExpenseTile(
      {required this.expense, required this.onTap, this.maintenanceTitle});

  @override
  Widget build(BuildContext context) {
    final e = expense;
    return ListTile(
      leading: Icon(e.category.icon, color: e.category.color),
      title: Text(e.displayLabel),
      subtitle: Text([
        [
          formatDate(e.date),
          if (e.label.isNotEmpty) e.category.label,
          if (e.km != null) formatKm(e.km!),
        ].join(' · '),
        if (maintenanceTitle != null) 'Carnet : $maintenanceTitle',
      ].join('\n')),
      isThreeLine: maintenanceTitle != null,
      trailing: Text(formatEuros(e.cents),
          style: const TextStyle(fontWeight: FontWeight.w700)),
      onTap: onTap,
    );
  }
}

class ExpenseFormScreen extends StatefulWidget {
  final Vehicle vehicle;

  /// Dépense existante (édition, suppression possible).
  final Expense? expense;

  /// Pré-remplissage d'une nouvelle dépense (depuis le carnet).
  final Expense? draft;

  const ExpenseFormScreen(
      {super.key, required this.vehicle, this.expense, this.draft});

  static Route<void> route(Vehicle v, {Expense? expense, Expense? draft}) =>
      MaterialPageRoute(
          builder: (_) =>
              ExpenseFormScreen(vehicle: v, expense: expense, draft: draft));

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Expense? _initial = widget.expense ?? widget.draft;
  late final _amount = TextEditingController(
      text: _initial == null
          ? ''
          : formatEuros(_initial.cents)
              .replaceAll(RegExp(r'[\u00a0€]'), '')
              .trim());
  late final _km = TextEditingController(text: _initial?.km?.toString() ?? '');
  late final _label = TextEditingController(text: _initial?.label ?? '');
  late ExpenseCategory _category = _initial?.category ?? ExpenseCategory.fuel;
  late DateTime _date = _initial?.date ?? _today();
  late String? _maintenanceId = _initial?.maintenanceId;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    for (final c in [_amount, _km, _label]) {
      c.dispose();
    }
    super.dispose();
  }

  ExpenseStore get _store => ExpenseStore.of(context.read<AppState>().prefs);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final expense = Expense(
      id: _initial?.id ?? ExpenseStore.newId(),
      vehicleId: widget.vehicle.id,
      date: _date,
      category: _category,
      cents: parseEurosToCents(_amount.text)!,
      km: int.tryParse(_km.text),
      label: _label.text.trim(),
      maintenanceId: _maintenanceId,
    );
    try {
      await _store.save(expense);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final expense = widget.expense!;
    final store = _store;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette dépense ?'),
        content:
            Text('${expense.displayLabel} · ${formatEuros(expense.cents)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler')),
          FilledButton(
              key: const Key('expense-delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await store.delete(expense.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final maintenance =
        context.watch<AppState>().maintenanceFor(widget.vehicle.id);
    final linkable = maintenance.any((m) => m.id == _maintenanceId)
        ? _maintenanceId
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expense == null ? 'Nouvelle dépense' : 'Dépense'),
        actions: [
          if (widget.expense != null)
            IconButton(
                key: const Key('expense-delete'),
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in ExpenseCategory.values)
              ChoiceChip(
                key: Key('expense-cat-${c.key}'),
                avatar: Icon(c.icon, size: 18, color: c.color),
                label: Text(c.label),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('expense-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]'))
            ],
            decoration:
                const InputDecoration(labelText: 'Montant *', suffixText: '€'),
            validator: (v) => parseEurosToCents(v ?? '') == null
                ? 'Montant attendu, ex. 45,90'
                : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(1980),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  child: Text(formatDate(_date)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('expense-km'),
                controller: _km,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Kilométrage', suffixText: 'km'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('expense-label'),
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Libellé', hintText: 'Plein gazole, plaquettes AV…'),
          ),
          if (maintenance.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('expense-maintenance'),
              initialValue: linkable,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Intervention du carnet (facultatif)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Aucune')),
                for (final m in maintenance)
                  DropdownMenuItem(
                      value: m.id,
                      child: Text('${formatDate(m.date)} · ${m.title}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _maintenanceId = v),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('expense-save'),
            icon: const Icon(Icons.save),
            label: const Text('Enregistrer'),
            onPressed: _save,
          ),
        ]),
      ),
    );
  }
}
