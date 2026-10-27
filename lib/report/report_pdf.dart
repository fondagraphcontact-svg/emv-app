import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../codelog/code_entry.dart';
import '../expenses/expense.dart';
import '../maintenance/maintenance_entry.dart';
import '../models.dart';
import '../precheck/precheck_models.dart';
import '../state.dart';

const reportDisclaimer = 'Généré par Electro Meca View — informatif, '
    'ne remplace pas un diagnostic professionnel.';

class ReportInput {
  final Vehicle? vehicle;
  final int? odometer;
  final String symptoms;
  final List<(RecentDtc, Dtc?)> codes;
  final List<MaintenanceEntry> maintenance;
  final List<(CodeLogEntry, Dtc?)> loggedCodes;

  /// Section « Dépenses » omise si vide.
  final List<Expense> expenses;

  /// Section « Pré-contrôle technique » omise si null.
  final PrecheckReport? precheck;
  final String? dataVersion;
  final DateTime generatedAt;

  const ReportInput({
    required this.vehicle,
    required this.symptoms,
    required this.codes,
    required this.maintenance,
    required this.generatedAt,
    this.odometer,
    this.dataVersion,
    this.loggedCodes = const [],
    this.expenses = const [],
    this.precheck,
  });
}

/// Roboto embarquée : les polices PDF standard ne couvrent que Latin-1
/// (pas de « — », « € », « œ »).
Future<pw.ThemeData> loadReportTheme([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  return pw.ThemeData.withFont(
    base: pw.Font.ttf(await b.load('assets/fonts/Roboto-Regular.ttf')),
    bold: pw.Font.ttf(await b.load('assets/fonts/Roboto-Bold.ttf')),
  );
}

Future<Uint8List> buildReportPdf(ReportInput r, {pw.ThemeData? theme}) {
  const accent = PdfColor.fromInt(0xFFFF8A00);
  final doc = pw.Document(
    title: 'Rapport Electro Meca View',
    author: 'Electro Meca View',
    theme: theme,
  );

  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: accent)),
      );
  pw.Widget muted(String text) => pw.Text(text,
      style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10));

  final v = r.vehicle;
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (context) => pw.Column(children: [
      pw.Divider(color: PdfColors.grey400),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(child: muted(reportDisclaimer)),
        muted('${context.pageNumber}/${context.pagesCount}'),
      ]),
    ]),
    build: (context) => [
      pw.Text('Rapport pour le garage',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      muted([
        'Le ${formatDate(r.generatedAt)}',
        if (r.dataVersion != null) 'données v${r.dataVersion}',
      ].join(' · ')),
      heading('Véhicule'),
      if (v == null)
        pw.Text('Non renseigné')
      else ...[
        pw.Text(v.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(v.subtitle),
      ],
      if (r.odometer != null) pw.Text('Kilométrage : ${formatKm(r.odometer!)}'),
      heading('Symptômes décrits'),
      pw.Text(r.symptoms.trim().isEmpty ? 'Non renseignés' : r.symptoms.trim()),
      heading('Codes défaut consultés'),
      if (r.codes.isEmpty)
        pw.Text('Aucun')
      else
        pw.TableHelper.fromTextArray(
          headers: const ['Code', 'Libellé', 'Consulté le'],
          data: [
            for (final (recent, dtc) in r.codes)
              [recent.code, dtc?.title ?? '', formatDate(recent.at)]
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: const {
            0: pw.FixedColumnWidth(60),
            1: pw.FlexColumnWidth(),
            2: pw.FixedColumnWidth(80),
          },
        ),
      heading('Codes relevés'),
      if (r.loggedCodes.isEmpty)
        pw.Text('Aucun code relevé')
      else
        pw.TableHelper.fromTextArray(
          headers: const ['Code', 'Libellé', 'Relevé le', 'Km', 'Statut'],
          data: [
            for (final (e, dtc) in r.loggedCodes)
              [
                e.code,
                [dtc?.title ?? 'Code non répertorié', if (e.note.isNotEmpty) e.note]
                    .join('\n'),
                formatDate(e.date),
                e.km == null ? '' : formatKm(e.km!),
                e.resolvedAt == null
                    ? 'Ouvert'
                    : 'Résolu le ${formatDate(e.resolvedAt!)}',
              ]
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          cellStyle: const pw.TextStyle(fontSize: 9),
          columnWidths: const {
            0: pw.FixedColumnWidth(50),
            1: pw.FlexColumnWidth(),
            2: pw.FixedColumnWidth(62),
            3: pw.FixedColumnWidth(62),
            4: pw.FixedColumnWidth(80),
          },
        ),
      heading('Carnet d\'entretien'),
      if (r.maintenance.isEmpty)
        pw.Text('Aucune intervention enregistrée')
      else
        pw.TableHelper.fromTextArray(
          headers: const ['Date', 'Km', 'Intervention', 'Pièces', 'Coût'],
          data: [
            for (final e in r.maintenance)
              [
                formatDate(e.date),
                e.km == null ? '' : formatKm(e.km!),
                [e.title, if (e.note.isNotEmpty) e.note].join('\n'),
                e.parts.join(', '),
                e.cost == null ? '' : formatCost(e.cost!),
              ]
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          cellStyle: const pw.TextStyle(fontSize: 9),
        ),
      if (r.expenses.isNotEmpty) ..._expensesSection(r.expenses, heading),
      if (r.precheck != null) ..._precheckSection(r.precheck!, heading),
      pw.SizedBox(height: 18),
      pw.Text(reportDisclaimer,
          style: const pw.TextStyle(fontSize: 10)),
    ],
  ));
  return doc.save();
}

const reportExpenseLines = 20;

List<pw.Widget> _expensesSection(
    List<Expense> expenses, pw.Widget Function(String) heading) {
  final summary = ExpenseSummary.of(expenses);
  final recent = [...expenses]..sort((a, b) => b.date.compareTo(a.date));
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  return [
    heading('Dépenses'),
    pw.TableHelper.fromTextArray(
      headers: const ['Catégorie', 'Total'],
      data: [
        for (final (c, cents) in summary.ranked) [c.label, formatEuros(cents)],
        ['Total', formatEuros(summary.totalCents)],
      ],
      headerStyle: bold,
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: const {1: pw.Alignment.centerRight},
      columnWidths: const {
        0: pw.FlexColumnWidth(),
        1: pw.FixedColumnWidth(90),
      },
    ),
    pw.SizedBox(height: 8),
    pw.Text(
        recent.length > reportExpenseLines
            ? '$reportExpenseLines dernières dépenses sur ${recent.length}'
            : 'Détail',
        style: bold),
    pw.TableHelper.fromTextArray(
      headers: const ['Date', 'Catégorie', 'Libellé', 'Km', 'Montant'],
      data: [
        for (final e in recent.take(reportExpenseLines))
          [
            formatDate(e.date),
            e.category.label,
            e.label,
            e.km == null ? '' : formatKm(e.km!),
            formatEuros(e.cents),
          ]
      ],
      headerStyle: bold,
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: const {4: pw.Alignment.centerRight},
      cellStyle: const pw.TextStyle(fontSize: 9),
      columnWidths: const {
        0: pw.FixedColumnWidth(62),
        1: pw.FixedColumnWidth(90),
        2: pw.FlexColumnWidth(),
        3: pw.FixedColumnWidth(62),
        4: pw.FixedColumnWidth(70),
      },
    ),
  ];
}

List<pw.Widget> _precheckSection(
    PrecheckReport p, pw.Widget Function(String) heading) {
  final s = p.summary;
  return [
    heading('Pré-contrôle technique (indicatif)'),
    pw.Text('${s.ok + s.todo}/${s.total} points vérifiés soi-même · '
        '${s.ok} OK · ${s.todo} à voir '
        '(critique ${s.todoByLevel['critique'] ?? 0}, '
        'majeure ${s.todoByLevel['majeure'] ?? 0}, '
        'mineure ${s.todoByLevel['mineure'] ?? 0})'),
    if (p.todo.isNotEmpty)
      pw.TableHelper.fromTextArray(
        headers: const ['Fonction', 'Point à voir', 'Niveau EMV'],
        data: [
          for (final t in p.todo) [t.function, t.point.title, t.point.level]
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellAlignment: pw.Alignment.centerLeft,
        cellStyle: const pw.TextStyle(fontSize: 9),
        columnWidths: const {
          0: pw.FixedColumnWidth(110),
          1: pw.FlexColumnWidth(),
          2: pw.FixedColumnWidth(70),
        },
      ),
    pw.Text('Vérification faite par l\'utilisateur, indicative : ne remplace pas '
        'le contrôle technique.',
        style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9)),
  ];
}
