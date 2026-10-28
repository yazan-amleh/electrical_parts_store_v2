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
      'return_status',
      'return_id',
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
          invoice.returnStatus ?? '',
          invoice.returnId ?? '',
        ],
    ];
    return rows.map((row) => row.map(escaped).join(',')).join('\r\n');
  }

  Future<Uint8List> invoicePdf({
    required List<SalesInvoiceDocument> documents,
    required Map<String, String> customerNames,
    required String storeLabel,
  }) async {
    if (documents.isEmpty) {
      throw ArgumentError('At least one invoice is required.');
    }

    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Rubik-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Rubik-Bold.ttf'),
    );
    final pdf = pw.Document();

    for (final document in documents) {
      final invoice = document.invoice;
      final customerName = customerNames[invoice.customerId] ??
          invoice.customerId ??
          'بدون عميل';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          theme: pw.ThemeData.withFont(base: font, bold: bold),
          build: (_) => [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'فاتورة بيع',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: bold, fontSize: 22),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text('المتجر: $storeLabel'),
                  pw.Text('رقم الفاتورة: ${invoice.id}'),
                  pw.Text(
                    'التاريخ: ${invoice.postedAt.toLocal().toIso8601String()}',
                  ),
                  pw.Text('العميل: $customerName'),
                  pw.Text('طريقة الدفع: ${invoice.paymentMethod}'),
                  pw.Text(
                    invoice.isFullyReturned
                        ? 'الحالة: مُرجعة بالكامل'
                        : 'الحالة: مرحّلة',
                    style: invoice.isFullyReturned
                        ? pw.TextStyle(font: bold)
                        : null,
                  ),
                  if (invoice.returnId != null)
                    pw.Text('مرجع المردود: ${invoice.returnId}'),
                  if ((invoice.description ?? '').trim().isNotEmpty)
                    pw.Text('ملاحظات: ${invoice.description}'),
                  pw.SizedBox(height: 14),
                ],
              ),
            ),
            pw.Table.fromTextArray(
              headers: const [
                '#',
                'الصنف',
                'الوحدة',
                'الكمية',
                'سعر الوحدة',
                'الخصم',
                'الإجمالي',
              ],
              data: [
                for (final entry in document.lines.asMap().entries)
                  [
                    '${entry.key + 1}',
                    entry.value.description,
                    entry.value.unitName ?? 'وحدة',
                    _quantity(entry.value.quantityMilliUnits),
                    entry.value.unitPrice.formatted,
                    entry.value.discount.formatted,
                    entry.value.total.formatted,
                  ],
              ],
              headerStyle: pw.TextStyle(font: bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignment: pw.Alignment.centerRight,
            ),
            pw.SizedBox(height: 14),
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('قبل الضريبة: ${invoice.subtotal.formatted}'),
                  pw.Text('الضريبة: ${invoice.tax.formatted}'),
                  pw.Text(
                    'الإجمالي: ${invoice.total.formatted}',
                    style: pw.TextStyle(font: bold, fontSize: 13),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'مرجع القيد: ${invoice.journalEntryId}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return pdf.save();
  }

  String _quantity(int milliUnits) {
    final whole = milliUnits ~/ 1000;
    final remainder = milliUnits.abs() % 1000;
    if (remainder == 0) {
      return '$whole';
    }

    var fraction = remainder.toString().padLeft(3, '0');
    while (fraction.endsWith('0')) {
      fraction = fraction.substring(0, fraction.length - 1);
    }
    return '$whole.$fraction';
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
              'الحالة',
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
                  invoice.isFullyReturned ? 'مُرجعة بالكامل' : 'مرحّلة',
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
