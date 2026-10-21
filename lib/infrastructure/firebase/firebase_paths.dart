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

  static CollectionReference<Map<String, dynamic>> chatRooms(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('chatRooms');
  }

  static DocumentReference<Map<String, dynamic>> chatRoom(
    FirebaseFirestore firestore,
    String storeId,
    String roomId,
  ) {
    return chatRooms(firestore, storeId).doc(roomId);
  }

  static CollectionReference<Map<String, dynamic>> chatMessages(
    FirebaseFirestore firestore,
    String storeId,
    String roomId,
  ) {
    return chatRoom(firestore, storeId, roomId).collection('messages');
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

  static CollectionReference<Map<String, dynamic>> parties(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('parties');
  }

  static CollectionReference<Map<String, dynamic>> categories(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('categories');
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

  static CollectionReference<Map<String, dynamic>> offers(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('offers');
  }

  static CollectionReference<Map<String, dynamic>> offerIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('offer_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> offerOrders(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('offer_orders');
  }

  static CollectionReference<Map<String, dynamic>> offerOrderIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('offer_order_idempotency');
  }

  static CollectionReference<Map<String, dynamic>>
      offerOrderConfirmationIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(
      firestore,
      storeId,
    ).collection('offer_order_confirmation_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> purchases(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('purchases');
  }

  static CollectionReference<Map<String, dynamic>> purchaseOrders(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('purchase_orders');
  }

  static CollectionReference<Map<String, dynamic>>
      purchaseOrderReceiptIdempotency(
          FirebaseFirestore firestore, String storeId) {
    return store(
      firestore,
      storeId,
    ).collection('purchase_order_receipt_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> purchaseIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('purchase_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> commandOutbox(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('command_outbox');
  }

  static CollectionReference<Map<String, dynamic>> accountTransfers(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('account_transfers');
  }

  static CollectionReference<Map<String, dynamic>> accountTransferIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('account_transfer_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> expenses(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('expenses');
  }

  static CollectionReference<Map<String, dynamic>> expenseIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('expense_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> partyPayments(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('party_payments');
  }

  static CollectionReference<Map<String, dynamic>> repairs(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('repairs');
  }

  static CollectionReference<Map<String, dynamic>> repairPayments(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('party_payments');
  }

  static CollectionReference<Map<String, dynamic>> repairPaymentIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('repair_payment_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> chequeSettlementIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(
      firestore,
      storeId,
    ).collection('cheque_settlement_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> partyPaymentIdempotency(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('party_payment_idempotency');
  }

  static CollectionReference<Map<String, dynamic>> partyLedgerEntries(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('party_ledger_entries');
  }

  static CollectionReference<Map<String, dynamic>> partyBalances(
    FirebaseFirestore firestore,
    String storeId,
  ) {
    return store(firestore, storeId).collection('party_balances');
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
