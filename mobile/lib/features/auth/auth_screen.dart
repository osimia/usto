import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.apiClient,
    required this.onSignedIn,
  });

  final ApiClient apiClient;
  final ValueChanged<Map<String, dynamic>> onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController(text: '+992900112233');
  final _codeController = TextEditingController(text: '1234');
  String _role = 'customer';
  bool _codeRequested = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.apiClient.postJson(
        '/auth/request-code',
        body: {'phone': _phoneController.text},
      );
      setState(() => _codeRequested = true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = await widget.apiClient.postJson(
        '/auth/verify-code',
        body: {
          'phone': _phoneController.text,
          'code': _codeController.text,
          'role': _role,
        },
      );
      widget.onSignedIn(auth);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 32),
            Text(
              'USTO',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Маркетплейс услуг для заказчиков и мастеров',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Телефон',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'customer',
                  icon: Icon(Icons.person_outline),
                  label: Text('Заказчик'),
                ),
                ButtonSegment(
                  value: 'master',
                  icon: Icon(Icons.handyman_outlined),
                  label: Text('Мастер'),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (value) =>
                  setState(() => _role = value.first),
            ),
            const SizedBox(height: 12),
            if (_codeRequested)
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'SMS-код',
                  prefixIcon: Icon(Icons.sms_outlined),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading
                  ? null
                  : (_codeRequested ? _verifyCode : _requestCode),
              icon: Icon(_codeRequested ? Icons.login : Icons.send_to_mobile),
              label: Text(
                _loading
                    ? 'Подождите...'
                    : (_codeRequested ? 'Войти' : 'Получить код'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
