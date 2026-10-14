import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../data/notifications.dart';

/// Firebase Cloud Messaging. Every install listens on the "all" topic, so a
/// message sent from the Firebase console (Messaging > New campaign > topic
/// "all") reaches everyone, e.g. "New firmware available". Signed-in users
/// also store their device token for messages to one person later.
class PushService {
  PushService(this._notifications);

  final NotificationService _notifications;
  static const topicAll = 'all';

  Future<void> init() async {
    try {
      // The system shows messages while the app is in the background; in
      // the foreground that's up to the app.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        _notifications.showMessage(n.title ?? 'OMHS', n.body ?? '');
      });
      await FirebaseMessaging.instance.subscribeToTopic(topicAll);
    } catch (e) {
      // iOS without an APNs key in Firebase, or no Play services.
      debugPrint('Push messages unavailable: $e');
    }
  }

  /// After sign-in: ask for permission and remember this phone's token.
  Future<void> registerUser(String uid) async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // iOS may not have its APNs token yet on first launch.
      await FirebaseMessaging.instance.subscribeToTopic(topicAll);
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      unawaited(FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((Object e) {
        debugPrint('Saving the push token failed: $e');
      }));
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }
}
