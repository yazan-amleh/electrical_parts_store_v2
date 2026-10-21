import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../categories/domain/entities/category.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../../inventory/domain/entities/product.dart';
import '../../inventory/domain/repositories/product_repository.dart';
import '../../reports/domain/entities/operational_report.dart';
import '../../reports/domain/repositories/reports_repository.dart';

class StoreAssistantService {
  StoreAssistantService({
    required this.productRepository,
    required this.categoryRepository,
    required this.reportsRepository,
  });

  final ProductRepository productRepository;
  final CategoryRepository categoryRepository;
  final ReportsRepository reportsRepository;

  Future<String> answer({
    required StoreContext context,
    required String message,
  }) async {
    final query = message.trim().toLowerCase();
    if (query.isEmpty) {
      return 'اكتب سؤالاً عن المبيعات أو المخزون أو التصنيفات.';
    }
    if (query.contains('مبيع') ||
        query.contains('ربح') ||
        query.contains('دخل')) {
      return _salesAnswer(context, query);
    }
    if (query.contains('مخزون') ||
        query.contains('منتج') ||
        query.contains('قطعة')) {
      return _inventoryAnswer(context, query);
    }
    if (query.contains('تصنيف') || query.contains('فئة')) {
      return _categoryAnswer(context);
    }
    if (query.contains('مرحبا') ||
        query.contains('السلام') ||
        query.contains('مساعد')) {
      return 'مرحباً. اسألني عن مبيعات اليوم، مخزون الأصناف، أو عدد التصنيفات.';
    }
    return 'أستطيع مساعدتك في المبيعات والمخزون والتصنيفات. جرّب سؤالاً محدداً.';
  }

  Future<String> _salesAnswer(
    StoreContext context,
    String query,
  ) async {
    final now = DateTime.now().toUtc();
    final from = query.contains('اليوم')
        ? DateTime.utc(now.year, now.month, now.day)
        : DateTime.utc(now.year, now.month, 1);
    final result = await reportsRepository.getOperationalReport(
      context: context,
      from: from,
      to: now,
      limit: 500,
      maxDocuments: 10000,
    );
    if (result is FailureResult<OperationalReport>) {
      return 'تعذر تحميل تقرير المبيعات: ' + result.failure.message;
    }
    final report = (result as Success<OperationalReport>).value;
    final period = query.contains('اليوم') ? 'اليوم' : 'هذا الشهر';
    return 'مبيعات ' +
        period +
        ': ' +
        report.salesRevenue.formatted +
        '\nعدد العمليات: ' +
        report.salesCount.toString() +
        '\nالربح الإجمالي: ' +
        report.grossProfit.formatted;
  }

  Future<String> _inventoryAnswer(StoreContext context) async {
    final result = await productRepository.getProducts(context: context);
    if (result is FailureResult<List<Product>>) {
      return 'تعذر تحميل المخزون: ' + result.failure.message;
    }
    final products = (result as Success<List<Product>>).value;
    final lowStock = products.where((product) => product.isLowStock).toList();
    if (lowStock.isEmpty) {
      return 'لا توجد أصناف منخفضة المخزون حالياً.';
    }
    final names = lowStock.take(5).map((product) => product.name).join('، ');
    return 'الأصناف منخفضة المخزون (' +
        lowStock.length.toString() +
        '): ' +
        names;
  }

  Future<String> _categoryAnswer(StoreContext context) async {
    final result = await categoryRepository.getCategories(context: context);
    if (result is FailureResult<List<Category>>) {
      return 'تعذر تحميل التصنيفات: ' + result.failure.message;
    }
    final categories = (result as Success<List<Category>>).value;
    return 'عدد التصنيفات النشطة: ' + categories.length.toString();
  }
}
