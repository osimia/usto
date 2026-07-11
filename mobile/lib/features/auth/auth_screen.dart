import 'package:flutter/material.dart';

import '../../app/brand_assets.dart';
import '../../core/api/api_client.dart';
import '../../core/constants.dart';

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

enum _AuthStep { onboarding, phone, details }

class _AuthScreenState extends State<AuthScreen> {
  final _pageController = PageController();
  final List<_OnboardingItem> _items = const [
    _OnboardingItem(
      icon: Icons.assignment_outlined,
      title: 'Опишите задачу',
      body:
          'Создайте заявку за минуту и получите отклики от подходящих мастеров.',
    ),
    _OnboardingItem(
      icon: Icons.groups_2_outlined,
      title: 'Сравните мастеров',
      body: 'Смотрите рейтинг, цену и опыт, чтобы выбрать лучшего исполнителя.',
    ),
    _OnboardingItem(
      icon: Icons.chat_bubble_outline,
      title: 'Договоритесь в чате',
      body: 'Уточняйте время, адрес и детали заказа прямо внутри приложения.',
    ),
  ];

  _AuthStep _step = _AuthStep.onboarding;
  int _page = 0;
  String _role = 'customer';
  String _phoneDigits = '900112233';
  bool _loading = false;
  String? _error;

  final _name = TextEditingController();
  String _city = kCities.first;
  String _district = kDistricts.first;

  String get _phone => '+992$_phoneDigits';

  @override
  void dispose() {
    _pageController.dispose();
    _name.dispose();
    super.dispose();
  }

  // Tries to log in with just phone+role. An existing account signs in
  // immediately; a brand-new one is told registrationRequired and moves to
  // the details step to collect name/city/district before an account is
  // actually created.
  Future<void> _login() async {
    if (_phoneDigits.length < 9) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.apiClient.postJson(
        '/auth/login',
        body: {'phone': _phone, 'role': _role},
      );
      if (!mounted) return;
      if (res['registrationRequired'] == true) {
        setState(() => _step = _AuthStep.details);
      } else {
        widget.onSignedIn(res);
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _completeRegistration() async {
    if (_name.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.apiClient.postJson(
        '/auth/login',
        body: {
          'phone': _phone,
          'role': _role,
          'name': _name.text.trim(),
          'city': _city,
          'district': _district,
        },
      );
      widget.onSignedIn(res);
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
      if (_phoneDigits.length < 9) {
        _phoneDigits += value;
      }
    });
  }

  void _removeDigit() {
    setState(() {
      _error = null;
      if (_phoneDigits.isNotEmpty) {
        _phoneDigits = _phoneDigits.substring(0, _phoneDigits.length - 1);
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
      case _AuthStep.details:
        return _buildDetails(context);
    }
  }

  Widget _buildOnboarding(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF111A32),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
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
                        const Spacer(),
                        Container(
                          width: 228,
                          height: 228,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2B5DE0),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x24000000),
                                blurRadius: 24,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Icon(
                            slide.icon,
                            color: Colors.white,
                            size: 82,
                          ),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            slide.body,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF8F96A8),
                              height: 1.45,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        const Spacer(),
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
                        minimumSize: const Size.fromHeight(54),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: _goToPhone,
                      child: const FittedBox(child: Text('Пропустить')),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 7,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2B5DE0),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
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
                        _page == _items.length - 1 ? 'Начать' : 'Далее',
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
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _AuthBrandBlock(
                  title: 'Вход в аккаунт',
                  subtitle: 'Вход для заказчиков и мастеров',
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
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
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Введите номер и выберите роль',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PhoneInputCard(phoneDigits: _phoneDigits),
                      const SizedBox(height: 14),
                      SegmentedButton<String>(
                        style: ButtonStyle(
                          side: const WidgetStatePropertyAll(
                            BorderSide(color: Color(0xFFD5E1F7)),
                          ),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 10),
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
                const SizedBox(height: 10),
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
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _loading || _phoneDigits.length != 9
                      ? null
                      : _login,
                  child: Text(_loading ? 'Входим...' : 'Войти'),
                ),
                const SizedBox(height: 14),
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
                  style: theme.textTheme.bodySmall?.copyWith(
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

  Widget _buildDetails(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
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
                            'Заполните профиль',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1F2940),
                              fontSize: 17,
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
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
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
                            'Это первый вход с этого номера',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF1F2940),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Укажите ФИО и адрес, чтобы создать аккаунт',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'ФИО',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _city,
                            decoration: const InputDecoration(
                              labelText: 'Город',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final city in kCities)
                                DropdownMenuItem(
                                  value: city,
                                  child: Text(city),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _city = value);
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _district,
                            decoration: const InputDecoration(
                              labelText: 'Район',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final district in kDistricts)
                                DropdownMenuItem(
                                  value: district,
                                  child: Text(district),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _district = value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_error != null) ...[
                  _AuthErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2B5DE0),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD0D9E8),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _loading || _name.text.trim().isEmpty
                      ? null
                      : _completeRegistration,
                  child: Text(_loading ? 'Создаём аккаунт...' : 'Продолжить'),
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
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _PhoneInputCard extends StatelessWidget {
  const _PhoneInputCard({required this.phoneDigits});

  final String phoneDigits;

  @override
  Widget build(BuildContext context) {
    final formatted = _formatPhoneDigits(phoneDigits);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B5DE0), width: 1.5),
      ),
      child: Row(
        children: [
          const Text('🇹🇯', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Text(
            '+992',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2940),
            ),
          ),
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: const Color(0xFFB4C5F0),
          ),
          Expanded(
            child: Text(
              formatted,
              style: const TextStyle(
                fontSize: 18,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
                height: 1.15,
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
            const SizedBox(width: 10),
            Text(
              'USTO',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF1F2940),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
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
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.22,
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
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2940),
                      ),
                    ),
                    if (label != '1' && label != '0')
                      Text(
                        _lettersForDigit(label),
                        style: const TextStyle(
                          fontSize: 11,
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}
