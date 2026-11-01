import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
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

  /// V1-style customer invoice created only from immutable posted V2 data.
  ///
  /// Settlement figures are intentionally omitted: the sale header does not
  /// prove which customer payments were subsequently collected.
  Future<Uint8List> invoicePdf({
    required List<SalesInvoiceDocument> documents,
    required Map<String, String> customerNames,
    required String storeLabel,
    String storePhone = '',
    String storeAddress = '',
    String? expectedStoreId,
  }) async {
    if (documents.isEmpty) {
      throw ArgumentError('At least one invoice is required.');
    }

    // Do not silently turn inconsistent line data into a printable invoice.
    final storeId = documents.first.invoice.storeId;
    for (final document in documents) {
      final invoice = document.invoice;
      if (storeId.trim().isEmpty ||
          invoice.storeId != storeId ||
          (expectedStoreId != null && invoice.storeId != expectedStoreId) ||
          document.lines.isEmpty ||
          invoice.subtotal.currency != invoice.total.currency ||
          invoice.tax.currency != invoice.total.currency ||
          invoice.cost.currency != invoice.total.currency ||
          invoice.subtotal.minorUnits + invoice.tax.minorUnits !=
              invoice.total.minorUnits) {
        throw StateError(
            'Invoice is inconsistent or belongs to another store.');
      }
      var sum = 0;
      var cost = 0;
      for (final line in document.lines) {
        if (line.quantityMilliUnits <= 0 ||
            line.returnedQuantityMilliUnits < 0 ||
            line.returnedQuantityMilliUnits > line.quantityMilliUnits ||
            line.total.minorUnits < 0 ||
            line.discount.minorUnits < 0 ||
            line.unitPrice.currency != invoice.total.currency ||
            line.discount.currency != invoice.total.currency ||
            line.total.currency != invoice.total.currency ||
            line.cost.currency != invoice.total.currency) {
          throw StateError('Invoice contains inconsistent line values.');
        }
        sum += line.total.minorUnits;
        cost += line.cost.minorUnits;
      }
      if (sum != invoice.subtotal.minorUnits ||
          cost != invoice.cost.minorUnits) {
        throw StateError('Invoice lines do not reconcile to posted totals.');
      }
    }

    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Rubik-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Rubik-Bold.ttf'),
    );
    final navy = PdfColor.fromInt(0xFF1E3A6E);
    final pale = PdfColor.fromInt(0xFFEAEDF6);
    final border = PdfColor.fromInt(0xFFCDD3E8);
    final pdf = pw.Document();

    for (final document in documents) {
      final invoice = document.invoice;
      final customerName = customerNames[invoice.customerId] ??
          invoice.customerId ??
          (invoice.paymentMethod == 'credit' ? 'عميل آجل' : 'عميل نقدي');
      final currency = invoice.total.currency;
      final discount = document.lines.fold<int>(
        0,
        (sum, line) => sum + line.discount.minorUnits,
      );
      final original = invoice.subtotal.minorUnits + discount;
      String money(int minor) =>
          Money(minorUnits: minor, currency: currency).formatted;
      final date = invoice.postedAt.toLocal();
      final dateLabel = '${date.year.toString().padLeft(4, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.day.toString().padLeft(2, '0')}';

      pw.Widget summaryRow(String label, String value,
          {bool emphasized = false}) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: emphasized ? pale : PdfColors.white,
            border: pw.Border(
              bottom: pw.BorderSide(color: border, width: 0.4),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(value,
                  style: pw.TextStyle(
                    font: emphasized ? bold : font,
                    fontSize: emphasized ? 12 : 10,
                    color: emphasized ? navy : PdfColors.blueGrey900,
                  )),
              pw.Text(label,
                  style: pw.TextStyle(
                    font: emphasized ? bold : font,
                    fontSize: emphasized ? 11 : 10,
                    color: emphasized ? navy : PdfColors.blueGrey900,
                  )),
            ],
          ),
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            theme: pw.ThemeData.withFont(base: font, bold: bold),
            textDirection: pw.TextDirection.rtl,
          ),
          header: (ctx) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: border, width: 1.5),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 46,
                  height: 46,
                  decoration: pw.BoxDecoration(
                    color: navy,
                    borderRadius: pw.BorderRadius.circular(7),
                  ),
                  child: pw.SizedBox(),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Text(
                    storeLabel.trim().isEmpty ? storeId : storeLabel.trim(),
                    style: pw.TextStyle(font: bold, fontSize: 19, color: navy),
                  ),
                ),
                pw.Container(width: 1, height: 49, color: border),
                pw.SizedBox(width: 12),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('فاتورة مبيعات',
                        style: pw.TextStyle(
                            font: bold, fontSize: 16, color: navy)),
                    pw.SizedBox(height: 4),
                    pw.Text('رقم الفاتورة: ${invoice.id}',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('التاريخ: $dateLabel',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
          footer: (ctx) => pw.Column(
            children: [
              pw.Container(height: 0.7, color: border),
              pw.SizedBox(height: 6),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: navy,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                        style: pw.TextStyle(
                            font: font, fontSize: 8, color: PdfColors.white)),
                    pw.Text('شكراً لتعاملكم معنا',
                        style: pw.TextStyle(
                            font: bold, fontSize: 10, color: PdfColors.white)),
                    pw.Text(storePhone.trim(),
                        style: pw.TextStyle(
                            font: font, fontSize: 9, color: PdfColors.white)),
                  ],
                ),
              ),
            ],
          ),
          build: (_) => [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: border),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: pw.BoxDecoration(
                      color: navy,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text('بيانات العميل',
                        style: pw.TextStyle(
                            font: bold, fontSize: 11, color: PdfColors.white)),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('الاسم: $customerName',
                      style: pw.TextStyle(font: font, fontSize: 10)),
                  if ((invoice.customerId ?? '').trim().isNotEmpty)
                    pw.Text('مرجع العميل: ${invoice.customerId}',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                  pw.Text('طريقة الدفع: ${_paymentName(invoice.paymentMethod)}',
                      style: pw.TextStyle(font: font, fontSize: 9)),
                  if (storeAddress.trim().isNotEmpty)
                    pw.Text('عنوان المتجر: ${storeAddress.trim()}',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                  pw.Text(
                    invoice.isFullyReturned
                        ? 'الحالة: مُرجعة بالكامل'
                        : invoice.isPartiallyReturned
                            ? 'الحالة: مُرجعة جزئيًا'
                            : 'الحالة: مرحّلة',
                    style: pw.TextStyle(font: bold, fontSize: 9),
                  ),
                  if (invoice.returnId != null)
                    pw.Text('مرجع المردود: ${invoice.returnId}',
                        style: pw.TextStyle(font: font, fontSize: 8)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Table.fromTextArray(
              headers: const [
                '#',
                'الصنف',
                'الوحدة',
                'الكمية',
                'مرتجع',
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
                    _quantity(entry.value.returnedQuantityMilliUnits),
                    entry.value.unitPrice.formatted,
                    entry.value.discount.formatted,
                    entry.value.total.formatted,
                  ],
              ],
              headerStyle:
                  pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
              cellStyle: pw.TextStyle(font: font, fontSize: 8),
              headerDecoration: pw.BoxDecoration(color: navy),
              oddRowDecoration: pw.BoxDecoration(color: pale),
              cellAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(color: border, width: 0.4),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 12),
              decoration: pw.BoxDecoration(
                color: pale,
                border: pw.Border.all(color: border, width: 0.5),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(invoice.total.formatted,
                      style:
                          pw.TextStyle(font: bold, fontSize: 13, color: navy)),
                  pw.Text('إجمالي الفاتورة',
                      style:
                          pw.TextStyle(font: bold, fontSize: 11, color: navy)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              children: [
                pw.Expanded(child: pw.SizedBox()),
                pw.Expanded(
                  flex: 3,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: border),
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Column(
                      children: [
                        summaryRow('إجمالي الأصناف قبل الخصم', money(original)),
                        if (discount > 0)
                          summaryRow('خصم الأصناف', money(discount)),
                        summaryRow(
                            'الصافي قبل الضريبة', invoice.subtotal.formatted),
                        summaryRow('الضريبة', invoice.tax.formatted),
                        summaryRow('الإجمالي المستحق', invoice.total.formatted,
                            emphasized: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if ((invoice.description ?? '').trim().isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: border),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('ملاحظات',
                        style: pw.TextStyle(font: bold, fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text(invoice.description!,
                        style: pw.TextStyle(font: font, fontSize: 9)),
                  ],
                ),
              ),
            ],
            pw.SizedBox(height: 8),
            pw.Text('المدفوع والمتبقي لا يظهران دون بيانات تحصيل مؤكدة.',
                style: pw.TextStyle(
                    font: font, fontSize: 8, color: PdfColors.blueGrey700)),
            pw.Text('مرجع القيد: ${invoice.journalEntryId}',
                style: pw.TextStyle(
                    font: font, fontSize: 8, color: PdfColors.blueGrey700)),
          ],
        ),
      );
    }

    return pdf.save();
  }

  String _paymentName(String method) {
    switch (method) {
      case 'cash':
        return 'نقدي';
      case 'bank':
        return 'تحويل بنكي';
      case 'card':
        return 'بطاقة';
      case 'credit':
        return 'آجل';
      case 'cheque':
        return 'شيك';
      default:
        return method;
    }
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
                  invoice.isFullyReturned
                      ? 'مُرجعة بالكامل'
                      : invoice.isPartiallyReturned
                          ? 'مُرجعة جزئيًا'
                          : 'مرحّلة',
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
