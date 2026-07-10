import 'package:flutter/material.dart';

import '../../app/brand_assets.dart';
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

enum _AuthStep { onboarding, phone, code }

class _AuthScreenState extends State<AuthScreen> {
  final _pageController = PageController();
  final List<_OnboardingItem> _items = const [
    _OnboardingItem(
      icon: Icons.assignment_outlined,
      title: 'Опишите задачу',
      subtitle: 'Вазифаро тавсиф кунед',
      body:
          'Укажите, что нужно сделать, и мастера увидят вашу заявку за пару минут.',
    ),
    _OnboardingItem(
      icon: Icons.groups_2_outlined,
      title: 'Сравните мастеров',
      subtitle: 'Устоҳоро муқоиса кунед',
      body:
          'Смотрите рейтинг, цену, портфолио и выбирайте того, кто вам подходит.',
    ),
    _OnboardingItem(
      icon: Icons.chat_bubble_outline,
      title: 'Договоритесь в чате',
      subtitle: 'Дар чат созиш кунед',
      body: 'Обсуждайте время, адрес и детали заказа внутри приложения.',
    ),
  ];

  _AuthStep _step = _AuthStep.onboarding;
  int _page = 0;
  String _role = 'customer';
  String _phoneDigits = '900112233';
  String _codeDigits = '';
  bool _loading = false;
  String? _error;

  String get _phone => '+992$_phoneDigits';

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_phoneDigits.length < 9) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.apiClient.postJson(
        '/auth/request-code',
        body: {'phone': _phone},
      );
      if (!mounted) return;
      setState(() {
        _step = _AuthStep.code;
        _codeDigits = '';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    if (_codeDigits.length < 4) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = await widget.apiClient.postJson(
        '/auth/verify-code',
        body: {'phone': _phone, 'code': _codeDigits, 'role': _role},
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

  void _appendDigit(String value) {
    setState(() {
      _error = null;
      if (_step == _AuthStep.phone) {
        if (_phoneDigits.length < 9) {
          _phoneDigits += value;
        }
      } else if (_step == _AuthStep.code) {
        if (_codeDigits.length < 4) {
          _codeDigits += value;
        }
      }
    });
  }

  void _removeDigit() {
    setState(() {
      _error = null;
      if (_step == _AuthStep.phone && _phoneDigits.isNotEmpty) {
        _phoneDigits = _phoneDigits.substring(0, _phoneDigits.length - 1);
      } else if (_step == _AuthStep.code && _codeDigits.isNotEmpty) {
        _codeDigits = _codeDigits.substring(0, _codeDigits.length - 1);
      }
    });
  }

  void _goToPhone() {
    setState(() {
      _step = _AuthStep.phone;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _AuthStep.onboarding:
        return _buildOnboarding(context);
      case _AuthStep.phone:
        return _buildPhone(context);
      case _AuthStep.code:
        return _buildCode(context);
    }
  }

  Widget _buildOnboarding(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF111A32),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _items.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  itemBuilder: (context, index) {
                    final slide = _items[index];
                    return Column(
                      children: [
                        const Spacer(flex: 2),
                        Container(
                          width: 270,
                          height: 270,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2B5DE0),
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 30,
                                offset: Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Icon(
                            slide.icon,
                            color: Colors.white,
                            size: 104,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          slide.subtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF9CA3AF),
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            slide.body,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF8F96A8),
                              height: 1.45,
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: i == _page ? 22 : 10,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: i == _page
                            ? const Color(0xFF2B5DE0)
                            : const Color(0xFF4B5563),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF232E4A),
                        foregroundColor: const Color(0xFF9CA3AF),
                      ),
                      onPressed: _goToPhone,
                      child: const Text('Пропустить'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 7,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2B5DE0),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        if (_page == _items.length - 1) {
                          _goToPhone();
                          return;
                        }
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Text(
                        _page == _items.length - 1 ? 'Начать' : 'Далее ->',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhone(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF6F8FC), Color(0xFFEEF3FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _AuthBrandBlock(
                  title: 'Вход в аккаунт',
                  subtitle: 'Быстрый вход для заказчиков и мастеров',
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F172A),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Номер телефона',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2940),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Введите номер и выберите роль для входа',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _PhoneInputCard(phoneDigits: _phoneDigits),
                      const SizedBox(height: 14),
                      SegmentedButton<String>(
                        style: ButtonStyle(
                          side: const WidgetStatePropertyAll(
                            BorderSide(color: Color(0xFFD5E1F7)),
                          ),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
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
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_error != null) ...[
                  _AuthErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: _AuthKeyboard(
                    onDigit: _appendDigit,
                    onBackspace: _removeDigit,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2B5DE0),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD0D9E8),
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: _loading || _phoneDigits.length != 9
                      ? null
                      : _requestCode,
                  child: Text(_loading ? 'Отправляем...' : 'Получить SMS-код'),
                ),
                const SizedBox(height: 18),
                Text.rich(
                  TextSpan(
                    text: 'Продолжая, вы соглашаетесь с ',
                    children: [
                      TextSpan(
                        text: 'офертой',
                        style: const TextStyle(color: Color(0xFF2B5DE0)),
                      ),
                      const TextSpan(text: ' и '),
                      TextSpan(
                        text: 'политикой',
                        style: const TextStyle(color: Color(0xFF2B5DE0)),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCode(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF6F8FC), Color(0xFFEEF3FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() => _step = _AuthStep.phone),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Подтверждение входа',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1F2940),
                            ),
                          ),
                          Text(
                            _phone,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F172A),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Введите SMS-код',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF1F2940),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Для демо используйте код 1234',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          for (var i = 0; i < 4; i++) ...[
                            Expanded(
                              child: _CodeCell(
                                value: i < _codeDigits.length
                                    ? _codeDigits[i]
                                    : '',
                              ),
                            ),
                            if (i != 3) const SizedBox(width: 10),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _loading ? null : _requestCode,
                          child: const Text('Отправить код повторно'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_error != null) ...[
                  _AuthErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: _AuthKeyboard(
                    onDigit: _appendDigit,
                    onBackspace: _removeDigit,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2B5DE0),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD0D9E8),
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: _loading || _codeDigits.length != 4
                      ? null
                      : _verifyCode,
                  child: Text(_loading ? 'Проверяем...' : 'Войти'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingItem {
  const _OnboardingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String body;
}

class _PhoneInputCard extends StatelessWidget {
  const _PhoneInputCard({required this.phoneDigits});

  final String phoneDigits;

  @override
  Widget build(BuildContext context) {
    final formatted = _formatPhoneDigits(phoneDigits);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF2B5DE0), width: 1.6),
      ),
      child: Row(
        children: [
          const Text('🇹🇯', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          const Text(
            '+992',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2940),
            ),
          ),
          Container(
            width: 1,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0xFFB4C5F0),
          ),
          Expanded(
            child: Text(
              formatted,
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatPhoneDigits(String digits) {
    final padded = digits.padRight(9, '•');
    return '${padded.substring(0, 2)} ${padded.substring(2, 5)} ${padded.substring(5, 7)} ${padded.substring(7, 9)}';
  }
}

class _AuthBrandBlock extends StatelessWidget {
  const _AuthBrandBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              BrandAssets.appIcon,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            Text(
              'USTO',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w900,
                fontSize: 28,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: const Color(0xFF1F2940),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF64748B),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _AuthErrorBanner extends StatelessWidget {
  const _AuthErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFB91C1C),
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _CodeCell extends StatelessWidget {
  const _CodeCell({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: value.isEmpty
              ? const Color(0xFFD9E2F2)
              : const Color(0xFF2B5DE0),
          width: 1.4,
        ),
      ),
      child: Text(
        value.isEmpty ? '•' : value,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1F2940),
        ),
      ),
    );
  }
}

class _AuthKeyboard extends StatelessWidget {
  const _AuthKeyboard({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const labels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return GridView.builder(
      padding: const EdgeInsets.only(top: 8),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: labels.length,
      itemBuilder: (context, index) {
        final label = labels[index];
        if (label.isEmpty) {
          return const SizedBox.shrink();
        }
        final isBackspace = label == '<';
        return _KeyboardKey(
          label: label,
          onTap: () => isBackspace ? onBackspace() : onDigit(label),
          child: isBackspace
              ? const Icon(
                  Icons.backspace_outlined,
                  size: 30,
                  color: Color(0xFF64748B),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2940),
                      ),
                    ),
                    if (label != '1' && label != '0')
                      Text(
                        _lettersForDigit(label),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  static String _lettersForDigit(String value) {
    switch (value) {
      case '2':
        return 'АБВ';
      case '3':
        return 'ГДЕ';
      case '4':
        return 'ЖЗИ';
      case '5':
        return 'КЛМ';
      case '6':
        return 'НОП';
      case '7':
        return 'РСТ';
      case '8':
        return 'УФХ';
      case '9':
        return 'ЦЧШ';
      default:
        return '';
    }
  }
}

class _KeyboardKey extends StatelessWidget {
  const _KeyboardKey({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}
