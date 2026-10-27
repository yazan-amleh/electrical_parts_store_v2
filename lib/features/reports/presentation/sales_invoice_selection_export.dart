import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/entities/sales_invoice_report.dart';

/// A read-only print summary of posted sale headers.
/// Not an invoice with product lines, returns or tax invoice certification.
class SalesInvoiceSelectionExport {
  const SalesInvoiceSelectionExport();

  String csv({
    required List<SalesInvoiceSummary> invoices,
    required Map<String, String> customerNames,
  }) {
    const header = [
      'invoice_id',
      'posted_at_utc',
      'customer',
      'payment_method',
      'subtotal_minor_units',
      'tax_minor_units',
      'total_minor_units',
      'cost_minor_units',
      'currency',
      'journal_entry_id',
    ];
    String escaped(String value) {
      final trimmed = value.trimLeft();
      final unsafe = trimmed.isNotEmpty &&
          const ['=', '+', '-', '@'].contains(trimmed.substring(0, 1));
      final safe = unsafe ? "'$value" : value;
      return '"${safe.replaceAll('"', '""')}"';
    }

    final rows = <List<String>>[
      header,
      for (final invoice in invoices)
        [
          invoice.id,
          invoice.postedAt.toUtc().toIso8601String(),
          customerNames[invoice.customerId] ??
              invoice.customerId ??
              'بدون عميل',
          invoice.paymentMethod,
          invoice.subtotal.minorUnits.toString(),
          invoice.tax.minorUnits.toString(),
          invoice.total.minorUnits.toString(),
          invoice.cost.minorUnits.toString(),
          invoice.total.currency,
          invoice.journalEntryId,
        ],
    ];
    return rows.map((row) => row.map(escaped).join(',')).join('\r\n');
  }

  Future<Uint8List> pdf({
    required List<SalesInvoiceSummary> invoices,
    required Map<String, String> customerNames,
    required String storeLabel,
  }) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Rubik-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Rubik-Bold.ttf'),
    );
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        build: (_) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ملخص الفواتير المرحّلة المختارة',
                  style: pw.TextStyle(font: bold, fontSize: 19),
                ),
                pw.SizedBox(height: 5),
                pw.Text('المتجر: $storeLabel'),
                pw.Text('عدد الفواتير المختارة: ${invoices.length}'),
                pw.SizedBox(height: 5),
                pw.Text(
                  'هذه طباعة لملخص رؤوس الفواتير المحمّلة؛ '
                  'ليست فاتورة تفصيلية بالأصناف أو شهادة ضريبية.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.SizedBox(height: 12),
              ],
            ),
          ),
          pw.Table.fromTextArray(
            headers: const [
              'معرف الفاتورة',
              'التاريخ UTC',
              'العميل',
              'الدفع',
              'قبل الضريبة',
              'الضريبة',
              'الإجمالي',
              'مرجع القيد',
            ],
            data: [
              for (final invoice in invoices)
                [
                  invoice.id,
                  invoice.postedAt.toUtc().toIso8601String().split('T').first,
                  customerNames[invoice.customerId] ??
                      invoice.customerId ??
                      'بدون عميل',
                  invoice.paymentMethod,
                  invoice.subtotal.formatted,
                  invoice.tax.formatted,
                  invoice.total.formatted,
                  invoice.journalEntryId,
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(font: bold, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey200,
            ),
            cellAlignment: pw.Alignment.centerRight,
          ),
        ],
      ),
    );
    return document.save();
  }
}
