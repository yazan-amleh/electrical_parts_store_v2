import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/repair_payment.dart';
import '../../domain/entities/repair_request.dart';
import '../../domain/enums/device_condition.dart';
import '../../domain/enums/repair_payment_kind.dart';
import '../../domain/enums/repair_status.dart';
import '../../../payments/domain/enums/party_payment_method.dart';
import '../../domain/services/repair_document_builder.dart';

class PdfRepairDocumentBuilder implements RepairDocumentBuilder {
  PdfRepairDocumentBuilder({AssetBundle? assetBundle})
      : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;
  _RepairPdfFonts? _fonts;

  @override
  Future<Uint8List> buildRepairRequest({
    required RepairRequest repair,
    required String storeName,
    required String customerName,
    String? customerPhone,
  }) async {
    final fonts = await _loadFonts();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(fonts),
        header: (context) => _pageHeader(context, fonts),
        footer: (context) => _pageFooter(context, fonts),
        build: (context) => _repairRequestContent(
          repair: repair,
          storeName: storeName,
          customerName: customerName,
          customerPhone: customerPhone,
          fonts: fonts,
        ),
      ),
    );
    return document.save();
  }

  @override
  Future<Uint8List> buildPaymentReceipt({
    required RepairPayment payment,
    required RepairRequest repair,
    required String storeName,
    required String customerName,
    String? customerPhone,
  }) async {
    final fonts = await _loadFonts();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(fonts),
        header: (context) => _pageHeader(context, fonts),
        footer: (context) => _pageFooter(context, fonts),
        build: (context) => _paymentReceiptContent(
          payment: payment,
          repair: repair,
          storeName: storeName,
          customerName: customerName,
          customerPhone: customerPhone,
          fonts: fonts,
        ),
      ),
    );
    return document.save();
  }

  Future<_RepairPdfFonts> _loadFonts() async {
    final cached = _fonts;
    if (cached != null) {
      return cached;
    }
    final regularData = await _assetBundle.load(
      'assets/fonts/Rubik-Regular.ttf',
    );
    final boldData = await _assetBundle.load('assets/fonts/Rubik-Bold.ttf');
    final fonts = _RepairPdfFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
    _fonts = fonts;
    return fonts;
  }

  pw.PageTheme _pageTheme(_RepairPdfFonts fonts) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 34, 28, 32),
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      textDirection: pw.TextDirection.rtl,
    );
  }

  pw.Widget _pageHeader(pw.Context context, _RepairPdfFonts fonts) {
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
        'نظام إدارة المتجر - مستند صيانة V2',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 9,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _pageFooter(pw.Context context, _RepairPdfFonts fonts) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'صفحة ' +
                context.pageNumber.toString() +
                ' من ' +
                context.pagesCount.toString(),
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

  List<pw.Widget> _repairRequestContent({
    required RepairRequest repair,
    required String storeName,
    required String customerName,
    required String? customerPhone,
    required _RepairPdfFonts fonts,
  }) {
    final content = <pw.Widget>[
      _title(
        title: 'تفاصيل طلب الإصلاح',
        subtitle: 'طلب رقم ' + repair.id,
        storeName: storeName,
        fonts: fonts,
      ),
      pw.SizedBox(height: 12),
      _section(
        'معلومات الطلب',
        [
          _valueLine('الحالة', repair.status.arabicLabel, fonts),
          _valueLine('تاريخ الاستلام', _formatDate(repair.receivedAt), fonts),
          _valueLine(
            'التسليم المتوقع',
            _formatDate(repair.expectedDeliveryDate),
            fonts,
          ),
          _valueLine(
            'التسليم الفعلي',
            _formatOptionalDate(repair.actualDeliveryDate),
            fonts,
          ),
          _valueLine('الأولوية', repair.priority.arabicLabel, fonts),
        ],
        fonts,
      ),
      pw.SizedBox(height: 10),
      _section(
        'معلومات العميل',
        [
          _valueLine(
            'الاسم',
            customerName.trim().isEmpty ? repair.customerId : customerName,
            fonts,
          ),
          _valueLine(
            'رقم الهاتف',
            customerPhone?.trim().isNotEmpty == true
                ? customerPhone!
                : 'غير متوفر',
            fonts,
          ),
          _valueLine('معرّف العميل', repair.customerId, fonts),
        ],
        fonts,
      ),
      pw.SizedBox(height: 10),
      _section(
        'معلومات الجهاز',
        [
          _valueLine('نوع الجهاز', repair.deviceName, fonts),
          _valueLine('الموديل', repair.deviceModel, fonts),
          _valueLine(
            'الرقم التسلسلي',
            repair.serialNumber.trim().isEmpty
                ? 'غير متوفر'
                : repair.serialNumber,
            fonts,
          ),
          _valueLine('حالة الجهاز', repair.deviceCondition.arabicLabel, fonts),
          if (repair.deviceConditionNotes.trim().isNotEmpty)
            _valueLine(
              'ملاحظات الحالة',
              repair.deviceConditionNotes,
              fonts,
            ),
        ],
        fonts,
      ),
      pw.SizedBox(height: 10),
      _section(
        'معلومات الإصلاح',
        [
          _valueLine(
            'وصف المشكلة',
            repair.problemDescription.trim().isEmpty
                ? 'لا يوجد وصف'
                : repair.problemDescription,
            fonts,
          ),
          if (repair.technicianNotes.trim().isNotEmpty)
            _valueLine('ملاحظات الفني', repair.technicianNotes, fonts),
          if (repair.requiredParts.isNotEmpty)
            _valueLine(
              'القطع المطلوبة',
              repair.requiredParts.join('، '),
              fonts,
            ),
        ],
        fonts,
      ),
      pw.SizedBox(height: 10),
      _section(
        'قطع الغيار المستخدمة',
        [_partsTable(repair, fonts)],
        fonts,
      ),
      pw.SizedBox(height: 10),
      _section(
        'الملخص المالي',
        [
          _valueLine('أجرة العمل', repair.laborCost.formatted, fonts),
          _valueLine('قيمة القطع', repair.partsTotal.formatted, fonts),
          _valueLine('التكلفة النهائية', repair.finalCost.formatted, fonts),
          _valueLine('الدفعة المقدمة', repair.advancePaid.formatted, fonts),
          _valueLine('المدفوع بعد الفاتورة', repair.paid.formatted, fonts),
          _valueLine('الإجمالي المفوتر', repair.invoicedTotal.formatted, fonts),
          _valueLine('المتبقي', repair.outstanding.formatted, fonts),
        ],
        fonts,
      ),
    ];
    return content;
  }

  List<pw.Widget> _paymentReceiptContent({
    required RepairPayment payment,
    required RepairRequest repair,
    required String storeName,
    required String customerName,
    required String? customerPhone,
    required _RepairPdfFonts fonts,
  }) {
    return [
      _title(
        title: 'إيصال دفع صيانة',
        subtitle: 'إيصال رقم ' + payment.id,
        storeName: storeName,
        fonts: fonts,
      ),
      pw.SizedBox(height: 12),
      _section(
        'تفاصيل الدفعة',
        [
          _valueLine('التاريخ', _formatDateTime(payment.postedAt), fonts),
          _valueLine('نوع الدفعة', payment.kind.arabicLabel, fonts),
          _valueLine(
            'طريقة الدفع',
            _paymentMethodLabel(payment.paymentMethod),
            fonts,
          ),
          _valueLine('المبلغ', payment.amount.formatted, fonts),
          if (payment.description?.trim().isNotEmpty == true)
            _valueLine('الوصف', payment.description!, fonts),
          if (payment.chequeNumber?.trim().isNotEmpty == true)
            _valueLine('رقم الشيك', payment.chequeNumber!, fonts),
          if (payment.bankName?.trim().isNotEmpty == true)
            _valueLine('البنك', payment.bankName!, fonts),
          if (payment.dueDate != null)
            _valueLine('تاريخ الاستحقاق', _formatDate(payment.dueDate!), fonts),
        ],
        fonts,
      ),
      pw.SizedBox(height: 10),
      _section(
        'معلومات العميل',
        [
          _valueLine(
            'الاسم',
            customerName.trim().isEmpty ? repair.customerId : customerName,
            fonts,
          ),
          _valueLine(
            'رقم الهاتف',
            customerPhone?.trim().isNotEmpty == true
                ? customerPhone!
                : 'غير متوفر',
            fonts,
          ),
        ],
        fonts,
      ),
      pw.SizedBox(height: 10),
      _section(
        'معلومات طلب الصيانة',
        [
          _valueLine('رقم الطلب', repair.id, fonts),
          _valueLine(
            'الجهاز',
            repair.deviceName + ' — ' + repair.deviceModel,
            fonts,
          ),
          _valueLine('الإجمالي المفوتر', repair.invoicedTotal.formatted, fonts),
          _valueLine('إجمالي المدفوع', repair.paid.formatted, fonts),
          _valueLine('المتبقي', repair.outstanding.formatted, fonts),
        ],
        fonts,
      ),
      pw.SizedBox(height: 24),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.blue200),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text(
          'تم إصدار هذا الإيصال من نظام V2 بناءً على دفعة مرحّلة.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: fonts.regular, fontSize: 9),
        ),
      ),
    ];
  }

  pw.Widget _title({
    required String title,
    required String subtitle,
    required String storeName,
    required _RepairPdfFonts fonts,
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
    List<pw.Widget> children,
    _RepairPdfFonts fonts,
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
          ...children,
        ],
      ),
    );
  }

  pw.Widget _valueLine(String label, String value, _RepairPdfFonts fonts) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 115,
            child: pw.Text(
              label,
              style: pw.TextStyle(font: fonts.bold, fontSize: 9),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: fonts.regular, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _partsTable(RepairRequest repair, _RepairPdfFonts fonts) {
    if (repair.parts.isEmpty) {
      return pw.Text(
        'لم يتم استخدام أي قطع غيار.',
        style: pw.TextStyle(font: fonts.regular, fontSize: 9),
      );
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blue200, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.4),
      },
      children: [
        _tableRow(
          ['القطعة', 'الكمية', 'سعر الوحدة', 'الإجمالي'],
          fonts: fonts,
          header: true,
        ),
        for (final part in repair.parts)
          _tableRow(
            [
              part.productName,
              _formatQuantity(part.quantity.milliUnits),
              part.unitPrice.formatted,
              part.totalPrice.formatted,
            ],
            fonts: fonts,
          ),
      ],
    );
  }

  pw.TableRow _tableRow(
    List<String> values, {
    required _RepairPdfFonts fonts,
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

  String _formatDate(DateTime value) {
    final date = value.toUtc();
    return date.year.toString().padLeft(4, '0') +
        '/' +
        date.month.toString().padLeft(2, '0') +
        '/' +
        date.day.toString().padLeft(2, '0');
  }

  String _formatDateTime(DateTime value) {
    final date = value.toUtc();
    return _formatDate(date) +
        ' ' +
        date.hour.toString().padLeft(2, '0') +
        ':' +
        date.minute.toString().padLeft(2, '0');
  }

  String _formatOptionalDate(DateTime? value) {
    return value == null ? '—' : _formatDate(value);
  }

  String _formatQuantity(int milliUnits) {
    final sign = milliUnits < 0 ? '-' : '';
    final absolute = milliUnits.abs();
    final major = absolute ~/ 1000;
    final fraction = (absolute % 1000).toString().padLeft(3, '0');
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.isEmpty
        ? sign + major.toString()
        : sign + major.toString() + '.' + trimmed;
  }

  String _paymentMethodLabel(PartyPaymentMethod method) {
    switch (method) {
      case PartyPaymentMethod.cash:
        return 'نقدي';
      case PartyPaymentMethod.bank:
        return 'بنك';
      case PartyPaymentMethod.card:
        return 'بطاقة';
      case PartyPaymentMethod.cheque:
        return 'شيك';
    }
  }
}

class _RepairPdfFonts {
  const _RepairPdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}
