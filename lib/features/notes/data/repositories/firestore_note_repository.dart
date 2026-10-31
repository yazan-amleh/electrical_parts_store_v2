import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';
import '../mappers/note_firestore_mapper.dart';

class FirestoreNoteRepository implements NoteRepository {
  FirestoreNoteRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<Note>>> getNotes({
    required StoreContext context,
    bool includeArchived = false,
    bool starredOnly = false,
  }) async {
    if (context.storeId.trim().isEmpty || context.userId.trim().isEmpty) {
      return const FailureResult<List<Note>>(
        ValidationFailure('A store and user are required to read notes.'),
      );
    }

    try {
      final snapshot = await FirebasePaths.notes(
        _firestore,
        context.storeId,
      ).where('userId', isEqualTo: context.userId).get();

      final notes = snapshot.docs
          .map(NoteFirestoreMapper.fromSnapshot)
          .where(
            (note) =>
                note.storeId == context.storeId &&
                note.userId == context.userId &&
                (includeArchived || !note.isArchived) &&
                (!starredOnly || note.isStarred),
          )
          .toList()
        ..sort((left, right) {
          final priority = right.priority.index.compareTo(left.priority.index);
          if (priority != 0) {
            return priority;
          }
          if (left.isCompleted != right.isCompleted) {
            return left.isCompleted ? 1 : -1;
          }
          return right.createdAt.compareTo(left.createdAt);
        });
      return Success<List<Note>>(notes);
    } on FirebaseException catch (error) {
      return FailureResult<List<Note>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<Note>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> saveNote({
    required StoreContext context,
    required Note note,
  }) async {
    if (note.storeId != context.storeId || note.userId != context.userId) {
      return const FailureResult<void>(
        AuthorizationFailure('Note does not belong to the active user/store.'),
      );
    }
    if (note.id.trim().isEmpty || note.id.contains('/')) {
      return const FailureResult<void>(
        ValidationFailure('Note id is invalid.'),
      );
    }

    try {
      await FirebasePaths.notes(
        _firestore,
        context.storeId,
      ).doc(note.id).set(NoteFirestoreMapper.toMap(note));
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<void>> deleteNote({
    required StoreContext context,
    required Note note,
  }) async {
    if (context.storeId.trim().isEmpty ||
        context.userId.trim().isEmpty ||
        note.storeId != context.storeId ||
        note.userId != context.userId) {
      return const FailureResult<void>(
        AuthorizationFailure('Note does not belong to the active user/store.'),
      );
    }
    if (note.id.trim().isEmpty || note.id.contains('/')) {
      return const FailureResult<void>(
        ValidationFailure('Note id is invalid.'),
      );
    }
    try {
      await FirebasePaths.notes(
        _firestore,
        context.storeId,
      ).doc(note.id).delete();
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
