import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.apiClient,
    required this.user,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late Future<HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<HomeData> _load() async {
    final results = await Future.wait([
      widget.apiClient.getJson('/me'),
      widget.apiClient.getJson('/orders?wrap=1'),
      widget.apiClient.getJson('/masters?wrap=1'),
      widget.apiClient.getJson('/wallet'),
      widget.apiClient.getJson('/chats'),
      widget.apiClient.getJson('/categories?wrap=1'),
    ]);
    return HomeData(
      me: results[0],
      orders: asMapList(results[1]['orders']),
      masters: asMapList(results[2]['masters']),
      wallet: results[3]['wallet'] as Map<String, dynamic>,
      chats: asMapList(results[4]['chats']),
      categories: asMapList(results[5]['categories']),
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(
          apiClient: widget.apiClient,
          orderId: order['id'] as int,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _createOrder() async {
    final data = await _future;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateOrderScreen(
          apiClient: widget.apiClient,
          categories: data.categories,
        ),
      ),
    );
    if (created == true) {
      setState(() => _tab = 1);
      await _refresh();
    }
  }

  Future<void> _openMaster(Map<String, dynamic> master) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MasterDetailScreen(
          apiClient: widget.apiClient,
          masterId: master['id'] as int,
        ),
      ),
    );
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          apiClient: widget.apiClient,
          chatId: chat['id'] as int,
          title: chat['orderTitle'] as String? ?? 'Чат',
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _editProfile(HomeData data) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EditProfileScreen(apiClient: widget.apiClient, data: data),
      ),
    );
    await _refresh();
  }

  Future<void> _openVerification() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerificationScreen(apiClient: widget.apiClient),
      ),
    );
    await _refresh();
  }

  Future<void> _openWallet() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletScreen(apiClient: widget.apiClient),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('USTO'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data!;
          final pages = [
            OverviewPage(
              data: data,
              onOpenOrder: _openOrder,
              onOpenChat: _openChat,
              onOpenWallet: _openWallet,
            ),
            OrdersPage(
              orders: data.orders,
              onOpenOrder: _openOrder,
              onCreateOrder: _createOrder,
            ),
            MastersPage(masters: data.masters, onOpenMaster: _openMaster),
            ProfilePage(
              data: data,
              onEdit: () => _editProfile(data),
              onVerification: _openVerification,
              onWallet: _openWallet,
            ),
          ];
          return RefreshIndicator(onRefresh: _refresh, child: pages[_tab]);
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            label: 'Заявки',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Мастера',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.data,
    required this.onOpenOrder,
    required this.onOpenChat,
    required this.onOpenWallet,
  });

  final HomeData data;
  final ValueChanged<Map<String, dynamic>> onOpenOrder;
  final ValueChanged<Map<String, dynamic>> onOpenChat;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    final profile = data.profile;
    final latestOrders = data.orders.take(2).toList();
    final latestChat = data.chats.isEmpty ? null : data.chats.first;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InfoCard(
          icon: Icons.account_circle_outlined,
          title: profile['name'] as String? ?? 'Профиль',
          subtitle: '${profile['role']} · ${profile['city']}',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Заявки',
                value: data.orders.length.toString(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Мастера',
                value: data.masters.length.toString(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InfoCard(
          icon: Icons.account_balance_wallet_outlined,
          title: '${data.wallet['balance']} ${data.wallet['currency']}',
          subtitle: 'Баланс мастера',
          onTap: onOpenWallet,
        ),
        const SizedBox(height: 20),
        SectionTitle(title: 'Свежие заявки'),
        const SizedBox(height: 8),
        for (final order in latestOrders) ...[
          OrderTile(order: order, onTap: () => onOpenOrder(order)),
          const SizedBox(height: 10),
        ],
        if (latestChat != null) ...[
          const SizedBox(height: 10),
          SectionTitle(title: 'Последний чат'),
          const SizedBox(height: 8),
          InfoCard(
            icon: Icons.chat_bubble_outline,
            title: latestChat['orderTitle'] as String? ?? 'Чат',
            subtitle: latestChat['lastMessage'] as String? ?? '',
            onTap: () => onOpenChat(latestChat),
          ),
        ],
      ],
    );
  }
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({
    super.key,
    required this.orders,
    required this.onOpenOrder,
    required this.onCreateOrder,
  });

  final List<Map<String, dynamic>> orders;
  final ValueChanged<Map<String, dynamic>> onOpenOrder;
  final VoidCallback onCreateOrder;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: onCreateOrder,
          icon: const Icon(Icons.add),
          label: const Text('Создать заявку'),
        ),
        const SizedBox(height: 16),
        if (orders.isEmpty)
          const EmptyState(
            icon: Icons.assignment_outlined,
            text: 'Заявок пока нет',
          ),
        for (final order in orders) ...[
          OrderTile(order: order, onTap: () => onOpenOrder(order)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class MastersPage extends StatelessWidget {
  const MastersPage({
    super.key,
    required this.masters,
    required this.onOpenMaster,
  });

  final List<Map<String, dynamic>> masters;
  final ValueChanged<Map<String, dynamic>> onOpenMaster;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final master = masters[index];
        return InfoCard(
          icon: Icons.handyman_outlined,
          title: master['name'] as String,
          subtitle:
              '${master['service']} · ★ ${master['rating']} · ${master['price']}',
          trailing: master['verified'] == true
              ? const Icon(Icons.verified, color: Colors.teal)
              : null,
          onTap: () => onOpenMaster(master),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemCount: masters.length,
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.data,
    required this.onEdit,
    required this.onVerification,
    required this.onWallet,
  });

  final HomeData data;
  final VoidCallback onEdit;
  final VoidCallback onVerification;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) {
    final profile = data.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InfoCard(
          icon: Icons.badge_outlined,
          title: profile['phone'] as String? ?? '',
          subtitle:
              '${profile['name']} · ${profile['city']} · ${profile['district']}',
        ),
        const SizedBox(height: 10),
        InfoCard(
          icon: Icons.verified_user_outlined,
          title: profile['isVerified'] == true ? 'Проверен' : 'Не проверен',
          subtitle: 'Статус профиля',
          onTap: onVerification,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onVerification,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Верификация мастера'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onWallet,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Кошелек'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Редактировать профиль'),
        ),
      ],
    );
  }
}

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({
    super.key,
    required this.apiClient,
    required this.categories,
  });

  final ApiClient apiClient;
  final List<Map<String, dynamic>> categories;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _address = TextEditingController();
  final _budget = TextEditingController(text: 'до 300 TJS');
  late String _category;
  String _district = 'Сино';
  String _when = 'Сегодня';
  bool _saving = false;
  String? _error;

  static const _districts = ['Сино', 'Фирдавси', 'Шохмансур', 'Исмоили Сомони'];

  static const _whenOptions = [
    'Сегодня',
    'Завтра',
    'На неделе',
    'В ближайшее время',
  ];

  @override
  void initState() {
    super.initState();
    _category = _categoryNames.first;
  }

  List<String> get _categoryNames {
    final names = [
      for (final item in widget.categories) item['name'] as String? ?? '',
    ].where((item) => item.isNotEmpty).toList();
    return names.isEmpty ? ['Сантехника'] : names;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _address.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.apiClient.postJson(
        '/orders',
        body: {
          'title': _title.text,
          'desc': _desc.text,
          'category': _category,
          'district': _district,
          'address': _address.text,
          'budget': _budget.text,
          'when': _when,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новая заявка')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Название',
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Описание',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Категория',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              for (final item in _categoryNames)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: (value) =>
                setState(() => _category = value ?? _category),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _district,
            decoration: const InputDecoration(
              labelText: 'Район',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            items: [
              for (final item in _districts)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: (value) =>
                setState(() => _district = value ?? _district),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Адрес',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _budget,
            decoration: const InputDecoration(
              labelText: 'Бюджет',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _when,
            decoration: const InputDecoration(
              labelText: 'Срок',
              prefixIcon: Icon(Icons.event_outlined),
            ),
            items: [
              for (final item in _whenOptions)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: (value) => setState(() => _when = value ?? _when),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.publish_outlined),
            label: Text(_saving ? 'Публикация...' : 'Опубликовать'),
          ),
        ],
      ),
    );
  }
}

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.apiClient,
    required this.orderId,
  });

  final ApiClient apiClient;
  final int orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      widget.apiClient.getJson('/orders/${widget.orderId}');

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _showResponseSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          ResponseSheet(apiClient: widget.apiClient, orderId: widget.orderId),
    );
    if (created == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Заявка')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final order = snapshot.data!['order'] as Map<String, dynamic>;
          final responses = asMapList(snapshot.data!['responses']);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                order['title'] as String,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(order['desc'] as String),
              const SizedBox(height: 16),
              InfoCard(
                icon: Icons.place_outlined,
                title: '${order['district']} · ${order['address']}',
                subtitle:
                    '${order['category']} · ${order['budget']} · ${order['when']}',
              ),
              const SizedBox(height: 20),
              SectionTitle(title: 'Отклики'),
              const SizedBox(height: 8),
              if (responses.isEmpty)
                const EmptyState(
                  icon: Icons.mark_chat_unread_outlined,
                  text: 'Откликов пока нет',
                ),
              for (final response in responses) ...[
                InfoCard(
                  icon: Icons.handyman_outlined,
                  title: '${response['master']} · ${response['price']} TJS',
                  subtitle: response['comment'] as String? ?? '',
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showResponseSheet,
        icon: const Icon(Icons.reply_outlined),
        label: const Text('Отклик'),
      ),
    );
  }
}

class MasterDetailScreen extends StatefulWidget {
  const MasterDetailScreen({
    super.key,
    required this.apiClient,
    required this.masterId,
  });

  final ApiClient apiClient;
  final int masterId;

  @override
  State<MasterDetailScreen> createState() => _MasterDetailScreenState();
}

class _MasterDetailScreenState extends State<MasterDetailScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.apiClient.getJson('/masters/${widget.masterId}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мастер')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: () async => setState(
                () => _future = widget.apiClient.getJson(
                  '/masters/${widget.masterId}',
                ),
              ),
            );
          }
          final master = snapshot.data!['master'] as Map<String, dynamic>;
          final skills = List<String>.from(
            master['skills'] as List? ?? const [],
          );
          final portfolio = List<String>.from(
            master['portfolio'] as List? ?? const [],
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              InfoCard(
                icon: Icons.handyman_outlined,
                title: master['name'] as String,
                subtitle:
                    '${master['service']} · ★ ${master['rating']} (${master['reviews']})',
                trailing: master['verified'] == true
                    ? const Icon(Icons.verified, color: Colors.teal)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(master['bio'] as String? ?? ''),
              const SizedBox(height: 20),
              SectionTitle(title: 'Навыки'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final skill in skills) Chip(label: Text(skill)),
                ],
              ),
              const SizedBox(height: 20),
              SectionTitle(title: 'Портфолио'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in portfolio)
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      child: Text(item),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.apiClient,
    required this.chatId,
    required this.title,
  });

  final ApiClient apiClient;
  final int chatId;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await widget.apiClient.getJson(
      '/chats/${widget.chatId}/messages',
    );
    return asMapList(data['messages']);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await widget.apiClient.postJson(
      '/chats/${widget.chatId}/messages',
      body: {'text': text, 'fromRole': 'customer'},
    );
    _controller.clear();
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final mine = message['fromRole'] == 'customer';
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Card(
                        color: mine
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(message['text'] as String? ?? ''),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(hintText: 'Сообщение'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _amount = TextEditingController(text: '100');
  late Future<Map<String, dynamic>> _future;
  bool _toppingUp = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    return widget.apiClient.getJson('/wallet');
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _topUp() async {
    setState(() {
      _toppingUp = true;
      _error = null;
    });
    try {
      await widget.apiClient.postJson(
        '/wallet/topup?wrap=1',
        body: {'amount': int.tryParse(_amount.text) ?? 0},
      );
      await _refresh();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _toppingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Кошелек')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final wallet = snapshot.data!['wallet'] as Map<String, dynamic>;
          final transactions = asMapList(wallet['transactions']);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                InfoCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: '${wallet['balance']} ${wallet['currency']}',
                  subtitle: 'Доступный баланс',
                ),
                const SizedBox(height: 20),
                SectionTitle(title: 'Пополнение'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Сумма, TJS',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _toppingUp ? null : _topUp,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SectionTitle(title: 'Транзакции'),
                const SizedBox(height: 8),
                if (transactions.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    text: 'Транзакций пока нет',
                  ),
                for (final tx in transactions) ...[
                  InfoCard(
                    icon: (tx['amount'] as int? ?? 0) >= 0
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    title: '${tx['amount']} TJS',
                    subtitle: '${tx['label']} · ${tx['createdAt']}',
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.apiClient,
    required this.data,
  });

  final ApiClient apiClient;
  final HomeData data;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _district;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.data.profile;
    _name = TextEditingController(text: profile['name'] as String? ?? '');
    _city = TextEditingController(text: profile['city'] as String? ?? '');
    _district = TextEditingController(
      text: profile['district'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _district.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.apiClient.patchJson(
        '/me/profile',
        body: {
          'name': _name.text,
          'city': _city.text,
          'district': _district.text,
          'avatarUrl': widget.data.profile['avatarUrl'] ?? '',
        },
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'Город'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _district,
            decoration: const InputDecoration(labelText: 'Район'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Сохранение...' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _documentType = TextEditingController(text: 'passport');
  final _fileUrl = TextEditingController(
    text: 'https://example.com/passport.jpg',
  );
  late Future<Map<String, dynamic>> _future;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _documentType.dispose();
    _fileUrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    return widget.apiClient.getJson('/verification/status');
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _uploadDocument() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.apiClient.postJson(
        '/verification/documents',
        body: {'documentType': _documentType.text, 'fileUrl': _fileUrl.text},
      );
      await _refresh();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _approveDev() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.apiClient.postJson('/verification?wrap=1');
      await _refresh();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Верификация')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final status = snapshot.data!;
          final documents = asMapList(status['documents']);
          final verified = status['verified'] == true;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              InfoCard(
                icon: verified
                    ? Icons.verified_user_outlined
                    : Icons.pending_actions_outlined,
                title: verified ? 'Проверен' : status['status'] as String,
                subtitle: 'Статус верификации мастера',
              ),
              const SizedBox(height: 20),
              SectionTitle(title: 'Документы'),
              const SizedBox(height: 8),
              if (documents.isEmpty)
                const EmptyState(
                  icon: Icons.file_upload_outlined,
                  text: 'Документы еще не загружены',
                ),
              for (final document in documents) ...[
                InfoCard(
                  icon: Icons.description_outlined,
                  title: document['documentType'] as String? ?? 'Документ',
                  subtitle:
                      '${document['status']} · ${document['fileUrl'] ?? ''}',
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 20),
              SectionTitle(title: 'Загрузить документ'),
              const SizedBox(height: 8),
              TextField(
                controller: _documentType,
                decoration: const InputDecoration(
                  labelText: 'Тип документа',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fileUrl,
                decoration: const InputDecoration(
                  labelText: 'Ссылка на файл',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _sending ? null : _uploadDocument,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(_sending ? 'Отправка...' : 'Отправить документ'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _sending ? null : _approveDev,
                icon: const Icon(Icons.done_all_outlined),
                label: const Text('Dev-подтвердить'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ResponseSheet extends StatefulWidget {
  const ResponseSheet({
    super.key,
    required this.apiClient,
    required this.orderId,
  });

  final ApiClient apiClient;
  final int orderId;

  @override
  State<ResponseSheet> createState() => _ResponseSheetState();
}

class _ResponseSheetState extends State<ResponseSheet> {
  final _price = TextEditingController(text: '250');
  final _comment = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.apiClient.postJson(
        '/orders/${widget.orderId}/responses',
        body: {
          'price': int.tryParse(_price.text) ?? 0,
          'comment': _comment.text,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Отклик на заявку',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Цена, TJS'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Комментарий'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_outlined),
              label: Text(_sending ? 'Отправка...' : 'Отправить'),
            ),
          ),
        ],
      ),
    );
  }
}

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.onTap});

  final Map<String, dynamic> order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      icon: Icons.assignment_outlined,
      title: order['title'] as String,
      subtitle:
          '${order['category']} · ${order['district']} · ${order['budget']}',
      trailing: Text('${order['responses'] ?? 0} откл.'),
      onTap: onTap,
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing:
            trailing ??
            (onTap == null ? null : const Icon(Icons.chevron_right)),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeData {
  HomeData({
    required this.me,
    required this.orders,
    required this.masters,
    required this.wallet,
    required this.chats,
    required this.categories,
  });

  final Map<String, dynamic> me;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> masters;
  final Map<String, dynamic> wallet;
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> categories;

  Map<String, dynamic> get profile => me['profile'] as Map<String, dynamic>;
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is! List) return [];
  return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
}
