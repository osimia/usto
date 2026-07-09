import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../features/auth/auth_gate.dart';
import 'app_config.dart';
import 'app_theme.dart';

class UstoApp extends StatefulWidget {
  const UstoApp({super.key});

  @override
  State<UstoApp> createState() => _UstoAppState();
}

class _UstoAppState extends State<UstoApp> {
  late final ApiClient _apiClient;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USTO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: AuthGate(apiClient: _apiClient),
    );
  }
}
