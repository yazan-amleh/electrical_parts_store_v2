import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/repositories/notification_repository.dart';

class FirebaseNotificationRepository implements NotificationRepository {
  FirebaseNotificationRepository({
    required FirebaseFirestore firestore,
    FirebaseMessaging? messaging,
  })  : _firestore = firestore,
        _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;

  @override
  Future<Result<void>> registerCurrentDevice({
    required StoreContext context,
  }) async {
    if (context.storeId.trim().isEmpty || context.userId.trim().isEmpty) {
      return const FailureResult<void>(
        ValidationFailure('A store and user are required for notifications.'),
      );
    }

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return const FailureResult<void>(
          AuthorizationFailure('Notification permission was denied.'),
        );
      }
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) {
        return const FailureResult<void>(
          InfrastructureFailure(
              'The device did not return a notification token.'),
        );
      }

      await _tokenReference(context, token).set(<String, dynamic>{
        'storeId': context.storeId,
        'userId': context.userId,
        'token': token,
        'platform': _platform,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        _mapFailure(error, 'Notifications could not be enabled.'),
      );
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<void>> unregisterCurrentDevice({
    required StoreContext context,
  }) async {
    if (context.storeId.trim().isEmpty || context.userId.trim().isEmpty) {
      return const FailureResult<void>(
        ValidationFailure('A store and user are required for notifications.'),
      );
    }

    try {
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) {
        return const Success<void>(null);
      }
      await _tokenReference(context, token).delete();
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        _mapFailure(error, 'Notifications could not be disabled.'),
      );
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }

  DocumentReference<Map<String, dynamic>> _tokenReference(
    StoreContext context,
    String token,
  ) {
    final tokenId = base64Url.encode(utf8.encode(token)).replaceAll('=', '');
    return _firestore
        .collection('stores')
        .doc(context.storeId)
        .collection('notificationTokens')
        .doc(tokenId);
  }

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Failure _mapFailure(FirebaseException error, String fallback) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(error.message ?? fallback);
      default:
        return InfrastructureFailure(error.message ?? fallback);
    }
  }
}
