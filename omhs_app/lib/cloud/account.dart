import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';

/// Optional Google account for cloud sync. The app works fully without it.
class AccountService extends ChangeNotifier {
  AccountService({required this.available});

  /// False when Firebase didn't start (no network config, unsupported
  /// platform); the account section is hidden then.
  final bool available;

  User? _user;
  bool _busy = false;
  String? _error;
  bool _googleReady = false;
  StreamSubscription<User?>? _sub;

  User? get user => _user;
  bool get signedIn => _user != null;
  bool get busy => _busy;

  /// Why the last sign-in failed; cleared on the next attempt.
  String? get error => _error;

  Future<void> init() async {
    if (!available) return;
    _user = FirebaseAuth.instance.currentUser;
    _sub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _user = u;
      notifyListeners();
    });
  }

  Future<void> _ensureGoogle() async {
    if (_googleReady) return;
    // Android reads its client ids from google-services.json.
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS ? DefaultFirebaseOptions.ios.iosClientId : null,
    );
    _googleReady = true;
  }

  Future<void> signInWithGoogle() async {
    if (!available || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _ensureGoogle();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw StateError('no ID token');
      await FirebaseAuth.instance
          .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (e) {
      // Cancelled by the user: say nothing.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _error = e.code == GoogleSignInExceptionCode.clientConfigurationError
            ? 'Google sign-in is not set up for this build of the app.'
            : 'Google sign-in failed. Try again.';
        debugPrint('Google sign-in: ${e.code} ${e.description}');
      }
    } on FirebaseAuthException catch (e) {
      _error = e.code == 'network-request-failed'
          ? 'No internet connection.'
          : 'Sign-in failed (${e.code}).';
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      _error = 'Sign-in failed. Try again.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (!available) return;
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
