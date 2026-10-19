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

  static CollectionReference<Map<String, dynamic>> products(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('products');
  }

  static CollectionReference<Map<String, dynamic>> sales(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('sales');
  }

  static CollectionReference<Map<String, dynamic>> saleIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('sale_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> purchases(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('purchases');
  }

  static CollectionReference<Map<String, dynamic>> purchaseIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('purchase_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> journalEntries(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('journal_entries');
  }

  static CollectionReference<Map<String, dynamic>> inventoryMovements(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('inventory_movements');
  }

  static CollectionReference<Map<String, dynamic>> inventoryIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('inventory_idempotency');
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
