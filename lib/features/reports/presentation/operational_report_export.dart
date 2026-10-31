import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../core/money/money.dart';
import '../domain/entities/operational_report.dart';

/// Filters the loaded transaction details only. The report's accounting totals
/// always remain period-wide and are never recomputed from a limited view.
class OperationalTransactionFilter {
  const OperationalTransactionFilter({
    this.source,
    this.paymentMethod,
    this.search = '',
  });

  final String? source;
  final String? paymentMethod;
  final String search;

  List<ReportTransaction> apply(Iterable<ReportTransaction> transactions) {
    final term = search.trim().toLowerCase();
    return transactions.where((transaction) {
      if (source != null && transaction.source != source) return false;
      if (paymentMethod != null &&
          (transaction.paymentMethod ?? 'unknown') != paymentMethod) {
        return false;
      }
      if (term.isEmpty) return true;
      return transaction.id.toLowerCase().contains(term) ||
          (transaction.description?.toLowerCase().contains(term) ?? false) ||
          transaction.source.toLowerCase().contains(term) ||
          (transaction.paymentMethod?.toLowerCase().contains(term) ?? false);
    }).toList(growable: false);
  }
}

/// Produces a real XLSX file. Never silently presents filtered details as
/// filtered accounting totals or partial data as a complete report.
class OperationalReportExport {
  const OperationalReportExport();

  Uint8List xlsx({
    required OperationalReport report,
    required String storeLabel,
    required List<ReportTransaction> displayedTransactions,
    bool detailsFiltered = false,
  }) {
    final workbook = Excel.createExcel();
    final summary = _sheet(workbook, 'ملخص التقرير');
    _headers(summary, const ['البيان', 'القيمة', 'العملة']);
    _row(summary, [
      'المتجر',
      _safe(storeLabel),
      '',
    ]);
    _row(summary, [
      'من',
      report.from.toUtc().toIso8601String(),
      '',
    ]);
    _row(summary, [
      'إلى',
      report.to.toUtc().toIso8601String(),
      '',
    ]);
    _row(summary, [
      'اكتمال البيانات',
      report.mayBeTruncated ? 'غير مكتمل - سقف التحميل' : 'ضمن سقف التحميل',
      '',
    ]);
    _row(summary, [
      'نطاق الإجماليات',
      'كامل الفترة المحمّلة دون تطبيق فلتر التفاصيل',
      '',
    ]);
    _moneyRow(summary, 'صافي المبيعات', report.salesRevenue);
    _moneyRow(summary, 'صافي تكلفة المبيعات', report.salesCost);
    _moneyRow(summary, 'مجمل الربح', report.grossProfit);
    _moneyRow(summary, 'صافي المشتريات', report.purchasesTotal);
    _moneyRow(summary, 'المصروفات', report.expensesTotal);
    _moneyRow(summary, 'نتيجة التشغيل', report.operatingResult);
    _row(summary, ['فواتير البيع', report.salesCount, '']);
    _row(summary, ['مردودات البيع', report.salesReturnCount, '']);
    _row(summary, ['فواتير الشراء', report.purchasesCount, '']);
    _row(summary, ['مردودات الشراء', report.purchaseReturnCount, '']);
    _row(summary, ['عدد المصروفات', report.expensesCount, '']);
    _row(summary, ['عدد الحركات في التقرير', report.transactions.length, '']);
    _row(summary, ['الحركات المصدّرة', displayedTransactions.length, '']);
    _row(summary, [
      'فلتر تفاصيل الحركات',
      detailsFiltered ? 'مفعّل - لا يغيّر إجماليات الفترة' : 'غير مفعّل',
      '',
    ]);
    _widths(summary, const [42, 62, 16]);

    final movements = _sheet(workbook, 'تفاصيل الحركات');
    _headers(movements, const [
      'معرف المستند',
      'التاريخ والوقت UTC',
      'النوع',
      'الوصف',
      'طريقة الدفع',
      'المبلغ',
      'الضريبة',
      'التكلفة',
      'العملة',
    ]);
    for (final item in displayedTransactions) {
      _row(movements, [
        _safe(item.id),
        item.postedAt.toUtc().toIso8601String(),
        _sourceLabel(item.source),
        _safe(item.description ?? ''),
        _paymentLabel(item.paymentMethod),
        item.amount.minorUnits / 100,
        (item.tax?.minorUnits ?? 0) / 100,
        item.cost.minorUnits / 100,
        item.amount.currency,
      ]);
    }
    _widths(movements, const [28, 27, 22, 46, 20, 18, 18, 18, 14]);

    final payment = _sheet(workbook, 'طرق الدفع');
    _headers(payment, const ['مجموعة', 'طريقة الدفع', 'عدد الحركات']);
    for (final entry in report.salesByPaymentMethod.entries) {
      _row(payment, ['مبيعات', _paymentLabel(entry.key), entry.value]);
    }
    for (final entry in report.expensesByPaymentMethod.entries) {
      _row(payment, ['مصروفات', _paymentLabel(entry.key), entry.value]);
    }
    _widths(payment, const [25, 25, 20]);
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('تعذر إنشاء ملف Excel.');
    }
    return Uint8List.fromList(bytes);
  }

  /// CSV is a secondary interchange format using unambiguous minor units.
  String csv(List<ReportTransaction> transactions) {
    final lines = <List<String>>[
      [
        'document_id',
        'posted_at_utc',
        'source',
        'description',
        'payment_method',
        'amount_minor_units',
        'tax_minor_units',
        'cost_minor_units',
        'currency',
      ],
      for (final item in transactions)
        [
          item.id,
          item.postedAt.toUtc().toIso8601String(),
          item.source,
          item.description ?? '',
          item.paymentMethod ?? '',
          item.amount.minorUnits.toString(),
          (item.tax?.minorUnits ?? 0).toString(),
          item.cost.minorUnits.toString(),
          item.amount.currency,
        ],
    ];
    return lines
        .map((line) => line.map(_csvValue).join(','))
        .join('\r\n');
  }

  Sheet _sheet(Excel workbook, String name) {
    final sheet = workbook[name];
    sheet.isRTL = true;
    if (workbook.tables.containsKey('Sheet1')) {
      workbook.delete('Sheet1');
    }
    return sheet;
  }

  void _headers(Sheet sheet, List<String> headers) {
    _row(sheet, headers);
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .cellStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
    }
  }

  void _row(Sheet sheet, List<Object> values) {
    sheet.appendRow([
      for (final value in values)
        if (value is int)
          IntCellValue(value)
        else if (value is double)
          DoubleCellValue(value)
        else
          TextCellValue(_safe(value.toString())),
    ]);
  }

  void _moneyRow(Sheet sheet, String title, Money money) {
    _row(sheet, [title, money.minorUnits / 100, money.currency]);
  }

  void _widths(Sheet sheet, List<double> widths) {
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  String _safe(String text) {
    final stripped = text.trimLeft();
    if (stripped.isNotEmpty &&
        const ['=', '+', '-', '@'].contains(stripped[0])) {
      return "'$text";
    }
    return text;
  }

  String _csvValue(String text) => '"${_safe(text).replaceAll('"', '""')}"';

  String _sourceLabel(String source) {
    switch (source) {
      case 'sale':
        return 'مبيعات';
      case 'saleReturn':
        return 'مردود مبيعات';
      case 'purchase':
        return 'مشتريات';
      case 'purchaseReturn':
        return 'مردود مشتريات';
      case 'expense':
        return 'مصروف';
      default:
        return _safe(source);
    }
  }

  String _paymentLabel(String? method) {
    switch (method) {
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
      case null:
      case 'unknown':
        return 'غير محدد';
      default:
        return _safe(method);
    }
  }
}
