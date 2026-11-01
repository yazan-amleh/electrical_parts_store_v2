import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/inventory_movement.dart';
import '../../domain/entities/product.dart';
import '../../domain/enums/inventory_movement_type.dart';

/// Read-only printable product card. Its posted on-hand value is authoritative
/// for the snapshot; the limited movement list must not be used to invent a
/// historical running balance or reconstruct missing prior transactions.
class PdfProductHistoryDocumentBuilder {
  PdfProductHistoryDocumentBuilder({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  Future<Uint8List> build({
    required Product product,
    required List<InventoryMovement> movements,
    required String expectedStoreId,
    required bool historyMayBeTruncated,
  }) async {
    if (expectedStoreId.trim().isEmpty ||
        product.storeId != expectedStoreId ||
        movements.any((entry) =>
            entry.storeId != expectedStoreId ||
            entry.productId != product.id)) {
      throw StateError(
          'Product history belongs to a different store or product.');
    }
    final font = pw.Font.ttf(
      await _bundle.load('assets/fonts/Rubik-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await _bundle.load('assets/fonts/Rubik-Bold.ttf'),
    );
    final document = pw.Document();
    final incoming = movements
        .where((m) => m.quantityDelta.milliUnits > 0)
        .fold<int>(0, (sum, m) => sum + m.quantityDelta.milliUnits);
    final outgoing = movements
        .where((m) => m.quantityDelta.milliUnits < 0)
        .fold<int>(0, (sum, m) => sum - m.quantityDelta.milliUnits);
    String quantity(int milli) => (milli / 1000).toStringAsFixed(3);
    String stamp(DateTime value) {
      final v = value.toLocal();
      return '${v.year}/${v.month.toString().padLeft(2, '0')}/'
          '${v.day.toString().padLeft(2, '0')} '
          '${v.hour.toString().padLeft(2, '0')}:'
          '${v.minute.toString().padLeft(2, '0')}';
    }

    final title =
        pw.TextStyle(font: bold, color: PdfColors.blue800, fontSize: 17);
    final label = pw.TextStyle(font: font, fontSize: 9);

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(26),
          theme: pw.ThemeData.withFont(base: font, bold: bold),
          textDirection: pw.TextDirection.rtl,
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('الصفحة ${context.pageNumber}/${context.pagesCount}',
                style: label),
            pw.Text('تقرير اطلاع فقط — لا ينشئ قيدًا أو تسوية', style: label),
          ],
        ),
        build: (_) => [
          pw.Text('بطاقة الصنف وكشف حركاته', style: title),
          pw.SizedBox(height: 8),
          pw.Text('المتجر: $expectedStoreId    الصنف: ${product.name}',
              style: pw.TextStyle(font: bold, fontSize: 12)),
          pw.Text(
              'SKU: ${product.sku ?? '-'}    الباركود: ${product.barcode ?? '-'}',
              style: label),
          pw.Text(
            'الرصيد الحالي المسجل: ${product.quantityOnHand.formatted}'
            '    حد الطلب: ${product.minimumQuantity.formatted}'
            '    قيمة المخزون المسجلة: ${product.inventoryValue.formatted}',
            style: label,
          ),
          pw.Text(
            'عدد الحركات المحمّلة: ${movements.length}    '
            'وارد ضمن الحركات المحمّلة: ${quantity(incoming)}    '
            'صادر ضمن الحركات المحمّلة: ${quantity(outgoing)}',
            style: label,
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            historyMayBeTruncated
                ? 'تنبيه: هذا كشف جزئي لآخر 500 حركة فقط؛ '
                    'لا تُستخدم هذه الحركات لحساب رصيد افتتاحي أو مطابقة تاريخية.'
                : 'البيانات من الحركات المتاحة بالمستودع عند وقت التصدير؛ '
                    'لا يمثل التقرير مصادقة على المطابقة المحاسبية.',
            style: pw.TextStyle(
              font: bold,
              fontSize: 9,
              color: PdfColors.deepOrange800,
            ),
          ),
          pw.SizedBox(height: 12),
          if (movements.isEmpty)
            pw.Text('لا توجد حركات مسجلة ضمن البيانات المحمّلة.', style: label)
          else
            pw.Table.fromTextArray(
              headers: const [
                'التاريخ',
                'نوع الحركة',
                'وارد',
                'صادر',
                'التكلفة',
                'المرجع',
                'الوصف',
              ],
              data: [
                for (final movement in movements)
                  [
                    stamp(movement.occurredAt),
                    _typeLabel(movement.type),
                    movement.quantityDelta.milliUnits > 0
                        ? movement.quantityDelta.formatted
                        : '—',
                    movement.quantityDelta.milliUnits < 0
                        ? quantity(-movement.quantityDelta.milliUnits)
                        : '—',
                    movement.totalCost.formatted,
                    movement.sourceId ?? movement.sourceType,
                    movement.description,
                  ],
              ],
              headerStyle:
                  pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
              cellStyle: pw.TextStyle(font: font, fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blue800),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
              cellAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(
                color: PdfColors.blue100,
                width: 0.4,
              ),
            ),
        ],
      ),
    );
    return document.save();
  }

  static String _typeLabel(InventoryMovementType type) {
    switch (type) {
      case InventoryMovementType.openingBalance:
        return 'رصيد افتتاحي';
      case InventoryMovementType.purchaseReceipt:
        return 'استلام شراء';
      case InventoryMovementType.saleIssue:
        return 'صرف بيع';
      case InventoryMovementType.purchaseReturn:
        return 'مرتجع شراء';
      case InventoryMovementType.saleReturn:
        return 'مرتجع بيع';
      case InventoryMovementType.adjustment:
        return 'تسوية مخزون';
      case InventoryMovementType.transferIn:
        return 'تحويل وارد';
      case InventoryMovementType.transferOut:
        return 'تحويل صادر';
    }
  }
}
