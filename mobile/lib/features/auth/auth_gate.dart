import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/session_storage.dart';
import '../home/home_shell.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _sessionStorage = SessionStorage();
  Map<String, dynamic>? _user;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  // On cold start, a saved refresh token (if any) is exchanged for a brand
  // new access token so the user doesn't have to log in again. A failed
  // exchange (expired/invalid token, no network) just falls through to the
  // normal login screen instead of getting stuck.
  Future<void> _restoreSession() async {
    final refreshToken = await _sessionStorage.readRefreshToken();
    if (refreshToken == null) {
      setState(() => _restoring = false);
      return;
    }
    try {
      final auth = await widget.apiClient.postJson(
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      _applySignedIn(auth, persist: true);
    } on ApiException {
      await _sessionStorage.clear();
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _applySignedIn(Map<String, dynamic> auth, {required bool persist}) {
    widget.apiClient.accessToken = auth['accessToken'] as String?;
    widget.apiClient.refreshToken = auth['refreshToken'] as String?;
    if (persist) {
      final refreshToken = auth['refreshToken'] as String?;
      if (refreshToken != null) {
        unawaited(_sessionStorage.saveRefreshToken(refreshToken));
      }
    }
    _user = auth['user'] as Map<String, dynamic>?;
  }

  void _handleSignedIn(Map<String, dynamic> auth) {
    setState(() => _applySignedIn(auth, persist: true));
  }

  void _handleLogout() {
    widget.apiClient.accessToken = null;
    widget.apiClient.refreshToken = null;
    unawaited(_sessionStorage.clear());
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null) {
      return AuthScreen(
        apiClient: widget.apiClient,
        onSignedIn: _handleSignedIn,
      );
    }
    return HomeShell(
      apiClient: widget.apiClient,
      user: _user!,
      onLogout: _handleLogout,
    );
  }
}
