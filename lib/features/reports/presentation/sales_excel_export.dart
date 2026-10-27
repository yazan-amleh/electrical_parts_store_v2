import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../domain/entities/sales_analytics.dart';
import '../domain/entities/sales_invoice_report.dart';

class SalesExcelExport {
  const SalesExcelExport();

  Uint8List invoices({
    required List<SalesInvoiceSummary> invoices,
    required Map<String, String> customerNames,
  }) {
    final workbook = Excel.createExcel();
    final sheet = _sheet(workbook, 'تفاصيل المبيعات');
    _headers(sheet, const [
      'رقم الفاتورة',
      'التاريخ',
      'العميل',
      'طريقة الدفع',
      'قبل الضريبة',
      'الضريبة',
      'الإجمالي',
      'التكلفة',
      'العملة',
      'مرجع القيد',
    ]);

    for (final invoice in invoices) {
      sheet.appendRow([
        TextCellValue(invoice.id),
        TextCellValue(invoice.postedAt.toUtc().toIso8601String()),
        TextCellValue(
          _safeText(
            customerNames[invoice.customerId] ??
                invoice.customerId ??
                'بدون عميل',
          ),
        ),
        TextCellValue(_paymentLabel(invoice.paymentMethod)),
        DoubleCellValue(_major(invoice.subtotal.minorUnits)),
        DoubleCellValue(_major(invoice.tax.minorUnits)),
        DoubleCellValue(_major(invoice.total.minorUnits)),
        DoubleCellValue(_major(invoice.cost.minorUnits)),
        TextCellValue(invoice.total.currency),
        TextCellValue(_safeText(invoice.journalEntryId)),
      ]);
    }

    _widths(sheet, const [18, 24, 28, 16, 16, 14, 16, 16, 12, 24]);
    return _encode(workbook);
  }

  Uint8List topProducts({
    required List<SalesAnalyticsRow> products,
    required List<SalesAnalyticsRow> categories,
  }) {
    final workbook = Excel.createExcel();
    final productsSheet = _sheet(workbook, 'الأصناف الأكثر مبيعاً');
    _analyticsHeaders(productsSheet, includeQuantity: true);
    _analyticsRows(productsSheet, products, includeQuantity: true);
    _widths(productsSheet, const [30, 14, 18, 18, 18, 12]);

    final categoriesSheet = _sheet(workbook, 'المبيعات حسب التصنيف');
    _analyticsHeaders(categoriesSheet, includeQuantity: true);
    _analyticsRows(categoriesSheet, categories, includeQuantity: true);
    _widths(categoriesSheet, const [30, 14, 18, 18, 18, 12]);

    return _encode(workbook);
  }

  Uint8List customers({
    required List<SalesAnalyticsRow> customers,
    required Map<String, int> paymentMethodCounts,
  }) {
    final workbook = Excel.createExcel();
    final customerSheet = _sheet(workbook, 'ملخص العملاء');
    _analyticsHeaders(customerSheet, includeQuantity: false);
    _analyticsRows(customerSheet, customers, includeQuantity: false);
    _widths(customerSheet, const [30, 18, 18, 18, 12]);

    final paymentSheet = _sheet(workbook, 'طرق الدفع');
    _headers(paymentSheet, const ['طريقة الدفع', 'عدد الفواتير']);
    for (final entry in paymentMethodCounts.entries) {
      paymentSheet.appendRow([
        TextCellValue(_paymentLabel(entry.key)),
        IntCellValue(entry.value),
      ]);
    }
    _widths(paymentSheet, const [24, 18]);

    return _encode(workbook);
  }

  Sheet _sheet(Excel workbook, String name) {
    final sheet = workbook[name];
    sheet.isRTL = true;
    if (name != 'Sheet1' && workbook.tables.containsKey('Sheet1')) {
      workbook.delete('Sheet1');
    }
    return sheet;
  }

  void _analyticsHeaders(Sheet sheet, {required bool includeQuantity}) {
    _headers(sheet, [
      'الاسم',
      if (includeQuantity) 'الكمية',
      'المبيعات',
      'التكلفة',
      'مجمل الربح',
      'العملة',
    ]);
  }

  void _analyticsRows(
    Sheet sheet,
    List<SalesAnalyticsRow> rows, {
    required bool includeQuantity,
  }) {
    for (final row in rows) {
      sheet.appendRow([
        TextCellValue(_safeText(row.label)),
        if (includeQuantity)
          DoubleCellValue(row.quantityMilliUnits / 1000.0),
        DoubleCellValue(_major(row.revenue.minorUnits)),
        DoubleCellValue(_major(row.cost.minorUnits)),
        DoubleCellValue(_major(row.grossProfit.minorUnits)),
        TextCellValue(row.revenue.currency),
      ]);
    }
  }

  void _headers(Sheet sheet, List<String> headers) {
    sheet.appendRow([
      for (final header in headers) TextCellValue(header),
    ]);
    for (var column = 0; column < headers.length; column++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
          .cellStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
    }
  }

  void _widths(Sheet sheet, List<double> widths) {
    for (var index = 0; index < widths.length; index++) {
      sheet.setColumnWidth(index, widths[index]);
    }
  }

  Uint8List _encode(Excel workbook) {
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Unable to encode sales XLSX workbook.');
    }
    return Uint8List.fromList(bytes);
  }

  String _safeText(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.isNotEmpty &&
        const ['=', '+', '-', '@'].contains(trimmed.substring(0, 1))) {
      return "'$value";
    }
    return value;
  }

  double _major(int minorUnits) => minorUnits / 100.0;

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
        return _safeText(value);
    }
  }
}
