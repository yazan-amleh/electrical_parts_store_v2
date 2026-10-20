import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/operational_report.dart';
import '../../domain/entities/sales_analytics.dart';
import '../../domain/services/report_document_builder.dart';

class PdfReportDocumentBuilder implements ReportDocumentBuilder {
  PdfReportDocumentBuilder({AssetBundle? assetBundle})
    : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;
  _PdfFonts? _fonts;

  @override
  Future<Uint8List> buildOperationalReport({
    required OperationalReport report,
    required String storeName,
  }) async {
    final fonts = await _loadFonts();
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(fonts),
        header: (context) => _buildPageHeader(context, fonts),
        footer: (context) => _buildFooter(context, fonts),
        build: (context) => _operationalContent(
          report: report,
          storeName: storeName,
          fonts: fonts,
        ),
      ),
    );

    return document.save();
  }

  @override
  Future<Uint8List> buildSalesAnalyticsReport({
    required SalesAnalytics analytics,
    required String storeName,
  }) async {
    final fonts = await _loadFonts();
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(fonts),
        header: (context) => _buildPageHeader(context, fonts),
        footer: (context) => _buildFooter(context, fonts),
        build: (context) => _analyticsContent(
          analytics: analytics,
          storeName: storeName,
          fonts: fonts,
        ),
      ),
    );

    return document.save();
  }

  Future<_PdfFonts> _loadFonts() async {
    final cached = _fonts;
    if (cached != null) {
      return cached;
    }

    final regularData = await _assetBundle.load(
      'assets/fonts/Rubik-Regular.ttf',
    );
    final boldData = await _assetBundle.load('assets/fonts/Rubik-Bold.ttf');
    final fonts = _PdfFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
    _fonts = fonts;
    return fonts;
  }

  pw.PageTheme _pageTheme(_PdfFonts fonts) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 34, 28, 32),
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      textDirection: pw.TextDirection.rtl,
    );
  }

  pw.Widget _buildPageHeader(pw.Context context, _PdfFonts fonts) {
    if (context.pageNumber == 1) {
      return pw.SizedBox();
    }
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue700,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        'نظام إدارة المتجر - تقرير V2',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 9,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context, _PdfFonts fonts) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
          pw.Text(
            'مستند مولد من بيانات التقرير المرحّلة',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _operationalContent({
    required OperationalReport report,
    required String storeName,
    required _PdfFonts fonts,
  }) {
    final content = <pw.Widget>[
      _buildTitle(
        title: 'التقرير التشغيلي',
        subtitle:
            'الفترة: ${_formatDate(report.from)} - ${_formatDate(report.to)}',
        storeName: storeName,
        fonts: fonts,
      ),
      pw.SizedBox(height: 14),
      _sectionTitle('ملخص النتائج', fonts),
      pw.SizedBox(height: 6),
      _summaryTable(
        values: [
          ['المبيعات', report.salesRevenue.formatted],
          ['تكلفة المبيعات', report.salesCost.formatted],
          ['مجمل الربح', report.grossProfit.formatted],
          ['المشتريات', report.purchasesTotal.formatted],
          ['المصروفات', report.expensesTotal.formatted],
          ['نتيجة التشغيل', report.operatingResult.formatted],
        ],
        fonts: fonts,
      ),
      pw.SizedBox(height: 14),
      _sectionTitle('توزيع طرق الدفع', fonts),
      pw.SizedBox(height: 6),
      _countTable(report.salesByPaymentMethod, fonts),
      pw.SizedBox(height: 14),
      _sectionTitle('الحركات المرحّلة ضمن الفترة', fonts),
      pw.SizedBox(height: 6),
      _operationalTransactionsTable(report, fonts),
    ];

    if (report.mayBeTruncated) {
      content.insert(
        1,
        _warningBox(
          'هذه النسخة وصلت إلى سقف القراءة الآمن. ضيّق الفترة أو قسّمها قبل اعتماد التقرير.',
          fonts,
        ),
      );
      content.insert(2, pw.SizedBox(height: 10));
    }

    return content;
  }

  List<pw.Widget> _analyticsContent({
    required SalesAnalytics analytics,
    required String storeName,
    required _PdfFonts fonts,
  }) {
    final content = <pw.Widget>[
      _buildTitle(
        title: 'تحليلات المبيعات',
        subtitle:
            'الفترة: ${_formatDate(analytics.from)} - ${_formatDate(analytics.to)}',
        storeName: storeName,
        fonts: fonts,
      ),
      pw.SizedBox(height: 14),
      _sectionTitle('ملخص النتائج', fonts),
      pw.SizedBox(height: 6),
      _summaryTable(
        values: [
          ['عدد الفواتير', analytics.salesCount.toString()],
          ['إجمالي المبيعات', analytics.salesRevenue.formatted],
          ['التكلفة', analytics.salesCost.formatted],
          ['مجمل الربح', analytics.grossProfit.formatted],
        ],
        fonts: fonts,
      ),
      pw.SizedBox(height: 14),
      _sectionTitle('طرق الدفع', fonts),
      pw.SizedBox(height: 6),
      _countTable(analytics.paymentMethodCounts, fonts),
      pw.SizedBox(height: 14),
      _sectionTitle('الأصناف الأكثر مبيعاً', fonts),
      pw.SizedBox(height: 6),
      _analyticsRowsTable(
        analytics.productRows,
        includeQuantity: true,
        fonts: fonts,
      ),
      pw.SizedBox(height: 14),
      _sectionTitle('المبيعات حسب التصنيف', fonts),
      pw.SizedBox(height: 6),
      _analyticsRowsTable(
        analytics.categoryRows,
        includeQuantity: true,
        fonts: fonts,
      ),
      pw.SizedBox(height: 14),
      _sectionTitle('المبيعات حسب العميل', fonts),
      pw.SizedBox(height: 6),
      _analyticsRowsTable(
        analytics.customerRows,
        includeQuantity: false,
        fonts: fonts,
      ),
    ];

    if (analytics.mayBeTruncated) {
      content.insert(
        1,
        _warningBox(
          'هذه النسخة وصلت إلى سقف القراءة الآمن. ضيّق الفترة أو قسّمها قبل اعتماد التحليل.',
          fonts,
        ),
      );
      content.insert(2, pw.SizedBox(height: 10));
    }

    return content;
  }

  pw.Widget _buildTitle({
    required String title,
    required String subtitle,
    required String storeName,
    required _PdfFonts fonts,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue700,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fonts.bold,
              color: PdfColors.white,
              fontSize: 20,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            storeName.trim().isEmpty ? 'متجر V2' : storeName.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fonts.regular,
              color: PdfColors.white,
              fontSize: 11,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            subtitle,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fonts.regular,
              color: PdfColors.white,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionTitle(String title, _PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 12,
          color: PdfColors.blue900,
        ),
      ),
    );
  }

  pw.Widget _warningBox(String message, _PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.orange50,
        border: pw.Border.all(color: PdfColors.orange300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        message,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 9,
          color: PdfColors.orange900,
        ),
      ),
    );
  }

  pw.Widget _summaryTable({
    required List<List<String>> values,
    required _PdfFonts fonts,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blue200, width: 0.6),
      columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)},
      children: [for (final row in values) _tableRow(row, fonts: fonts)],
    );
  }

  pw.Widget _countTable(Map<String, int> values, _PdfFonts fonts) {
    if (values.isEmpty) {
      return pw.Text(
        'لا توجد بيانات ضمن الفترة.',
        style: pw.TextStyle(font: fonts.regular, fontSize: 9),
      );
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blue200, width: 0.6),
      columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1)},
      children: [
        _tableRow(['طريقة الدفع', 'العدد'], fonts: fonts, header: true),
        for (final entry in values.entries)
          _tableRow([
            _paymentLabel(entry.key),
            entry.value.toString(),
          ], fonts: fonts),
      ],
    );
  }

  pw.Widget _operationalTransactionsTable(
    OperationalReport report,
    _PdfFonts fonts,
  ) {
    if (report.transactions.isEmpty) {
      return pw.Text(
        'لا توجد حركات مرحّلة ضمن الفترة.',
        style: pw.TextStyle(font: fonts.regular, fontSize: 9),
      );
    }

    final rows = <pw.TableRow>[
      _tableRow(
        ['التاريخ', 'النوع', 'الوصف', 'طريقة الدفع', 'المبلغ'],
        fonts: fonts,
        header: true,
      ),
      for (final transaction in report.transactions.take(200))
        _tableRow([
          _formatDate(transaction.postedAt),
          _sourceLabel(transaction.source),
          transaction.description ?? 'مستند ${transaction.id}',
          transaction.paymentMethod == null
              ? '—'
              : _paymentLabel(transaction.paymentMethod!),
          transaction.amount.formatted,
        ], fonts: fonts),
    ];

    final widgets = <pw.Widget>[
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.blue200, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.2),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(2.2),
          3: pw.FlexColumnWidth(1.2),
          4: pw.FlexColumnWidth(1.2),
        },
        children: rows,
      ),
    ];
    if (report.transactions.length > 200) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'تم عرض أول 200 حركة فقط داخل مستند الطباعة.',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.grey700,
            ),
          ),
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  pw.Widget _analyticsRowsTable(
    List<SalesAnalyticsRow> rows, {
    required bool includeQuantity,
    required _PdfFonts fonts,
  }) {
    if (rows.isEmpty) {
      return pw.Text(
        'لا توجد بيانات ضمن الفترة.',
        style: pw.TextStyle(font: fonts.regular, fontSize: 9),
      );
    }

    final headers = <String>['الاسم'];
    if (includeQuantity) {
      headers.add('الكمية');
    }
    headers.addAll(['المبيعات', 'التكلفة', 'مجمل الربح']);

    final tableRows = <pw.TableRow>[
      _tableRow(headers, fonts: fonts, header: true),
      for (final row in rows.take(100))
        _tableRow([
          row.label,
          if (includeQuantity) _formatQuantity(row.quantityMilliUnits),
          row.revenue.formatted,
          row.cost.formatted,
          row.grossProfit.formatted,
        ], fonts: fonts),
    ];

    final widgets = <pw.Widget>[
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.blue200, width: 0.5),
        columnWidths: includeQuantity
            ? const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.3),
                3: pw.FlexColumnWidth(1.3),
                4: pw.FlexColumnWidth(1.3),
              }
            : const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(1.3),
                2: pw.FlexColumnWidth(1.3),
                3: pw.FlexColumnWidth(1.3),
              },
        children: tableRows,
      ),
    ];
    if (rows.length > 100) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'تم عرض أول 100 نتيجة مرتبة حسب قيمة المبيعات.',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.grey700,
            ),
          ),
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  pw.TableRow _tableRow(
    List<String> values, {
    required _PdfFonts fonts,
    bool header = false,
  }) {
    return pw.TableRow(
      decoration: header
          ? pw.BoxDecoration(color: PdfColors.blue700)
          : pw.BoxDecoration(color: PdfColors.white),
      children: [
        for (final value in values)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: header ? fonts.bold : fonts.regular,
                fontSize: header ? 8 : 8,
                color: header ? PdfColors.white : PdfColors.blueGrey900,
              ),
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime value) {
    final date = value.toUtc();
    return '${date.year.toString().padLeft(4, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatQuantity(int milliUnits) {
    final sign = milliUnits < 0 ? '-' : '';
    final absolute = milliUnits.abs();
    final major = absolute ~/ 1000;
    final fraction = (absolute % 1000).toString().padLeft(3, '0');
    final trimmedFraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    if (trimmedFraction.isEmpty) {
      return '$sign$major';
    }
    return '$sign$major.$trimmedFraction';
  }

  String _paymentLabel(String value) {
    switch (value) {
      case 'cash':
        return 'نقدي';
      case 'bank':
        return 'بنك';
      case 'card':
        return 'بطاقة';
      case 'credit':
        return 'آجل';
      case 'cheque':
        return 'شيك';
      case 'unknown':
        return 'غير محدد';
      default:
        return value;
    }
  }

  String _sourceLabel(String value) {
    switch (value) {
      case 'sale':
        return 'بيع';
      case 'purchase':
        return 'شراء';
      case 'expense':
        return 'مصروف';
      default:
        return value;
    }
  }
}

class _PdfFonts {
  const _PdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}
