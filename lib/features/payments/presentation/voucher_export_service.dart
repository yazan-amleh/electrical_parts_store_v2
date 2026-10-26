import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/entities/voucher_record.dart';

/// Only export records that were actually loaded from the secured voucher
/// repository. It does not claim to be a complete accounting-period report.
class VoucherExportService {
  const VoucherExportService();

  static const _font = 'assets/fonts/Rubik-Regular.ttf';
  static const _boldFont = 'assets/fonts/Rubik-Bold.ttf';

  String csvFor(List<VoucherRecord> records) {
    const headings = [
      'رقم السند',
      'معرف الحركة',
      'نوع الحركة',
      'معرف الطرف',
      'المبلغ بالوحدات الصغرى',
      'العملة',
      'الحالة',
      'تاريخ الحركة UTC',
      'مرجع القيد',
      'الوصف',
    ];
    final rows = <List<String>>[
      headings,
      for (final item in records)
        [
          item.voucherNumber ?? '',
          item.id,
          item.typeLabel,
          item.partyId,
          item.amount.minorUnits.toString(),
          item.amount.currency,
          item.statusLabel,
          item.postedAt.toUtc().toIso8601String(),
          item.journalEntryId,
          item.description ?? '',
        ],
    ];
    String escape(String value) {
      // Prevent CSV spreadsheet formula injection from untrusted text fields.
      final safe = value.startsWith('=') ||
              value.startsWith('+') ||
              value.startsWith('-') ||
              value.startsWith('@') ||
              value.startsWith('\t') ||
              value.startsWith('\r')
          ? "'" + value
          : value;
      return '"' + safe.replaceAll('"', '""') + '"';
    }

    return rows.map((row) => row.map(escape).join(',')).join('\r\n');
  }

  Future<void> copyCsv(List<VoucherRecord> records) async {
    await Clipboard.setData(ClipboardData(text: csvFor(records)));
  }

  Future<Uint8List> buildPdf(List<VoucherRecord> records) async {
    final font = pw.Font.ttf(await rootBundle.load(_font));
    final boldFont = pw.Font.ttf(await rootBundle.load(_boldFont));
    final document = pw.Document();
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: theme,
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'سجل سندات القبض والدفع',
                  style: pw.TextStyle(font: boldFont, fontSize: 19),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'تصدير للصفحات المحمّلة بعد تطبيق الفلاتر فقط، '
                  'وليس كشفًا محاسبيًا كاملًا للفترة.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 14),
              ],
            ),
          ),
          pw.Table.fromTextArray(
            headers: const [
              'رقم السند',
              'النوع',
              'الطرف',
              'المبلغ',
              'الحالة',
              'التاريخ',
              'القيد',
            ],
            data: [
              for (final item in records)
                [
                  item.voucherNumber ?? item.id,
                  item.typeLabel,
                  item.partyId,
                  item.amount.formatted,
                  item.statusLabel,
                  item.postedAt.toUtc().toIso8601String().split('T').first,
                  item.journalEntryId,
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(font: boldFont, fontSize: 10),
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

  Future<void> sharePdf(List<VoucherRecord> records) async {
    final bytes = await buildPdf(records);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'vouchers_loaded_pages.pdf',
    );
  }

  Future<void> printPdf(List<VoucherRecord> records) async {
    final bytes = await buildPdf(records);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
