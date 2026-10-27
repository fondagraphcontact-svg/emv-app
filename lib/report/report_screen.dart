import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../codelog/code_entry.dart';
import '../codelog/code_log_store.dart';
import '../config.dart';
import '../expenses/expense_store.dart';
import '../models.dart';
import '../precheck/precheck_assets.dart';
import '../precheck/precheck_models.dart';
import '../precheck/precheck_store.dart';
import '../state.dart';
import 'report_pdf.dart';

class ReportScreen extends StatefulWidget {
  /// Code à présélectionner (ouverture depuis une fiche DTC).
  final String? focusCode;

  const ReportScreen({super.key, this.focusCode});

  static Route<void> route({String? focusCode}) => MaterialPageRoute(
      builder: (_) => ReportScreen(focusCode: focusCode));

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _symptoms = TextEditingController();
  late final Set<String> _codes = {
    for (final r in context.read<AppState>().recentDtcs.take(5)) r.code,
    ?widget.focusCode,
  };
  bool _withMaintenance = true;
  bool _withCodeLog = true;
  bool _withExpenses = true;
  bool _withPrecheck = true;
  bool _busy = false;

  @override
  void dispose() {
    _symptoms.dispose();
    super.dispose();
  }

  Future<ReportInput> _input() async {
    final state = context.read<AppState>();
    final v = state.current;
    return ReportInput(
      vehicle: v,
      odometer: v == null ? null : state.odometer(v.id),
      symptoms: _symptoms.text,
      codes: [
        for (final r in state.recentDtcs)
          if (_codes.contains(r.code)) (r, state.data.dtc(r.code))
      ],
      maintenance: v == null || !_withMaintenance
          ? const []
          : state.maintenanceFor(v.id),
      loggedCodes: v == null || !_withCodeLog
          ? const []
          : [
              for (final e in _loggedCodes(state, v))
                (e, state.data.dtc(e.code))
            ],
      expenses: v == null || !_withExpenses
          ? const []
          : ExpenseStore.of(state.prefs).entriesFor(v.id),
      precheck: v == null || !_withPrecheck ? null : await _precheck(state, v),
      dataVersion: await loadDataVersion(),
      generatedAt: DateTime.now(),
    );
  }

  /// Null si aucune case n'est cochée pour ce véhicule.
  Future<PrecheckReport?> _precheck(AppState state, Vehicle v) async {
    final store = PrecheckStore.of(state.prefs);
    if (store.statuses(v.id).isEmpty) return null;
    final report = PrecheckReport.of(
        await loadPrecheck(), v, (id) => store.status(v.id, id));
    return report.isEmpty ? null : report;
  }

  /// Ouverts d'abord, puis résolus, chacun du plus récent au plus ancien.
  List<CodeLogEntry> _loggedCodes(AppState state, Vehicle v) {
    final store = CodeLogStore.of(state.prefs);
    return [...store.openFor(v.id), ...store.resolvedFor(v.id)];
  }

  String get _fileName {
    final n = DateTime.now();
    return 'emv-rapport-${n.year}${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}.pdf';
  }

  Future<void> _run(Future<void> Function(ReportInput input) action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(await _input());
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Impossible de générer le PDF : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() => _run((input) async {
        final theme = await loadReportTheme();
        await Printing.layoutPdf(
          name: _fileName,
          onLayout: (_) => buildReportPdf(input, theme: theme),
        );
      });

  Future<void> _share() => _run((input) async {
        final bytes =
            await buildReportPdf(input, theme: await loadReportTheme());
        // Web Share API rarement disponible avec fichiers : téléchargement.
        if (kIsWeb) {
          await Printing.sharePdf(bytes: bytes, filename: _fileName);
          return;
        }
        await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
          fileNameOverrides: [_fileName],
          subject: 'Rapport Electro Meca View',
        ));
      });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final v = state.current;
    final entries = v == null ? const [] : state.maintenanceFor(v.id);
    final recent = state.recentDtcs;
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer pour le garage')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.directions_car),
          title: Text(v?.title ?? 'Aucun véhicule choisi'),
          subtitle: Text(v?.subtitle ?? 'Choisissez-le dans l\'onglet Véhicule.'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('report-symptoms'),
          controller: _symptoms,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Symptômes constatés',
            hintText: 'À froid, voyant moteur allumé, à-coups vers 2000 tr/min…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        Text('Codes consultés récemment',
            style: Theme.of(context).textTheme.titleMedium),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun code consulté.',
                style: TextStyle(color: Colors.white60)),
          ),
        for (final r in recent)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _codes.contains(r.code),
            title: Text(r.code),
            subtitle: Text(state.data.dtc(r.code)?.title ?? ''),
            onChanged: (on) => setState(
                () => on == true ? _codes.add(r.code) : _codes.remove(r.code)),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _withMaintenance && v != null,
          onChanged: v == null
              ? null
              : (on) => setState(() => _withMaintenance = on),
          title: const Text('Inclure le carnet d\'entretien'),
          subtitle: Text('${entries.length} intervention(s)'),
        ),
        SwitchListTile(
          key: const Key('report-codelog'),
          contentPadding: EdgeInsets.zero,
          value: _withCodeLog && v != null,
          onChanged: v == null
              ? null
              : (on) => setState(() => _withCodeLog = on),
          title: const Text('Inclure mes codes relevés'),
          subtitle: Text(v == null
              ? 'Aucun véhicule'
              : '${_loggedCodes(state, v).length} code(s), ouverts et résolus'),
        ),
        SwitchListTile(
          key: const Key('report-expenses'),
          contentPadding: EdgeInsets.zero,
          value: _withExpenses && v != null,
          onChanged: v == null
              ? null
              : (on) => setState(() => _withExpenses = on),
          title: const Text('Inclure mes dépenses'),
          subtitle: Text(v == null
              ? 'Aucun véhicule'
              : 'Totaux par catégorie + $reportExpenseLines dernières · '
                  '${ExpenseStore.of(state.prefs).entriesFor(v.id).length} '
                  'dépense(s)'),
        ),
        SwitchListTile(
          key: const Key('report-precheck'),
          contentPadding: EdgeInsets.zero,
          value: _withPrecheck && v != null,
          onChanged: v == null
              ? null
              : (on) => setState(() => _withPrecheck = on),
          title: const Text('Inclure le pré-contrôle technique'),
          subtitle: Text(v == null
              ? 'Aucun véhicule'
              : '${PrecheckStore.of(state.prefs).statuses(v.id).length} '
                  'point(s) vérifié(s), indicatif'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined),
              label: const Text('Aperçu'),
              onPressed: _busy ? null : _preview,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              key: const Key('report-share'),
              icon: const Icon(Icons.share),
              label: const Text('Partager le PDF'),
              onPressed: _busy ? null : _share,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        const Text(reportDisclaimer,
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]),
    );
  }
}

/// Raccourci commun Profil / fiche DTC.
void openReport(BuildContext context, {Dtc? dtc}) =>
    Navigator.of(context).push(ReportScreen.route(focusCode: dtc?.code));
