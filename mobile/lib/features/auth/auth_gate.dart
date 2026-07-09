import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../home/home_shell.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Map<String, dynamic>? _user;

  void _handleSignedIn(Map<String, dynamic> auth) {
    widget.apiClient.accessToken = auth['accessToken'] as String?;
    widget.apiClient.refreshToken = auth['refreshToken'] as String?;
    setState(() => _user = auth['user'] as Map<String, dynamic>?);
  }

  void _handleLogout() {
    widget.apiClient.accessToken = null;
    widget.apiClient.refreshToken = null;
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
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
