import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/services/category_inventory_document_builder.dart';

class PdfCategoryInventoryDocumentBuilder
    implements CategoryInventoryDocumentBuilder {
  PdfCategoryInventoryDocumentBuilder({AssetBundle? assetBundle})
      : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;
  _CategoryPdfFonts? _fonts;

  @override
  Future<Uint8List> buildInventoryByCategory({
    required List<Category> categories,
    required Map<String, List<Product>> productsByCategory,
    required String storeName,
  }) async {
    final fonts = await _loadFonts();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(fonts),
        header: (context) => _pageHeader(context, fonts),
        footer: (context) => _pageFooter(context, fonts),
        build: (context) => _content(
          categories: categories,
          productsByCategory: productsByCategory,
          storeName: storeName,
          fonts: fonts,
        ),
      ),
    );
    return document.save();
  }

  Future<_CategoryPdfFonts> _loadFonts() async {
    final cached = _fonts;
    if (cached != null) {
      return cached;
    }
    final regularData = await _assetBundle.load(
      'assets/fonts/Rubik-Regular.ttf',
    );
    final boldData = await _assetBundle.load('assets/fonts/Rubik-Bold.ttf');
    final fonts = _CategoryPdfFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
    _fonts = fonts;
    return fonts;
  }

  pw.PageTheme _pageTheme(_CategoryPdfFonts fonts) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(20, 28, 20, 30),
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      textDirection: pw.TextDirection.rtl,
    );
  }

  pw.Widget _pageHeader(pw.Context context, _CategoryPdfFonts fonts) {
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
        'نظام إدارة المتجر - تقرير مخزون V2',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 9,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _pageFooter(pw.Context context, _CategoryPdfFonts fonts) {
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
            'مستند مولد من بيانات V2 المرحّلة',
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

  List<pw.Widget> _content({
    required List<Category> categories,
    required Map<String, List<Product>> productsByCategory,
    required String storeName,
    required _CategoryPdfFonts fonts,
  }) {
    final categoryData = [
      for (final category in categories)
        _categoryData(
          category,
          productsByCategory[category.id] ?? const <Product>[],
        ),
    ];
    final total = _sumCategoryData(categoryData);
    final widgets = <pw.Widget>[
      _title(
        storeName: storeName,
        fonts: fonts,
        subtitle: 'التاريخ: ${_formatDate(DateTime.now())}',
      ),
      pw.SizedBox(height: 12),
      _section(
        'ملخص المخزون',
        _summaryTable(total, fonts),
        fonts,
      ),
      pw.SizedBox(height: 14),
    ];

    for (final data in categoryData) {
      widgets.add(_categorySection(data, fonts));
      widgets.add(pw.SizedBox(height: 12));
    }

    if (categories.isEmpty) {
      widgets.add(
        pw.Text(
          'لا توجد تصنيفات ضمن المتجر.',
          style: pw.TextStyle(font: fonts.regular, fontSize: 10),
        ),
      );
    }
    return widgets;
  }

  _CategoryData _categoryData(Category category, List<Product> products) {
    var quantityMilliUnits = 0;
    for (final product in products) {
      quantityMilliUnits += product.quantityOnHand.milliUnits;
    }
    return _CategoryData(
      category: category,
      products: products,
      productCount: products.length,
      quantityMilliUnits: quantityMilliUnits,
      cost: _sum(products.map((product) => product.inventoryValue)),
      wholesale: _sum(
        products.map(
          (product) => _multiply(product.wholesalePrice, product.quantityOnHand),
        ),
      ),
      retail: _sum(
        products.map(
          (product) => _multiply(product.sellingPrice, product.quantityOnHand),
        ),
      ),
    );
  }

  _CategoryData _sumCategoryData(List<_CategoryData> values) {
    var quantityMilliUnits = 0;
    var productCount = 0;
    for (final value in values) {
      quantityMilliUnits += value.quantityMilliUnits;
      productCount += value.productCount;
    }
    return _CategoryData(
      category: const Category(
        id: 'total',
        storeId: 'total',
        name: 'الإجمالي',
      ),
      products: const <Product>[],
      productCount: productCount,
      quantityMilliUnits: quantityMilliUnits,
      cost: _sum(values.map((value) => value.cost)),
      wholesale: _sum(values.map((value) => value.wholesale)),
      retail: _sum(values.map((value) => value.retail)),
    );
  }

  pw.Widget _categorySection(_CategoryData data, _CategoryPdfFonts fonts) {
    final products = data.products;
    final rows = <pw.TableRow>[
      _tableRow(
        ['الصنف', 'الكمية', 'سعر الشراء', 'الجملة', 'البيع', 'قيمة التكلفة'],
        fonts: fonts,
        header: true,
      ),
      for (final product in products.take(1000))
        _tableRow(
          [
            product.name,
            product.quantityOnHand.formatted,
            product.purchasePrice.formatted,
            product.wholesalePrice.formatted,
            product.sellingPrice.formatted,
            product.inventoryValue.formatted,
          ],
          fonts: fonts,
        ),
    ];

    final children = <pw.Widget>[
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 9),
        decoration: pw.BoxDecoration(
          color: PdfColors.blue700,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                'التصنيف: ${data.category.name}',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 12,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Text(
              'التكلفة: ${data.cost.formatted}',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 9,
                color: PdfColors.white,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 5),
    ];

    if (products.isEmpty) {
      children.add(
        pw.Text(
          'لا توجد أصناف في هذا التصنيف.',
          style: pw.TextStyle(font: fonts.regular, fontSize: 9),
        ),
      );
    } else {
      children.add(
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.blue200, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.3),
            1: pw.FlexColumnWidth(0.9),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(1.2),
            5: pw.FlexColumnWidth(1.4),
          },
          children: rows,
        ),
      );
      if (products.length > 1000) {
        children.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5),
            child: pw.Text(
              'تم عرض أول 1000 صنف فقط داخل مستند الطباعة.',
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 8,
                color: PdfColors.orange900,
              ),
            ),
          ),
        );
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  pw.Widget _title({
    required String storeName,
    required String subtitle,
    required _CategoryPdfFonts fonts,
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
            'تقرير المخزون حسب التصنيف',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 20,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            storeName.trim().isEmpty ? 'متجر V2' : storeName.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 11,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            subtitle,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 10,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _section(
    String title,
    pw.Widget child,
    _CategoryPdfFonts fonts,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 13,
              color: PdfColors.blue900,
            ),
          ),
          pw.SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  pw.Widget _summaryTable(_CategoryData total, _CategoryPdfFonts fonts) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blue200, width: 0.6),
      columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)},
      children: [
        _tableRow(
          ['عدد الأصناف', total.productCount.toString()],
          fonts: fonts,
        ),
        _tableRow(
          ['إجمالي الكمية', _formatQuantity(total.quantityMilliUnits)],
          fonts: fonts,
        ),
        _tableRow(['قيمة التكلفة', total.cost.formatted], fonts: fonts),
        _tableRow(['قيمة الجملة', total.wholesale.formatted], fonts: fonts),
        _tableRow(['قيمة البيع', total.retail.formatted], fonts: fonts),
      ],
    );
  }

  pw.TableRow _tableRow(
    List<String> values, {
    required _CategoryPdfFonts fonts,
    bool header = false,
  }) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: header ? PdfColors.blue700 : PdfColors.white,
      ),
      children: [
        for (final value in values)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: header ? fonts.bold : fonts.regular,
                fontSize: 8,
                color: header ? PdfColors.white : PdfColors.blueGrey900,
              ),
            ),
          ),
      ],
    );
  }

  Money _sum(Iterable<Money> values) {
    Money? total;
    for (final value in values) {
      total = total == null ? value : total + value;
    }
    return total ?? const Money.zero();
  }

  Money _multiply(Money amount, Quantity quantity) {
    final numerator = amount.minorUnits * quantity.milliUnits;
    final minorUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Money(minorUnits: minorUnits, currency: amount.currency);
  }

  String _formatDate(DateTime value) {
    final date = value.toUtc();
    return '${date.year.toString().padLeft(4, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatQuantity(int milliUnits) {
    return Quantity.fromMilliUnits(milliUnits).formatted;
  }
}

class _CategoryData {
  const _CategoryData({
    required this.category,
    required this.products,
    required this.productCount,
    required this.quantityMilliUnits,
    required this.cost,
    required this.wholesale,
    required this.retail,
  });

  final Category category;
  final List<Product> products;
  final int productCount;
  final int quantityMilliUnits;
  final Money cost;
  final Money wholesale;
  final Money retail;
}

class _CategoryPdfFonts {
  const _CategoryPdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}
