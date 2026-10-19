import 'package:cloud_firestore/cloud_firestore.dart';

abstract final class FirebasePaths {
  static DocumentReference<Map<String, dynamic>> store(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return firestore.collection('stores').doc(storeId);
  }

  static CollectionReference<Map<String, dynamic>> members(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('members');
  }

  static CollectionReference<Map<String, dynamic>> accounts(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('accounts');
  }

  static CollectionReference<Map<String, dynamic>> journalEntries(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('journal_entries');
  }

  static CollectionReference<Map<String, dynamic>> accountBalances(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('account_balances');
  }

  static CollectionReference<Map<String, dynamic>> idempotencyKeys(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('idempotency_keys');
  }
}
