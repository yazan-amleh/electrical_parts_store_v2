import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/repositories/accounting_repository.dart';

class PostJournalEntry {
  const PostJournalEntry(this.repository);

  final AccountingRepository repository;

  Future<Result<JournalEntry>> call({
    required StoreContext context,
    required JournalEntry entry,
  }) async {
    if (entry.storeId != context.storeId) {
      return const FailureResult(
        ValidationFailure('Journal entry belongs to another store.'),
      );
    }

    try {
      entry.validateForPosting();
    } on ArgumentError catch (error) {
      return FailureResult(ValidationFailure(error.message.toString()));
    }

    return repository.postJournalEntry(context: context, entry: entry);
  }
}
