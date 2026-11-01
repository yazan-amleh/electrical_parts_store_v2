import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/note.dart';

abstract interface class NoteRepository {
  Future<Result<List<Note>>> getNotes({
    required StoreContext context,
    bool includeArchived = false,
    bool starredOnly = false,
  });

  Future<Result<void>> saveNote({
    required StoreContext context,
    required Note note,
  });

  Future<Result<void>> deleteNote({
    required StoreContext context,
    required Note note,
  });
}
