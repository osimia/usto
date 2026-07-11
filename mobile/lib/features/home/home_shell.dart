import 'package:flutter/material.dart';

import '../../app/brand_assets.dart';
import '../../core/api/api_client.dart';
import '../../core/constants.dart';

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
      widget.apiClient.getJson('/chats'),
      widget.apiClient.getJson('/bootstrap'),
    ]);
    final bootstrap = results[2];
    final master = bootstrap['master'] as Map<String, dynamic>? ?? const {};
    return HomeData(
      me: results[0],
      orders: asMapList(bootstrap['orders']),
      masters: asMapList(bootstrap['masters']),
      wallet: {
        'balance': master['walletBalance'] ?? 0,
        'currency': 'TJS',
        'transactions': asMapList(bootstrap['transactions']),
      },
      chats: asMapList(results[1]['chats']),
      categories: asMapList(bootstrap['categories']),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _goToTab(int index) {
    setState(() => _tab = index);
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    final isMaster = (widget.user['role'] as String? ?? '') == 'master';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(
          apiClient: widget.apiClient,
          orderId: order['id'] as int,
          isMaster: isMaster,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _createOrder() async {
    final data = await _future;
    if (!mounted) return;
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => CreateOrderScreen(
          apiClient: widget.apiClient,
          categories: data.categories,
        ),
      ),
    );
    if (created != null) {
      setState(() => _tab = 1);
      await _refresh();
      if (!mounted) return;
      await _openOrder(created);
    }
  }

  Future<void> _openMaster(Map<String, dynamic> master) async {
    final data = await _future;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MasterDetailScreen(
          apiClient: widget.apiClient,
          masterId: master['id'] as int,
          categories: data.categories,
        ),
      ),
    );
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    final isMaster = (widget.user['role'] as String? ?? '') == 'master';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          apiClient: widget.apiClient,
          chatId: chat['id'] as int,
          title: _chatPeerName(chat, isMaster: isMaster),
          orderTitle: chat['orderTitle'] as String? ?? 'Заказ',
          isMaster: isMaster,
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
    final role = widget.user['role'] as String? ?? 'customer';
    final isMaster = role == 'master';
    return Scaffold(
      appBar: null,
      body: FutureBuilder<HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _HomeLoadingView();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data!;
          final pages = isMaster
              ? [
                  OrdersPage(
                    orders: data.orders,
                    onOpenOrder: _openOrder,
                    onCreateOrder: _createOrder,
                    isMaster: true,
                  ),
                  ChatsPage(
                    chats: data.chats,
                    onOpenChat: _openChat,
                    isMaster: true,
                  ),
                  ProfilePage(
                    data: data,
                    onEdit: () => _editProfile(data),
                    onVerification: _openVerification,
                    onWallet: _openWallet,
                    isMaster: true,
                    onLogout: widget.onLogout,
                  ),
                ]
              : [
                  OverviewPage(
                    data: data,
                    onOpenOrder: _openOrder,
                    onOpenChat: _openChat,
                    onCreateOrder: _createOrder,
                    onOpenMaster: _openMaster,
                    onOpenAllOrders: () => _goToTab(1),
                    onOpenAllMasters: () => _goToTab(2),
                    onOpenProfile: () => _goToTab(3),
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
          return SafeArea(
            bottom: false,
            child: RefreshIndicator(onRefresh: _refresh, child: pages[_tab]),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: role == 'master'
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Заявки',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  label: 'Чаты',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Профиль',
                ),
              ]
            : const [
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
    required this.onCreateOrder,
    required this.onOpenMaster,
    required this.onOpenAllOrders,
    required this.onOpenAllMasters,
    required this.onOpenProfile,
  });

  final HomeData data;
  final ValueChanged<Map<String, dynamic>> onOpenOrder;
  final ValueChanged<Map<String, dynamic>> onOpenChat;
  final VoidCallback onCreateOrder;
  final ValueChanged<Map<String, dynamic>> onOpenMaster;
  final VoidCallback onOpenAllOrders;
  final VoidCallback onOpenAllMasters;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final profile = data.profile;
    final latestOrders = data.orders.take(3).toList();
    final featuredMasters = data.masters.take(3).toList();
    final categories = data.categories.take(8).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(color: Color(0xFF141B31)),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: Color(0xFF7FB3FF),
                          size: 17,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          profile['city'] as String? ?? 'Душанбе',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFFF8FAFC),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                        ),
                        const SizedBox(width: 1),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFF7FB3FF),
                          size: 17,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none_outlined,
                          color: Color(0xFFF8FAFC),
                          size: 22,
                        ),
                        Positioned(
                          top: 11,
                          right: 11,
                          child: CircleAvatar(
                            radius: 3.5,
                            backgroundColor: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onCreateOrder,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.search,
                            color: Color(0xFF7C859A),
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Что нужно сделать?',
                              style: TextStyle(
                                color: Color(0xFF7C859A),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _CustomerHeroCard(onCreateOrder: onCreateOrder),
              const SizedBox(height: 24),
              _CustomerQuickActions(
                onCreateOrder: onCreateOrder,
                onOpenOrders: onOpenAllOrders,
                onOpenMasters: onOpenAllMasters,
                onOpenProfile: onOpenProfile,
                onOpenChat: data.chats.isEmpty
                    ? null
                    : () => onOpenChat(data.chats.first),
              ),
              const SizedBox(height: 24),
              _OverviewSummaryCard(
                ordersCount: data.orders.length,
                chatsCount: data.chats.length,
                mastersCount: data.masters.length,
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Категории',
                actionLabel: 'Все',
                onTap: onOpenAllMasters,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth < 360 ? 3 : 4;
                  final aspectRatio = crossAxisCount == 3 ? 0.88 : 0.74;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: aspectRatio,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return _CategoryTile(
                        label: category['name'] as String? ?? 'Категория',
                        onTap: onCreateOrder,
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Лучшие мастера',
                actionLabel: 'Все',
                onTap: onOpenAllMasters,
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 244,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: featuredMasters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final master = featuredMasters[index];
                    return _FeaturedMasterCard(
                      master: master,
                      onTap: () => onOpenMaster(master),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Активные заявки',
                actionLabel: 'Все',
                onTap: onOpenAllOrders,
              ),
              const SizedBox(height: 14),
              Text(
                latestOrders.isEmpty
                    ? 'Здесь появятся ваши свежие обращения.'
                    : 'Открывайте заявку, чтобы следить за откликами, статусом и дальнейшим выбором мастера.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF667085),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              if (latestOrders.isEmpty)
                const EmptyState(
                  icon: Icons.assignment_outlined,
                  text: 'Заявок пока нет',
                ),
              for (final order in latestOrders) ...[
                _CustomerOrderCard(
                  order: order,
                  onTap: () => onOpenOrder(order),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
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
    this.isMaster = false,
  });

  final List<Map<String, dynamic>> orders;
  final ValueChanged<Map<String, dynamic>> onOpenOrder;
  final VoidCallback onCreateOrder;
  final bool isMaster;

  @override
  Widget build(BuildContext context) {
    if (isMaster) {
      final freshOrders = orders
          .where(
            (order) => _orderStatusIsActive(order['status'] as String?) == true,
          )
          .length;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text(
            'Заявки',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Только новые и подходящие заказы без лишнего шума',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Все заявки',
                    value: '${orders.length}',
                    accent: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: 'Активные',
                    value: '$freshOrders',
                    accent: const Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final order in orders) ...[
            _MasterJobCard(order: order, onTap: () => onOpenOrder(order)),
            const SizedBox(height: 12),
          ],
          if (orders.isEmpty)
            const EmptyState(
              icon: Icons.assignment_outlined,
              text: 'Подходящих заявок пока нет',
              subtitle:
                  'Новые заказы появятся здесь, как только система подберёт релевантные заявки.',
            ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(
          title: 'Заявки',
          actionLabel: orders.isEmpty ? null : 'Создать',
          onTap: orders.isEmpty ? null : onCreateOrder,
        ),
        const SizedBox(height: 10),
        Text(
          orders.isEmpty
              ? 'Создайте первую задачу и получите первые отклики от мастеров.'
              : 'Следите за активностью по вашим заявкам и открывайте нужную в один тап.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF667085)),
        ),
        const SizedBox(height: 16),
        _OrdersSummaryCard(orders: orders, onCreateOrder: onCreateOrder),
        const SizedBox(height: 14),
        if (orders.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE6ECF5)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_open_outlined,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Здесь собраны все ваши заявки: открывайте нужную и быстро переходите к откликам мастеров.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (orders.isNotEmpty) const SizedBox(height: 14),
        if (orders.isEmpty)
          const EmptyState(
            icon: Icons.assignment_outlined,
            text: 'Заявок пока нет',
            subtitle:
                'Создайте первую заявку, и мастера смогут откликнуться в ближайшее время.',
          ),
        for (final order in orders) ...[
          _CustomerOrderCard(order: order, onTap: () => onOpenOrder(order)),
          const SizedBox(height: 12),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: 'Мастера', actionLabel: 'Все'),
        const SizedBox(height: 10),
        Text(
          'Выбирайте по специализации, рейтингу и статусу проверки.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF667085)),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: _AdaptiveStatGrid(
            minTileWidth: 92,
            children: [
              _SummaryStatTile(
                label: 'Всего',
                value: '${masters.length}',
                accent: const Color(0xFF0F172A),
              ),
              _SummaryStatTile(
                label: 'Проверены',
                value:
                    '${masters.where((master) => master['verified'] == true).length}',
                accent: const Color(0xFF059669),
              ),
              _SummaryStatTile(
                label: 'Рейтинг',
                value: masters.isEmpty
                    ? '0'
                    : _averageMasterRating(masters).toStringAsFixed(1),
                accent: const Color(0xFF2563EB),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (masters.isEmpty)
          const EmptyState(
            icon: Icons.groups_outlined,
            text: 'Мастеров пока нет',
            subtitle:
                'Когда база специалистов загрузится, вы сможете выбрать подходящего исполнителя.',
          ),
        for (final master in masters) ...[
          _MasterListCard(master: master, onTap: () => onOpenMaster(master)),
          const SizedBox(height: 12),
        ],
      ],
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
    this.isMaster = false,
    this.onLogout,
  });

  final HomeData data;
  final VoidCallback onEdit;
  final VoidCallback onVerification;
  final VoidCallback onWallet;
  final bool isMaster;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final profile = data.profile;
    final isVerified = profile['isVerified'] == true;
    if (isMaster) {
      final balanceText =
          '${data.wallet['balance']} ${data.wallet['currency']}';
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text(
            'Профиль мастера',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Только важное: статус, баланс и настройка профиля',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 18),
          DashboardHero(
            name: profile['name'] as String? ?? 'Мастер',
            role: profile['role'] as String? ?? 'master',
            city: profile['city'] as String? ?? 'Душанбе',
            stats: [
              HeroStat(label: 'Заявки', value: data.orders.length.toString()),
              HeroStat(label: 'Чаты', value: data.chats.length.toString()),
              HeroStat(label: 'Баланс', value: '${data.wallet['balance']}'),
            ],
            trailing: StatusPill(
              icon: isVerified
                  ? Icons.verified
                  : Icons.pending_actions_outlined,
              label: isVerified ? 'Готов' : 'Проверка',
              tone: isVerified ? StatusTone.success : StatusTone.warning,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _AdaptiveStatGrid(
                  minTileWidth: 96,
                  children: [
                    _SummaryStatTile(
                      label: 'Статус',
                      value: isVerified ? 'Готов' : 'Проверка',
                      accent: isVerified
                          ? const Color(0xFF059669)
                          : const Color(0xFFF59E0B),
                    ),
                    _SummaryStatTile(
                      label: 'Баланс',
                      value: '${data.wallet['balance']}',
                      accent: const Color(0xFF2563EB),
                    ),
                    _SummaryStatTile(
                      label: 'Город',
                      value: profile['city'] as String? ?? 'Душанбе',
                      accent: const Color(0xFF8B5CF6),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _AdaptiveStatGrid(
                  minTileWidth: 140,
                  children: [
                    _ProfileActionTile(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Баланс',
                      accent: const Color(0xFF2563EB),
                      onTap: onWallet,
                    ),
                    _ProfileActionTile(
                      icon: Icons.verified_user_outlined,
                      label: isVerified ? 'Статус' : 'Проверка',
                      accent: isVerified
                          ? const Color(0xFF059669)
                          : const Color(0xFFF59E0B),
                      onTap: onVerification,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EEF6)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C0F172A),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                _ProfileSummaryRow(
                  icon: Icons.badge_outlined,
                  title: profile['name'] as String? ?? 'Мастер',
                  subtitle:
                      '${profile['phone'] ?? ''} · ${profile['city'] ?? 'Душанбе'}',
                ),
                const SizedBox(height: 10),
                _ProfileSummaryRow(
                  icon: Icons.verified_user_outlined,
                  title: isVerified ? 'Профиль проверен' : 'Нужна верификация',
                  subtitle: isVerified
                      ? 'Аккаунт готов к приёму заказов и виден клиентам увереннее.'
                      : 'Завершите проверку, чтобы повысить доверие и качество откликов.',
                  trailing: StatusPill(
                    icon: isVerified
                        ? Icons.verified
                        : Icons.pending_actions_outlined,
                    label: isVerified ? 'Готов' : 'Проверка',
                    tone: isVerified ? StatusTone.success : StatusTone.warning,
                  ),
                  onTap: onVerification,
                ),
                const SizedBox(height: 10),
                _ProfileSummaryRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: balanceText,
                  subtitle: 'Баланс для откликов и работы по заказам',
                  onTap: onWallet,
                ),
                const SizedBox(height: 10),
                _ProfileSummaryRow(
                  icon: Icons.edit_outlined,
                  title: 'Настройки профиля',
                  subtitle:
                      'Имя, город, рабочая информация и видимость профиля',
                  onTap: onEdit,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: 'Профиль', actionLabel: null),
        const SizedBox(height: 10),
        Text(
          'Управляйте аккаунтом, основными данными и текущей активностью.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF667085)),
        ),
        const SizedBox(height: 16),
        DashboardHero(
          name: profile['name'] as String? ?? 'Заказчик',
          role: profile['role'] as String? ?? 'user',
          city: profile['city'] as String? ?? 'Душанбе',
          stats: [
            HeroStat(label: 'Заявки', value: data.orders.length.toString()),
            HeroStat(label: 'Чаты', value: data.chats.length.toString()),
            HeroStat(label: 'Мастера', value: data.masters.length.toString()),
          ],
          trailing: StatusPill(
            icon: isVerified
                ? Icons.verified_user_outlined
                : Icons.shield_outlined,
            label: isVerified ? 'Аккаунт активен' : 'Профиль не завершён',
            tone: isVerified ? StatusTone.success : StatusTone.warning,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _AdaptiveStatGrid(
                minTileWidth: 96,
                children: [
                  _SummaryStatTile(
                    label: 'Профиль',
                    value: isVerified ? 'Готов' : 'Нужно',
                    accent: isVerified
                        ? const Color(0xFF059669)
                        : const Color(0xFFF59E0B),
                  ),
                  _SummaryStatTile(
                    label: 'Чаты',
                    value: '${data.chats.length}',
                    accent: const Color(0xFF2563EB),
                  ),
                  _SummaryStatTile(
                    label: 'Район',
                    value: (profile['district'] as String? ?? 'Не указан')
                        .split(' ')
                        .first,
                    accent: const Color(0xFF8B5CF6),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AdaptiveStatGrid(
                minTileWidth: 140,
                children: [
                  _ProfileActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Изменить',
                    accent: const Color(0xFF2563EB),
                    onTap: onEdit,
                  ),
                  _ProfileActionTile(
                    icon: Icons.verified_user_outlined,
                    label: 'Проверить',
                    accent: const Color(0xFF059669),
                    onTap: onVerification,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE8EEF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              _ProfileSummaryRow(
                icon: Icons.person_outline,
                title: profile['name'] as String? ?? 'Пользователь',
                subtitle:
                    '${profile['phone'] ?? ''} · ${profile['city']} · ${profile['district']}',
                trailing: StatusPill(
                  icon: isVerified
                      ? Icons.verified_user_outlined
                      : Icons.shield_outlined,
                  label: isVerified ? 'Активен' : 'Заполнить',
                  tone: isVerified ? StatusTone.success : StatusTone.warning,
                ),
              ),
              const SizedBox(height: 10),
              _ProfileSummaryRow(
                icon: Icons.manage_accounts_outlined,
                title: isVerified
                    ? 'Профиль заполнен'
                    : 'Профиль стоит завершить',
                subtitle: isVerified
                    ? 'Основные данные сохранены и аккаунт готов к использованию.'
                    : 'Проверьте имя, город и район, чтобы мастерам было проще с вами работать.',
                onTap: onVerification,
              ),
              const SizedBox(height: 10),
              _ProfileSummaryRow(
                icon: Icons.chat_bubble_outline,
                title: '${data.chats.length} активных чатов',
                subtitle: data.chats.isEmpty
                    ? 'Когда вы выберете мастера, диалоги появятся здесь.'
                    : 'Все текущие договорённости с мастерами собраны в одном месте.',
              ),
              const SizedBox(height: 10),
              _ProfileSummaryRow(
                icon: Icons.assignment_outlined,
                title: '${data.orders.length} заявок в аккаунте',
                subtitle: data.orders.isEmpty
                    ? 'После создания первой заявки история обращений появится здесь.'
                    : 'История ваших заявок уже сохранена и доступна для просмотра.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileSummaryRow extends StatelessWidget {
  const _ProfileSummaryRow({
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
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({
    super.key,
    required this.apiClient,
    required this.categories,
    this.initialCategory,
    this.preferredMaster,
  });

  final ApiClient apiClient;
  final List<Map<String, dynamic>> categories;
  final String? initialCategory;
  final Map<String, dynamic>? preferredMaster;

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
  int _step = 0;
  bool _saving = false;
  String? _error;
  final List<String> _selectedTemplates = [];

  static const _whenOptions = [
    'Сегодня',
    'Завтра',
    'На неделе',
    'В ближайшее время',
  ];

  static const _templates = [
    'Течёт кран',
    'Засор трубы',
    'Замена смесителя',
    'Протечка',
  ];

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? _categoryNames.first;
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
      final created = await widget.apiClient.postJson(
        '/orders',
        body: {
          'title': _derivedTitle,
          'desc': _desc.text,
          'category': _category,
          'district': _district,
          'address': _address.text,
          'budget': _budget.text,
          'when': _when,
          'preferredMasterId': widget.preferredMaster?['id'],
        },
      );
      final order = Map<String, dynamic>.from(
        created['order'] as Map? ?? const {},
      );
      if (mounted) Navigator.of(context).pop(order);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _desc.text.trim().length >= 10;
      case 1:
        return _address.text.trim().length >= 6;
      case 2:
        return true;
      case 3:
        return _budget.text.trim().isNotEmpty;
      case 4:
        return true;
      default:
        return false;
    }
  }

  String get _derivedTitle {
    final trimmed = _desc.text.trim();
    if (trimmed.isEmpty) return _category;
    final normalized = trimmed.replaceAll('\n', ' ');
    return normalized.length > 56
        ? '${normalized.substring(0, 56).trim()}...'
        : normalized;
  }

  String? _stepValidationMessage() {
    switch (_step) {
      case 0:
        return _desc.text.trim().length >= 10
            ? null
            : 'Опишите задачу чуть подробнее, минимум 10 символов.';
      case 1:
        return _address.text.trim().length >= 6
            ? null
            : 'Укажите точный адрес или ориентир, чтобы мастер понял, куда ехать.';
      case 2:
        return null;
      case 3:
        return _budget.text.trim().isNotEmpty
            ? null
            : 'Укажите бюджет или выберите вариант "жду предложений".';
      case 4:
        if (_desc.text.trim().length < 10) {
          return 'Описание заявки слишком короткое.';
        }
        if (_address.text.trim().length < 6) {
          return 'Адрес заполнен недостаточно подробно.';
        }
        if (_budget.text.trim().isEmpty) {
          return 'Бюджет не заполнен.';
        }
        return null;
      default:
        return null;
    }
  }

  void _continueFlow() {
    final message = _stepValidationMessage();
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  void _applyTemplate(String value) {
    setState(() {
      if (!_selectedTemplates.contains(value)) {
        _selectedTemplates.add(value);
      }
      if (_desc.text.trim().isEmpty) {
        _desc.text = value;
      } else if (!_desc.text.contains(value)) {
        _desc.text = '${_desc.text.trim()}, $value';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_step + 1) / 5;
    final titles = [
      'Что нужно сделать?',
      'Где выполнить?',
      'Когда нужно?',
      'Бюджет заявки',
      'Проверьте заявку',
    ];
    final subtitles = [
      'Кратко опишите задачу для мастера.',
      'Укажите адрес или удобный район.',
      'Выберите удобное время выполнения.',
      'Добавьте бюджет или ожидаемую цену.',
      'Проверьте детали перед публикацией.',
    ];
    return Scaffold(
      appBar: AppBar(toolbarHeight: 0, automaticallyImplyLeading: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (_step == 0) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() {
                        _error = null;
                        _step -= 1;
                      });
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Новая заявка',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                      Text(
                        'Шаг ${_step + 1} из 5',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: const Color(0xFFE6ECF6),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF2B5DE0)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              children: [
                Text(
                  titles[_step],
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF1F2940),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitles[_step],
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF94A3B8),
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                ...switch (_step) {
                  0 => _buildTaskStep(context),
                  1 => _buildAddressStep(context),
                  2 => _buildScheduleStep(context),
                  3 => _buildBudgetStep(context),
                  _ => _buildReviewStep(context),
                },
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5EAF3))),
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2B5DE0),
                  foregroundColor: Colors.white,
                ),
                onPressed: _saving
                    ? null
                    : (_step == 4
                          ? _submit
                          : (_canContinue ? _continueFlow : null)),
                child: Text(
                  _saving
                      ? 'Публикация...'
                      : (_step == 4 ? 'Опубликовать' : 'Далее'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTaskStep(BuildContext context) {
    return [
      if (widget.preferredMaster != null) ...[
        _PreferredMasterBanner(master: widget.preferredMaster!),
        const SizedBox(height: 18),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SelectionChip(
            icon: Icons.build_outlined,
            label: _category,
            active: true,
            onTap: () async {
              final selected = await showModalBottomSheet<String>(
                context: context,
                builder: (context) => _CategorySelectorSheet(
                  categories: _categoryNames,
                  current: _category,
                ),
              );
              if (selected != null) {
                setState(() => _category = selected);
              }
            },
          ),
        ],
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _desc,
        minLines: 6,
        maxLines: 8,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText:
              'Опишите задачу подробно. Например: течёт смеситель на кухне, нужна замена картриджа...',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Text(
            'Мин. 10 символов',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF94A3B8)),
          ),
          const Spacer(),
          Text(
            '${_desc.text.length}/300',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF94A3B8)),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        'Быстрые шаблоны:',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: const Color(0xFF64748B)),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final template in _templates)
            _TemplateChip(
              label: template,
              active: _selectedTemplates.contains(template),
              onTap: () => _applyTemplate(template),
            ),
        ],
      ),
    ];
  }

  List<Widget> _buildAddressStep(BuildContext context) {
    return [
      if (widget.preferredMaster != null) ...[
        _PreferredMasterBanner(master: widget.preferredMaster!),
        const SizedBox(height: 16),
      ],
      DropdownButtonFormField<String>(
        initialValue: _district,
        decoration: const InputDecoration(
          labelText: 'Район',
          prefixIcon: Icon(Icons.location_on_outlined),
        ),
        items: [
          for (final item in kDistricts)
            DropdownMenuItem(value: item, child: Text(item)),
        ],
        onChanged: (value) => setState(() => _district = value ?? _district),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _address,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Адрес',
          hintText: 'Улица, дом, подъезд, ориентир',
          prefixIcon: Icon(Icons.place_outlined),
        ),
      ),
      const SizedBox(height: 16),
      InfoCard(
        icon: Icons.map_outlined,
        title: 'Зона выезда',
        subtitle:
            'Мастера рядом быстрее увидят вашу заявку по району $_district',
      ),
    ];
  }

  List<Widget> _buildScheduleStep(BuildContext context) {
    return [
      if (widget.preferredMaster != null) ...[
        _PreferredMasterBanner(master: widget.preferredMaster!),
        const SizedBox(height: 16),
      ],
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in _whenOptions)
            _SelectionChip(
              icon: Icons.schedule_outlined,
              label: item,
              active: _when == item,
              onTap: () => setState(() => _when = item),
            ),
        ],
      ),
      const SizedBox(height: 18),
      InfoCard(
        icon: Icons.tips_and_updates_outlined,
        title: 'Подсказка',
        subtitle:
            'Если нужно срочно, выберите "Сегодня" - это повысит шанс быстрого отклика.',
      ),
    ];
  }

  List<Widget> _buildBudgetStep(BuildContext context) {
    const budgets = [
      'до 150 TJS',
      'до 300 TJS',
      '200-400 TJS',
      'жду предложений',
    ];
    return [
      if (widget.preferredMaster != null) ...[
        _PreferredMasterBanner(master: widget.preferredMaster!),
        const SizedBox(height: 16),
      ],
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final value in budgets)
            _SelectionChip(
              icon: Icons.payments_outlined,
              label: value,
              active: _budget.text == value,
              onTap: () => setState(() => _budget.text = value),
            ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _budget,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Свой бюджет',
          prefixIcon: Icon(Icons.tune_outlined),
        ),
      ),
    ];
  }

  List<Widget> _buildReviewStep(BuildContext context) {
    return [
      if (widget.preferredMaster != null) ...[
        InfoCard(
          icon: Icons.person_pin_circle_outlined,
          title: 'Предпочтительный мастер',
          subtitle:
              '${widget.preferredMaster!['name'] ?? 'Мастер'} · ${widget.preferredMaster!['service'] ?? 'Специалист'}',
          footer: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _InlineBadge(
                  icon: Icons.star_rounded,
                  text:
                      '${widget.preferredMaster!['rating'] ?? 0} (${widget.preferredMaster!['reviews'] ?? 0})',
                  color: const Color(0xFFF59E0B),
                ),
                _InlineBadge(
                  icon: Icons.payments_outlined,
                  text:
                      widget.preferredMaster!['price'] as String? ??
                      'Цена по договорённости',
                  color: const Color(0xFF059669),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      InfoCard(
        icon: Icons.build_circle_outlined,
        title: _derivedTitle,
        subtitle: _desc.text.trim().isEmpty
            ? 'Описание не заполнено'
            : _desc.text.trim(),
      ),
      const SizedBox(height: 12),
      InfoCard(
        icon: Icons.place_outlined,
        title: '$_district, Душанбе',
        subtitle: _address.text.trim().isEmpty
            ? 'Адрес не заполнен'
            : _address.text.trim(),
      ),
      const SizedBox(height: 12),
      InfoCard(
        icon: Icons.event_outlined,
        title: _when,
        subtitle: _budget.text,
      ),
    ];
  }
}

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.apiClient,
    required this.orderId,
    this.isMaster = false,
  });

  final ApiClient apiClient;
  final int orderId;
  final bool isMaster;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _selectingResponse = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      widget.apiClient.getJson('/orders/${widget.orderId}');

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openMasterProfile(int masterId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MasterDetailScreen(apiClient: widget.apiClient, masterId: masterId),
      ),
    );
  }

  Future<void> _openChatForResponse(Map<String, dynamic> response) async {
    final chatsData = await widget.apiClient.getJson('/chats');
    final chats = asMapList(chatsData['chats']);
    final masterName = response['master'] as String? ?? '';
    Map<String, dynamic>? match;
    for (final chat in chats) {
      if (chat['orderId'] == widget.orderId && chat['master'] == masterName) {
        match = chat;
        break;
      }
    }
    if (!mounted) return;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Чат станет доступен сразу после выбора мастера.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          apiClient: widget.apiClient,
          chatId: match!['id'] as int,
          title: match['master'] as String? ?? 'Мастер',
          orderTitle: match['orderTitle'] as String? ?? 'Заказ',
        ),
      ),
    );
  }

  Future<void> _selectMaster(Map<String, dynamic> response) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Выбрать мастера?'),
          content: Text(
            'После выбора ${response['master'] ?? 'мастера'} по этой заявке станет доступен рабочий чат.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Выбрать'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _selectingResponse = true);
    try {
      final result = await widget.apiClient.postJson(
        '/orders/${widget.orderId}/select-master',
        body: {'responseId': response['id']},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${response['master'] ?? 'Мастер'} выбран. Чат уже доступен.',
          ),
        ),
      );
      await _refresh();
      if (!mounted) return;
      final chat = Map<String, dynamic>.from(
        result['chat'] as Map? ?? const <String, dynamic>{},
      );
      if (chat.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              apiClient: widget.apiClient,
              chatId: chat['id'] as int,
              title: chat['master'] as String? ?? 'Мастер',
              orderTitle: chat['orderTitle'] as String? ?? 'Заказ',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _selectingResponse = false);
      }
    }
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
      appBar: AppBar(title: const Text('Детали заявки')),
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
          final selectedMasterId = (order['selectedMasterId'] as num?)?.toInt();
          final selectedResponse = selectedMasterId == null
              ? null
              : responses.cast<Map<String, dynamic>?>().firstWhere(
                  (response) =>
                      (response?['masterId'] as num?)?.toInt() ==
                      selectedMasterId,
                  orElse: () => null,
                );
          final hasPreferredMaster =
              (order['preferredMasterId'] as num?) != null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE8EEF6)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0C0F172A),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order['title'] as String? ?? 'Заявка',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${order['category']} · р-н ${order['district']}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (widget.isMaster) ...[
                          _MetaInline(
                            icon: Icons.payments_outlined,
                            text: order['budget'] as String? ?? 'Без бюджета',
                            color: const Color(0xFF059669),
                          ),
                          _MetaInline(
                            icon: Icons.schedule_outlined,
                            text: order['when'] as String? ?? 'Срок не указан',
                          ),
                        ] else ...[
                          _MetaInline(
                            icon: Icons.visibility_outlined,
                            text: '${order['views'] ?? 12} просмотров',
                          ),
                          _MetaInline(
                            icon: Icons.chat_bubble_outline,
                            text: '${responses.length} отклика',
                            color: const Color(0xFF2563EB),
                          ),
                        ],
                        StatusPill(
                          icon: _orderStatusIcon(order['status'] as String?),
                          label: _orderStatusLabel(order['status'] as String?),
                          tone: _orderStatusTone(order['status'] as String?),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (!widget.isMaster &&
                  hasPreferredMaster &&
                  selectedResponse == null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD9E9FF)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_pin_circle_outlined,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Для этой заявки уже указан предпочтительный мастер. Можно дождаться его отклика или выбрать другого исполнителя ниже.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: const Color(0xFF1D4ED8),
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (!widget.isMaster && selectedResponse != null) ...[
                InfoCard(
                  icon: Icons.verified_user_outlined,
                  title:
                      '${selectedResponse['master'] ?? 'Исполнитель'} уже выбран',
                  subtitle:
                      'Можно перейти в чат и согласовать детали перед выполнением работы.',
                  trailing: const StatusPill(
                    icon: Icons.check_circle_outline,
                    label: 'Выбран',
                    tone: StatusTone.success,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (widget.isMaster && selectedMasterId != null) ...[
                InfoCard(
                  icon: Icons.info_outline,
                  title: 'Заказ уже в работе',
                  subtitle:
                      'Заказчик уже выбрал исполнителя по этой заявке. Можно посмотреть детали, но новый отклик больше не нужен.',
                  trailing: const StatusPill(
                    icon: Icons.lock_outline,
                    label: 'Закрыт',
                    tone: StatusTone.warning,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order['desc'] as String? ?? '',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF475569),
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _OrderFactRow(
                      label: 'Район',
                      value: '${order['district']}, Душанбе',
                    ),
                    const SizedBox(height: 12),
                    _OrderFactRow(
                      label: 'Адрес',
                      value: order['address'] as String? ?? 'Не указан',
                    ),
                    const SizedBox(height: 12),
                    _OrderFactRow(
                      label: 'Бюджет',
                      value: order['budget'] as String? ?? '',
                    ),
                    const SizedBox(height: 12),
                    _OrderFactRow(
                      label: 'Когда',
                      value: order['when'] as String? ?? '',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (widget.isMaster) ...[
                const SectionTitle(
                  title: 'Перед откликом',
                  subtitle:
                      'Коротко опишите, когда готовы взять заказ и какую цену предлагаете.',
                ),
                const SizedBox(height: 12),
                InfoCard(
                  icon: Icons.tips_and_updates_outlined,
                  title: responses.isEmpty
                      ? 'Вы можете стать первым'
                      : 'Откликов уже: ${responses.length}',
                  subtitle: selectedMasterId == null
                      ? 'Чем понятнее комментарий и срок, тем выше шанс, что заказчик откроет именно ваш чат.'
                      : 'Заказ уже закрыт для новых предложений.',
                ),
              ] else ...[
                const SectionTitle(
                  title: 'Отклики мастеров',
                  subtitle:
                      'Сравните цену, опыт и выберите подходящего исполнителя',
                ),
                const SizedBox(height: 12),
                if (responses.isEmpty)
                  const EmptyState(
                    icon: Icons.mark_chat_unread_outlined,
                    text: 'Откликов пока нет',
                    subtitle:
                        'Когда мастера увидят заявку, их предложения появятся в этом списке.',
                  ),
                for (final response in responses) ...[
                  _ResponseCard(
                    response: response,
                    onOpenChat: () => _openChatForResponse(response),
                    onOpenProfile: () =>
                        _openMasterProfile(response['masterId'] as int),
                    onSelect: _selectingResponse
                        ? null
                        : () => _selectMaster(response),
                    isSelected:
                        (response['masterId'] as num?)?.toInt() ==
                        selectedMasterId,
                    selectionLocked: selectedMasterId != null,
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ],
          );
        },
      ),
      floatingActionButton: widget.isMaster
          ? FloatingActionButton.extended(
              onPressed: _showResponseSheet,
              icon: const Icon(Icons.reply_outlined),
              label: const Text('Откликнуться'),
            )
          : null,
    );
  }
}

class _MasterDetailData {
  const _MasterDetailData({required this.master, required this.reviews});

  final Map<String, dynamic> master;
  final List<Map<String, dynamic>> reviews;
}

class MasterDetailScreen extends StatefulWidget {
  const MasterDetailScreen({
    super.key,
    required this.apiClient,
    required this.masterId,
    this.categories = const [],
  });

  final ApiClient apiClient;
  final int masterId;
  final List<Map<String, dynamic>> categories;

  @override
  State<MasterDetailScreen> createState() => _MasterDetailScreenState();
}

class _MasterDetailScreenState extends State<MasterDetailScreen> {
  late Future<_MasterDetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MasterDetailData> _load() async {
    final results = await Future.wait([
      widget.apiClient.getJson('/masters/${widget.masterId}'),
      widget.apiClient.getJson('/masters/${widget.masterId}/reviews'),
    ]);
    return _MasterDetailData(
      master: Map<String, dynamic>.from(
        results[0]['master'] as Map? ?? const <String, dynamic>{},
      ),
      reviews: asMapList(results[1]['reviews']),
    );
  }

  Future<void> _openCreateOrder(Map<String, dynamic> master) async {
    final service = master['service'] as String? ?? 'Сантехника';
    final categories = widget.categories.isEmpty
        ? [
            {'name': service},
          ]
        : widget.categories;
    if (!mounted) return;
    await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => CreateOrderScreen(
          apiClient: widget.apiClient,
          categories: categories,
          initialCategory: service,
          preferredMaster: master,
        ),
      ),
    );
  }

  Future<void> _startContactFlow(Map<String, dynamic> master) async {
    final masterName = master['name'] as String? ?? '';
    try {
      final chatsData = await widget.apiClient.getJson('/chats');
      final chats = asMapList(chatsData['chats']);
      final existing = chats.cast<Map<String, dynamic>?>().firstWhere(
        (chat) => chat?['master'] == masterName,
        orElse: () => null,
      );
      if (existing != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              apiClient: widget.apiClient,
              chatId: existing['id'] as int,
              title: masterName,
              orderTitle: existing['orderTitle'] as String? ?? 'Заказ',
            ),
          ),
        );
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Создайте заявку с этим мастером, и после публикации сможете продолжить общение по заказу.',
        ),
      ),
    );
    await _openCreateOrder(master);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_MasterDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: () async => setState(() => _future = _load()),
            );
          }
          final payload = snapshot.data!;
          final master = payload.master;
          final masterReviews = payload.reviews;
          final skills = List<String>.from(
            master['skills'] as List? ?? const [],
          );
          final portfolio = List<String>.from(
            master['portfolio'] as List? ?? const [],
          );
          final name = master['name'] as String? ?? 'Мастер';
          final initials = _initials(name);
          final accent = _masterAccent(name);
          final service = master['service'] as String? ?? 'Услуги';
          final price = master['price'] as String? ?? 'Цена по договорённости';
          final verified = master['verified'] == true;
          final ratingText = '${master['rating'] ?? 0}';
          final reviews = (master['reviews'] as num?)?.toInt() ?? 0;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: const Text('Профиль мастера'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF18213A), Color(0xFF2847A6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x160F172A),
                        blurRadius: 22,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: LinearGradient(
                                colors: [
                                  accent,
                                  accent.withValues(alpha: 0.72),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _HeaderBadge(
                                      label: verified
                                          ? 'Проверенный профиль'
                                          : 'Без верификации',
                                    ),
                                    _HeaderBadge(label: service),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Color(0xFFFBBF24),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$ratingText ($reviews отзывов)',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _AdaptiveStatGrid(
                        minTileWidth: 96,
                        children: [
                          MetricCard(
                            label: 'Рейтинг',
                            value: ratingText,
                            isInverted: true,
                          ),
                          MetricCard(
                            label: 'Отзывы',
                            value: '$reviews',
                            isInverted: true,
                          ),
                          MetricCard(
                            label: 'Проверка',
                            value: verified ? 'Да' : 'Нет',
                            isInverted: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _AdaptiveStatGrid(
                  minTileWidth: 150,
                  children: [
                    _MasterFactTile(
                      icon: Icons.payments_outlined,
                      title: 'Цена',
                      value: price,
                      accent: const Color(0xFF059669),
                    ),
                    _MasterFactTile(
                      icon: Icons.home_repair_service_outlined,
                      title: 'Специализация',
                      value: service,
                      accent: accent,
                    ),
                    _MasterFactTile(
                      icon: verified
                          ? Icons.verified_user_outlined
                          : Icons.shield_outlined,
                      title: 'Статус',
                      value: verified ? 'Профиль подтверждён' : 'Без проверки',
                      accent: verified
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFF59E0B),
                    ),
                    _MasterFactTile(
                      icon: Icons.rate_review_outlined,
                      title: 'Отклик клиентов',
                      value: '$reviews отзывов',
                      accent: const Color(0xFF8B5CF6),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SectionTitle(
                  title: 'О мастере',
                  subtitle:
                      'Кратко о специализации, опыте и том, что важно знать перед выбором.',
                ),
                const SizedBox(height: 12),
                InfoCard(
                  icon: Icons.description_outlined,
                  title: service,
                  subtitle:
                      master['bio'] as String? ?? 'Описание пока не добавлено.',
                ),
                const SizedBox(height: 20),
                SectionTitle(
                  title: 'Услуги',
                  subtitle: 'Основное направление и дополнительные задачи.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SelectionChip(
                      icon: _categoryIcon(service),
                      label: service,
                      active: true,
                      onTap: () {},
                    ),
                    for (final skill in skills) _CompactSkillTag(label: skill),
                  ],
                ),
                const SizedBox(height: 20),
                SectionTitle(
                  title: 'Отзывы клиентов',
                  subtitle:
                      'Посмотрите, что пишут заказчики о скорости, качестве и общении.',
                ),
                const SizedBox(height: 12),
                if (masterReviews.isEmpty)
                  const EmptyState(
                    icon: Icons.reviews_outlined,
                    text: 'Отзывов пока нет',
                    subtitle:
                        'Этот мастер ещё не получил публичных отзывов от клиентов.',
                  )
                else ...[
                  for (final review in masterReviews) ...[
                    _MasterReviewCard(review: review),
                    const SizedBox(height: 10),
                  ],
                ],
                const SizedBox(height: 20),
                SectionTitle(
                  title: 'Портфолио',
                  subtitle: 'Примеры работ по этой специализации.',
                ),
                const SizedBox(height: 12),
                if (portfolio.isEmpty)
                  const EmptyState(
                    icon: Icons.photo_library_outlined,
                    text: 'Портфолио пока не добавлено',
                    subtitle:
                        'Можно ориентироваться на отзывы, специализацию и описание мастера.',
                  )
                else ...[
                  SizedBox(
                    height: 156,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: portfolio.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final item = portfolio[index];
                        return Container(
                          width: 156,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: LinearGradient(
                              colors: [
                                _portfolioColor(index),
                                _portfolioColor(index).withValues(alpha: 0.72),
                              ],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x120F172A),
                                blurRadius: 16,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item, style: const TextStyle(fontSize: 34)),
                              const Spacer(),
                              Text(
                                'Работа ${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _AdaptiveStatGrid(
                  minTileWidth: 150,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _startContactFlow(master),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Написать'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2B5DE0),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _openCreateOrder(master),
                      icon: const Icon(Icons.assignment_turned_in_outlined),
                      label: const Text('Выбрать мастера'),
                    ),
                  ],
                ),
              ),
            ),
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
    required this.orderTitle,
    this.isMaster = false,
  });

  final ApiClient apiClient;
  final int chatId;
  final String title;
  final String orderTitle;
  final bool isMaster;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  bool _sending = false;
  String? _sendError;

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
    if (text.isEmpty || _sending) return;
    final fromRole = widget.isMaster ? 'master' : 'customer';
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await widget.apiClient.postJson(
        '/chats/${widget.chatId}/messages',
        body: {'text': text, 'fromRole': fromRole},
      );
      _controller.clear();
      setState(() {
        _future = _load();
      });
    } on ApiException catch (error) {
      setState(() {
        _sendError = error.message;
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, widget.isMaster ? 24 : 52, 16, 12),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                Container(
                  width: widget.isMaster ? 56 : 62,
                  height: widget.isMaster ? 56 : 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      widget.isMaster ? 18 : 20,
                    ),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(widget.title),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.isMaster
                            ? 'Диалог по заказу'
                            : 'Мастер на связи',
                        style: TextStyle(
                          color: widget.isMaster
                              ? const Color(0xFF64748B)
                              : const Color(0xFF10B981),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                widget.orderTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: widget.isMaster
                  ? const Color(0xFFF6F8FB)
                  : const Color(0xFFEAF0F8),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ErrorState(
                      message: snapshot.error.toString(),
                      onRetry: () async {
                        setState(() {
                          _future = _load();
                        });
                        await _future;
                      },
                    );
                  }
                  final messages = snapshot.data ?? [];
                  if (messages.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: EmptyState(
                          icon: Icons.mark_chat_read_outlined,
                          text: widget.isMaster
                              ? 'Диалог пока пуст'
                              : 'Чат ещё не начался',
                          subtitle: widget.isMaster
                              ? 'Первый ответ часто помогает быстрее договориться по заказу.'
                              : 'Напишите первым, чтобы быстрее согласовать время, цену и детали работы.',
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final fromRole =
                          message['fromRole'] as String? ?? 'customer';
                      final mine = widget.isMaster
                          ? fromRole == 'master'
                          : fromRole == 'customer';
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: widget.isMaster ? 420 : 380,
                          ),
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: EdgeInsets.fromLTRB(
                            18,
                            widget.isMaster ? 14 : 16,
                            18,
                            12,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFF2B5DE0)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(
                              widget.isMaster ? 22 : 28,
                            ),
                            border: widget.isMaster && !mine
                                ? Border.all(color: const Color(0xFFE2E8F0))
                                : null,
                            boxShadow: widget.isMaster
                                ? null
                                : const [
                                    BoxShadow(
                                      color: Color(0x100F172A),
                                      blurRadius: 14,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                          ),
                          child: Column(
                            crossAxisAlignment: mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!mine) ...[
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              Text(
                                message['text'] as String? ?? '',
                                style: TextStyle(
                                  color: mine
                                      ? Colors.white
                                      : const Color(0xFF1F2940),
                                  fontSize: widget.isMaster ? 14 : 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                message['createdAt'] as String? ?? '14:05',
                                style: TextStyle(
                                  color: mine
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : const Color(0xFF94A3B8),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sendError != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _sendError!,
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: widget.isMaster
                                ? 'Ответить по заказу...'
                                : 'Написать мастеру...',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: widget.isMaster ? 54 : 64,
                        height: widget.isMaster ? 54 : 64,
                        decoration: BoxDecoration(
                          color: _sending
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF2B5DE0),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
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
    setState(() {
      _future = _load();
    });
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
      appBar: AppBar(title: const Text('Кошелёк')),
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
              padding: EdgeInsets.zero,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF141B31), Color(0xFF253D8F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'Баланс кошелька',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${wallet['balance']} ${wallet['currency']}',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '≈ ${(wallet['balance'] as int? ?? 85) / 11} USD',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: const Color(0xFF2B5DE0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                        ),
                        onPressed: _toppingUp ? null : _topUp,
                        icon: const Icon(Icons.add),
                        label: const Text('Пополнить'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'БЫСТРОЕ ПОПОЛНЕНИЕ',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final amount in [20, 50, 100, 200]) ...[
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: amount == 200 ? 0 : 10,
                                ),
                                child: _TopUpPreset(
                                  amount: amount,
                                  active: _amount.text == '$amount',
                                  onTap: () => setState(() {
                                    _amount.text = '$amount';
                                  }),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _PaymentMethodCard(
                              icon: Icons.sim_card_outlined,
                              label: 'alif mobi',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PaymentMethodCard(
                              icon: Icons.account_balance_outlined,
                              label: 'Карта',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Своя сумма, TJS',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ИСТОРИЯ ТРАНЗАКЦИЙ',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      if (transactions.isEmpty)
                        const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          text: 'Транзакций пока нет',
                          subtitle:
                              'История пополнений и списаний появится после первых операций.',
                        ),
                      for (final tx in transactions) ...[
                        _TransactionTile(tx: tx),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
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
    setState(() {
      _future = _load();
    });
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
      appBar: AppBar(title: const Text('Верификация мастера')),
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
          final currentStep = verified
              ? 5
              : (documents.length >= 2 ? 3 : documents.length + 1);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF141B31), Color(0xFF253D8F)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Текущий статус',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 18),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      verified
                          ? 'Профиль активен · Шаг 5/5'
                          : 'В процессе · Шаг $currentStep/5',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: currentStep / 5,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'SLA: не более 24 часов',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              _VerificationTimeline(
                currentStep: currentStep,
                documentsCount: documents.length,
                verified: verified,
              ),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Документы'),
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
              const SectionTitle(title: 'Загрузить документ'),
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
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Ваш отклик',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Цена (TJS)',
              prefixText: 'TJS ',
              hintText: 'Стоимость работ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Комментарий',
              hintText: 'Здравствуйте! Опыт 8 лет, приеду сегодня...',
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.savings_outlined, color: Color(0xFFB45309)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Стоимость отклика: 4 TJS\nСписывается с кошелька при отправке',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
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
          Row(
            children: const [
              Text(
                'Баланс: 85 TJS',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              Text(
                'Спишется: -4 TJS',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2B5DE0),
                foregroundColor: Colors.white,
              ),
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_outlined),
              label: Text(
                _sending ? 'Отправка...' : 'Откликнуться за 4 TJS ->',
              ),
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
    final title = order['title'] as String? ?? 'Заявка';
    final description = (order['desc'] as String? ?? '').trim();
    final category = order['category'] as String? ?? 'Без категории';
    final district = order['district'] as String? ?? 'Район не указан';
    final budget = (order['budget'] as String? ?? '').trim();
    final views = order['views'] ?? 0;
    final responses = order['responses'] ?? 0;
    final createdAt = _orderCreatedLabel(order['createdAt'] as String?);
    final status = order['status'] as String?;

    final categoryColor = _categoryColor(category);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE8EEF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _categoryIcon(category),
                      color: categoryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                                height: 1.2,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusPill(
                    icon: _orderStatusIcon(status),
                    label: _orderStatusLabel(status),
                    tone: _orderStatusTone(status),
                  ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475467),
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE6ECF5)),
                ),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    _MetaInline(
                      icon: Icons.location_on_outlined,
                      text: district,
                    ),
                    if (budget.isNotEmpty)
                      _MetaInline(
                        icon: Icons.payments_outlined,
                        text: budget,
                        color: const Color(0xFF059669),
                      ),
                    _MetaInline(icon: Icons.schedule_outlined, text: createdAt),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _TinyStat(icon: Icons.visibility_outlined, text: '$views'),
                  const SizedBox(width: 16),
                  _TinyStat(
                    icon: Icons.chat_bubble_outline,
                    text: '$responses',
                  ),
                  const Spacer(),
                  Text(
                    'Подробнее',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersSummaryCard extends StatelessWidget {
  const _OrdersSummaryCard({required this.orders, required this.onCreateOrder});

  final List<Map<String, dynamic>> orders;
  final VoidCallback onCreateOrder;

  @override
  Widget build(BuildContext context) {
    final activeCount = orders
        .where((order) => _orderStatusIsActive(order['status'] as String?))
        .length;
    final totalResponses = orders.fold<int>(
      0,
      (sum, order) => sum + ((order['responses'] as num?)?.toInt() ?? 0),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ваши заявки',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          orders.isEmpty
                              ? 'Здесь появятся созданные вами обращения.'
                              : 'Следите за статусами, откликами и активностью мастеров.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF667085)),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: onCreateOrder,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Создать'),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ваши заявки',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                orders.isEmpty
                                    ? 'Здесь появятся созданные вами обращения.'
                                    : 'Следите за статусами, откликами и активностью мастеров.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF667085)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: onCreateOrder,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Создать'),
                        ),
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          _AdaptiveStatGrid(
            minTileWidth: 96,
            children: [
              _SummaryStatTile(
                label: 'Всего',
                value: '${orders.length}',
                accent: const Color(0xFF0F172A),
              ),
              _SummaryStatTile(
                label: 'Активные',
                value: '$activeCount',
                accent: const Color(0xFF059669),
              ),
              _SummaryStatTile(
                label: 'Отклики',
                value: '$totalResponses',
                accent: const Color(0xFF2563EB),
              ),
            ],
          ),
          if (orders.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6ECF5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tips_and_updates_outlined,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Открывайте заявку, чтобы смотреть отклики и перейти в чат с мастером.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerHeroCard extends StatelessWidget {
  const _CustomerHeroCard({required this.onCreateOrder});

  final VoidCallback onCreateOrder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF2250D9), Color(0xFF4E86F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: 12,
            child: Container(
              width: 118,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
          ),
          Positioned(
            right: 26,
            bottom: -6,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'НУЖЕН МАСТЕР?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD8E6FF),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Найдите мастера\nза пару минут',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.16,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Создайте заявку и получите отклики от подходящих специалистов.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.84),
                  fontSize: 13,
                  height: 1.32,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2456DF),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: onCreateOrder,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Создать'),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Text(
                      'Онлайн 24/7',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onTap});

  final String title;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: const Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9E4F5),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton.icon(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = _categoryIcon(label);
    final color = _categoryColor(label);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFDFE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE7EDF5)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2940),
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerQuickActions extends StatelessWidget {
  const _CustomerQuickActions({
    required this.onCreateOrder,
    required this.onOpenOrders,
    required this.onOpenMasters,
    required this.onOpenProfile,
    this.onOpenChat,
  });

  final VoidCallback onCreateOrder;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenMasters;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionTile(
            icon: Icons.add_circle_outline,
            label: 'Создать',
            accent: const Color(0xFF2563EB),
            onTap: onCreateOrder,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.assignment_outlined,
            label: 'Заявки',
            accent: const Color(0xFF059669),
            onTap: onOpenOrders,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.groups_outlined,
            label: 'Мастера',
            accent: const Color(0xFF8B5CF6),
            onTap: onOpenMasters,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionTile(
            icon: onOpenChat == null
                ? Icons.person_outline
                : Icons.chat_bubble_outline,
            label: onOpenChat == null ? 'Профиль' : 'Чат',
            accent: onOpenChat == null
                ? const Color(0xFFF59E0B)
                : const Color(0xFFEF4444),
            onTap: onOpenChat ?? onOpenProfile,
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE8EEF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0F172A),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2940),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewSummaryCard extends StatelessWidget {
  const _OverviewSummaryCard({
    required this.ordersCount,
    required this.chatsCount,
    required this.mastersCount,
  });

  final int ordersCount;
  final int chatsCount;
  final int mastersCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryStatTile(
              label: 'Заявки',
              value: '$ordersCount',
              accent: const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryStatTile(
              label: 'Чаты',
              value: '$chatsCount',
              accent: const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryStatTile(
              label: 'Мастера',
              value: '$mastersCount',
              accent: const Color(0xFF059669),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStatTile extends StatelessWidget {
  const _SummaryStatTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
              fontSize: 13,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6ECF5)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedMasterCard extends StatelessWidget {
  const _FeaturedMasterCard({required this.master, required this.onTap});

  final Map<String, dynamic> master;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = master['name'] as String? ?? 'Мастер';
    final initials = _initials(name);
    final accent = _masterAccent(name);
    final service = master['service'] as String? ?? '';
    final price = master['price'] as String? ?? '';
    final isVerified = master['verified'] == true;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 208,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C0F172A),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: 0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                if (isVerified)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: Color(0xFF12B76A),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Проверен',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF067647),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                fontSize: 15,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              service,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF667085),
                fontSize: 13,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6ECF5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${master['rating']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2940),
                    ),
                  ),
                  Text(
                    ' (${master['reviews'] ?? 0})',
                    style: const TextStyle(color: Color(0xFF98A2B3)),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Text(
                  'Отклик и чат',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MasterListCard extends StatelessWidget {
  const _MasterListCard({required this.master, required this.onTap});

  final Map<String, dynamic> master;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = master['name'] as String? ?? 'Мастер';
    final service = master['service'] as String? ?? '';
    final price = master['price'] as String? ?? '';
    final reviews = master['reviews'] ?? 0;
    final rating = '${master['rating'] ?? 0}';
    final isVerified = master['verified'] == true;
    final accent = _masterAccent(name);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE8EEF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0.72)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                                height: 1.15,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          service,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (isVerified)
                              const StatusPill(
                                icon: Icons.verified_rounded,
                                label: 'Проверен',
                                tone: StatusTone.success,
                              ),
                            _InlineBadge(
                              icon: Icons.star_rounded,
                              text: '$rating ($reviews)',
                              color: const Color(0xFFF59E0B),
                            ),
                            _InlineBadge(
                              icon: Icons.payments_outlined,
                              text: price,
                              color: const Color(0xFF2563EB),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Открыть профиль, отзывы и действия',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerOrderCard extends StatelessWidget {
  const _CustomerOrderCard({required this.order, required this.onTap});

  final Map<String, dynamic> order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String?;
    final title = order['title'] as String? ?? 'Заявка';
    final description = order['desc'] as String? ?? '';
    final district = order['district'] as String? ?? '';
    final budget = order['budget'] as String? ?? '';
    final when = order['when'] as String? ?? '';
    final responses = '${order['responses'] ?? 0}';
    final views = '${order['views'] ?? 0}';
    final createdAt = _orderCreatedLabel(order['createdAt'] as String?);
    final hasPreferredMaster = (order['preferredMasterId'] as num?) != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C0F172A),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              height: 1.2,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 15,
                            color: Color(0xFF98A2B3),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            createdAt,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: const Color(0xFF98A2B3),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                StatusPill(
                  icon: _orderStatusIcon(status),
                  label: _orderStatusLabel(status),
                  tone: _orderStatusTone(status),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF667085),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE6ECF5)),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  _MetaInline(icon: Icons.location_on_outlined, text: district),
                  _MetaInline(
                    icon: Icons.payments_outlined,
                    text: budget,
                    color: const Color(0xFF059669),
                  ),
                  _MetaInline(icon: Icons.event_outlined, text: when),
                ],
              ),
            ),
            if (hasPreferredMaster) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF6FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD9E9FF)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_pin_circle_outlined,
                      size: 18,
                      color: Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Для этой заявки уже выбран предпочтительный мастер',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF1D4ED8),
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _TinyStat(icon: Icons.visibility_outlined, text: views),
                const SizedBox(width: 16),
                _TinyStat(icon: Icons.chat_bubble_outline, text: responses),
                const Spacer(),
                Text(
                  'Открыть',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaInline extends StatelessWidget {
  const _MetaInline({
    required this.icon,
    required this.text,
    this.color = const Color(0xFF64748B),
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _TinyStat extends StatelessWidget {
  const _TinyStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SelectionChip extends StatelessWidget {
  const _SelectionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFFEEF4FF) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? const Color(0xFF93C5FD) : const Color(0xFFDCE5E3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: active
                    ? const Color(0xFF2B5DE0)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? const Color(0xFF2B5DE0)
                      : const Color(0xFF334155),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CategorySelectorSheet extends StatelessWidget {
  const _CategorySelectorSheet({
    required this.categories,
    required this.current,
  });

  final List<String> categories;
  final String current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Выберите категорию',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final category in categories) ...[
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: category == current
                  ? const Color(0xFFEEF4FF)
                  : Colors.white,
              leading: Icon(
                _categoryIcon(category),
                color: _categoryColor(category),
              ),
              title: Text(category),
              trailing: category == current
                  ? const Icon(Icons.check, color: Color(0xFF2B5DE0))
                  : null,
              onTap: () => Navigator.of(context).pop(category),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({
    required this.response,
    required this.onOpenChat,
    required this.onOpenProfile,
    required this.onSelect,
    this.isSelected = false,
    this.selectionLocked = false,
  });

  final Map<String, dynamic> response;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenProfile;
  final VoidCallback? onSelect;
  final bool isSelected;
  final bool selectionLocked;

  @override
  Widget build(BuildContext context) {
    final master = response['master'] as String? ?? 'Мастер';
    final accent = _masterAccent(master);
    final canSelect = !selectionLocked || isSelected;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.74)],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(master),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      master,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified,
                              size: 16,
                              color: Color(0xFF2563EB),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Проверен',
                              style: TextStyle(
                                color: Color(0xFF2563EB),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              size: 16,
                              color: Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${response['rating'] ?? 4.8}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1F2940),
                              ),
                            ),
                            Text(
                              ' (${response['reviews'] ?? 89})',
                              style: const TextStyle(color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${response['price']} TJS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                response['createdAt'] as String? ?? 'Недавно',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              response['comment'] as String? ?? '',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF475569),
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _AdaptiveStatGrid(
            minTileWidth: 136,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Чат'),
              ),
              OutlinedButton(
                onPressed: onOpenProfile,
                child: const Text('Профиль'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isSelected
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF2B5DE0),
                  foregroundColor: Colors.white,
                ),
                onPressed: isSelected
                    ? onOpenChat
                    : (canSelect ? onSelect : null),
                child: Text(isSelected ? 'Открыть чат' : 'Выбрать'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MasterOverviewPage extends StatelessWidget {
  const MasterOverviewPage({
    super.key,
    required this.data,
    required this.onOpenOrder,
    required this.onOpenWallet,
  });

  final HomeData data;
  final ValueChanged<Map<String, dynamic>> onOpenOrder;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    final profile = data.profile;
    final orders = data.orders.take(3).toList();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          decoration: const BoxDecoration(color: Color(0xFF141B31)),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF60A5FA),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    profile['city'] as String? ?? 'Душанбе',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 4,
                          backgroundColor: Color(0xFF34D399),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Онлайн',
                          style: TextStyle(
                            color: Color(0xFF6EE7B7),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onOpenWallet,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Кошелёк',
                              style: TextStyle(color: Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${data.wallet['balance']} ${data.wallet['currency']}',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFFBFDBFE),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final order in orders) ...[
                _MasterJobCard(order: order, onTap: () => onOpenOrder(order)),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ChatsPage extends StatelessWidget {
  const ChatsPage({
    super.key,
    required this.chats,
    required this.onOpenChat,
    this.isMaster = false,
  });

  final List<Map<String, dynamic>> chats;
  final ValueChanged<Map<String, dynamic>> onOpenChat;
  final bool isMaster;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 6),
        SectionTitle(
          title: 'Чаты',
          subtitle: isMaster
              ? 'Только рабочие диалоги по актуальным заказам'
              : 'Все договорённости с мастерами собраны в одном месте',
        ),
        const SizedBox(height: 16),
        if (chats.isNotEmpty) ...[
          _ChatsSummaryCard(chats: chats, isMaster: isMaster),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE6ECF5)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isMaster
                        ? 'Открывайте диалог, чтобы быстро согласовать цену, срок и детали выезда.'
                        : 'Открывайте диалог, чтобы уточнить цену, адрес и время работы с мастером.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (chats.isEmpty)
          const EmptyState(
            icon: Icons.chat_bubble_outline,
            text: 'Диалогов пока нет',
            subtitle:
                'Когда появятся отклики или новые сообщения, они соберутся здесь.',
          ),
        for (final chat in chats) ...[
          _ChatTile(
            chat: chat,
            isMaster: isMaster,
            onTap: () => onOpenChat(chat),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ChatsSummaryCard extends StatelessWidget {
  const _ChatsSummaryCard({required this.chats, required this.isMaster});

  final List<Map<String, dynamic>> chats;
  final bool isMaster;

  @override
  Widget build(BuildContext context) {
    final freshCount = chats.where(_chatNeedsFirstMessage).length;
    final activeCount = chats.length - freshCount;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: _AdaptiveStatGrid(
        minTileWidth: 96,
        children: [
          _SummaryStatTile(
            label: 'Всего',
            value: '${chats.length}',
            accent: const Color(0xFF0F172A),
          ),
          _SummaryStatTile(
            label: isMaster ? 'Активные' : 'В работе',
            value: '$activeCount',
            accent: const Color(0xFF2563EB),
          ),
          _SummaryStatTile(
            label: 'Новые',
            value: '$freshCount',
            accent: const Color(0xFF059669),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.isMaster,
    required this.onTap,
  });

  final Map<String, dynamic> chat;
  final bool isMaster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final peerName = _chatPeerName(chat, isMaster: isMaster);
    final orderTitle = (chat['orderTitle'] as String? ?? 'Заказ').trim();
    final lastMessage = (chat['lastMessage'] as String? ?? '').trim();
    final lastTime = (chat['lastTime'] as String? ?? '').trim();
    final needsFirstMessage = _chatNeedsFirstMessage(chat);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(peerName),
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          orderTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF64748B),
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusPill(
                        icon: needsFirstMessage
                            ? Icons.fiber_new_outlined
                            : Icons.chat_bubble_outline,
                        label: needsFirstMessage ? 'Новый чат' : 'Активен',
                        tone: needsFirstMessage
                            ? StatusTone.success
                            : StatusTone.neutral,
                      ),
                      if (lastTime.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          lastTime,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  lastMessage.isEmpty
                      ? (isMaster
                            ? 'Заказчик ещё не писал. Можно открыть чат и начать обсуждение.'
                            : 'Чат создан. Напишите первым, чтобы быстрее согласовать детали.')
                      : lastMessage,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.4,
                    fontWeight: lastMessage.isEmpty
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _TinyStat(
                    icon: Icons.assignment_outlined,
                    text: needsFirstMessage ? 'Нужен старт' : 'Есть переписка',
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterJobCard extends StatelessWidget {
  const _MasterJobCard({required this.order, required this.onTap});

  final Map<String, dynamic> order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((order['urgent'] as bool?) ?? false)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Срочно',
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              order['title'] as String? ?? 'Заявка',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              order['desc'] as String? ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF64748B),
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _MetaInline(
                  icon: Icons.location_pin,
                  text: order['district'] as String? ?? '',
                ),
                _MetaInline(
                  icon: Icons.payments_outlined,
                  text: order['budget'] as String? ?? '',
                  color: const Color(0xFF059669),
                ),
                _MetaInline(
                  icon: Icons.schedule,
                  text: '${order['createdAt'] ?? '5 мин назад'}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _TinyStat(
                  icon: Icons.visibility_outlined,
                  text: '${order['views'] ?? 8}',
                ),
                const SizedBox(width: 16),
                _TinyStat(
                  icon: Icons.chat_bubble_outline,
                  text: '${order['responses'] ?? 2}',
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: onTap,
                  child: const Text('Отклик'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopUpPreset extends StatelessWidget {
  const _TopUpPreset({
    required this.amount,
    required this.active,
    required this.onTap,
  });

  final int amount;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? const Color(0xFF2563EB) : const Color(0xFFDCE5E3),
            width: active ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              '$amount',
              style: const TextStyle(
                color: Color(0xFF1F2940),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'TJS',
              style: TextStyle(
                color: active
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE5E3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28, color: const Color(0xFF2563EB)),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1F2940),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});

  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final amount = tx['amount'] as int? ?? 0;
    final incoming = amount >= 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: incoming
                  ? const Color(0xFFD1FAE5)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              incoming ? Icons.arrow_upward : Icons.arrow_downward,
              color: incoming
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx['label'] as String? ?? 'Операция',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tx['createdAt'] as String? ?? '',
                  style: const TextStyle(color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          Text(
            '${incoming ? '+' : ''}$amount.00',
            style: TextStyle(
              color: incoming
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationTimeline extends StatelessWidget {
  const _VerificationTimeline({
    required this.currentStep,
    required this.documentsCount,
    required this.verified,
  });

  final int currentStep;
  final int documentsCount;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final items = [
      _VerificationStepData(
        title: 'Анкета отправлена',
        subtitle: 'Выполнено',
        state: currentStep > 1
            ? _VerificationState.done
            : _VerificationState.current,
      ),
      _VerificationStepData(
        title: 'Документы проверены',
        subtitle: documentsCount > 0
            ? 'Личность подтверждена'
            : 'Ожидает документы',
        state: documentsCount > 0
            ? _VerificationState.done
            : (currentStep == 2
                  ? _VerificationState.current
                  : _VerificationState.todo),
      ),
      _VerificationStepData(
        title: 'Тест по специальности',
        subtitle: 'Тест: Сантехника · 10 вопросов',
        state: currentStep == 3
            ? _VerificationState.current
            : (currentStep > 3
                  ? _VerificationState.done
                  : _VerificationState.todo),
      ),
      _VerificationStepData(
        title: 'Звонок оператора',
        subtitle: '5-минутная беседа, скрипт',
        state: currentStep == 4
            ? _VerificationState.current
            : (currentStep > 4
                  ? _VerificationState.done
                  : _VerificationState.todo),
      ),
      _VerificationStepData(
        title: 'Профиль активен',
        subtitle: 'Начинайте принимать заказы',
        state: verified ? _VerificationState.done : _VerificationState.todo,
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          _VerificationTimelineItem(
            index: i + 1,
            data: items[i],
            isLast: i == items.length - 1,
          ),
      ],
    );
  }
}

enum _VerificationState { done, current, todo }

class _VerificationStepData {
  const _VerificationStepData({
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final String title;
  final String subtitle;
  final _VerificationState state;
}

class _VerificationTimelineItem extends StatelessWidget {
  const _VerificationTimelineItem({
    required this.index,
    required this.data,
    required this.isLast,
  });

  final int index;
  final _VerificationStepData data;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final (circleColor, textColor, icon) = switch (data.state) {
      _VerificationState.done => (
        const Color(0xFF059669),
        const Color(0xFF059669),
        Icons.check,
      ),
      _VerificationState.current => (
        const Color(0xFFFCD34D),
        const Color(0xFFD97706),
        null,
      ),
      _VerificationState.todo => (
        const Color(0xFFE2E8F0),
        const Color(0xFF94A3B8),
        null,
      ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: circleColor,
                child: icon != null
                    ? Icon(icon, color: Colors.white)
                    : Text(
                        '$index',
                        style: TextStyle(
                          color: data.state == _VerificationState.todo
                              ? const Color(0xFF94A3B8)
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: const Color(0xFFE2E8F0),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: data.state == _VerificationState.todo
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF1F2940),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.subtitle,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: data.state == _VerificationState.current
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  if (index == 3 &&
                      data.state == _VerificationState.current) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Тест: Сантехника · 10 вопросов',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Пройдено 7/10 · Порог: 7/10',
                            style: TextStyle(color: Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderFactRow extends StatelessWidget {
  const _OrderFactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1F2940),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '✓ $label',
        style: const TextStyle(
          color: Color(0xFFBFDBFE),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MasterFactTile extends StatelessWidget {
  const _MasterFactTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1F2940),
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSkillTag extends StatelessWidget {
  const _CompactSkillTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PreferredMasterBanner extends StatelessWidget {
  const _PreferredMasterBanner({required this.master});

  final Map<String, dynamic> master;

  @override
  Widget build(BuildContext context) {
    final name = master['name'] as String? ?? 'Мастер';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E7FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  _masterAccent(name),
                  _masterAccent(name).withValues(alpha: 0.72),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(name),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Предпочтительный мастер',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  master['service'] as String? ?? 'Специалист',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterReviewCard extends StatelessWidget {
  const _MasterReviewCard({required this.review});

  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review['authorName'] as String? ?? 'Клиент',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                review['createdAt'] as String? ?? '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: List.generate(
              5,
              (index) => Icon(
                index < rating ? Icons.star_rounded : Icons.star_border_rounded,
                size: 18,
                color: const Color(0xFFF59E0B),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            review['text'] as String? ?? '',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475569),
              height: 1.45,
            ),
          ),
        ],
      ),
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
    this.footer,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: footer == null ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
                if (footer != null) ...[const SizedBox(height: 12), footer!],
              ],
            ),
          ),
          if (trailing case final trailingWidget?) ...[
            const SizedBox(width: 12),
            trailingWidget,
          ] else if (onTap != null) ...[
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ],
      ),
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.isInverted = false,
    this.accent,
  });

  final String label;
  final String value;
  final bool isInverted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final background = isInverted
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white;
    final valueColor = isInverted
        ? Colors.white
        : (accent ?? const Color(0xFF0F172A));
    final labelColor = isInverted
        ? Colors.white.withValues(alpha: 0.74)
        : const Color(0xFF64748B);
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: valueColor,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: labelColor,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdaptiveStatGrid extends StatelessWidget {
  const _AdaptiveStatGrid({required this.children, this.minTileWidth = 100});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var columns = (width / minTileWidth).floor();
        if (columns < 1) columns = 1;
        if (columns > children.length) columns = children.length;
        final itemWidth = columns == 1
            ? width
            : (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.subtitle,
  });

  final IconData icon;
  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeLoadingView extends StatelessWidget {
  const _HomeLoadingView();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF7F9FC), Color(0xFFEEF3FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 22,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Image.asset(BrandAssets.appIcon, fit: BoxFit.contain),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: 14),
            Text(
              'Загружаем данные',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF1F2940),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Это займёт всего пару секунд.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
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

class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.name,
    required this.role,
    required this.city,
    required this.stats,
    this.trailing,
  });

  final String name;
  final String role;
  final String city;
  final List<HeroStat> stats;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            BrandAssets.appIcon,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: compact ? 18 : 20,
                                    height: 1.1,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_roleLabel(role)} · $city',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.82),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: trailing!),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _AdaptiveStatGrid(
            minTileWidth: 96,
            children: [
              for (final stat in stats)
                MetricCard(
                  label: stat.label,
                  value: stat.value,
                  isInverted: true,
                  accent: stat.accent,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class HeroStat {
  const HeroStat({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;
}

enum StatusTone { neutral, success, warning }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  final IconData icon;
  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      StatusTone.success => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      StatusTone.warning => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      StatusTone.neutral => (const Color(0xFFE2E8F0), const Color(0xFF334155)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.$2),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colors.$2,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'master':
      return 'Мастер';
    case 'customer':
      return 'Заказчик';
    default:
      return role;
  }
}

String _chatPeerName(Map<String, dynamic> chat, {required bool isMaster}) {
  final peer = isMaster
      ? chat['customer'] as String?
      : chat['master'] as String?;
  final value = (peer ?? '').trim();
  return value.isEmpty ? 'Чат' : value;
}

bool _chatNeedsFirstMessage(Map<String, dynamic> chat) {
  final lastMessage = (chat['lastMessage'] as String? ?? '').trim();
  return lastMessage.isEmpty;
}

bool _orderStatusIsActive(String? status) {
  final value = (status ?? '').toLowerCase();
  return value.isEmpty ||
      value == 'new' ||
      value == 'open' ||
      value == 'active' ||
      value == 'published' ||
      value == 'pending' ||
      value == 'in_progress' ||
      value == 'активная' ||
      value == 'новая' ||
      value == 'мастер выбран';
}

String _orderStatusLabel(String? status) {
  final value = (status ?? '').toLowerCase();
  switch (value) {
    case 'new':
    case 'open':
    case 'active':
    case 'published':
      return 'Активна';
    case 'pending':
      return 'На проверке';
    case 'in_progress':
      return 'В работе';
    case 'мастер выбран':
      return 'Мастер выбран';
    case 'completed':
    case 'done':
      return 'Завершена';
    case 'cancelled':
    case 'canceled':
      return 'Отменена';
    default:
      return 'Активна';
  }
}

StatusTone _orderStatusTone(String? status) {
  final value = (status ?? '').toLowerCase();
  switch (value) {
    case 'completed':
    case 'done':
      return StatusTone.success;
    case 'pending':
    case 'cancelled':
    case 'canceled':
      return StatusTone.warning;
    default:
      return StatusTone.neutral;
  }
}

IconData _orderStatusIcon(String? status) {
  final value = (status ?? '').toLowerCase();
  switch (value) {
    case 'completed':
    case 'done':
      return Icons.check_circle_outline;
    case 'in_progress':
      return Icons.construction_outlined;
    case 'мастер выбран':
      return Icons.verified_user_outlined;
    case 'pending':
      return Icons.pending_actions_outlined;
    case 'cancelled':
    case 'canceled':
      return Icons.cancel_outlined;
    default:
      return Icons.bolt_outlined;
  }
}

String _orderCreatedLabel(String? createdAt) {
  final value = (createdAt ?? '').trim();
  if (value.isEmpty) return 'Только что';
  return value;
}

double _averageMasterRating(List<Map<String, dynamic>> masters) {
  if (masters.isEmpty) return 0;
  final total = masters.fold<double>(0, (sum, master) {
    final raw = master['rating'];
    if (raw is num) return sum + raw.toDouble();
    return sum + (double.tryParse('$raw') ?? 0);
  });
  return total / masters.length;
}

IconData _categoryIcon(String label) {
  final value = label.toLowerCase();
  if (value.contains('сант')) return Icons.plumbing_outlined;
  if (value.contains('элект')) return Icons.bolt_outlined;
  if (value.contains('ремонт')) return Icons.construction_outlined;
  if (value.contains('меб')) return Icons.chair_outlined;
  if (value.contains('уборк')) return Icons.cleaning_services_outlined;
  if (value.contains('груз')) return Icons.inventory_2_outlined;
  if (value.contains('конд')) return Icons.ac_unit_outlined;
  if (value.contains('тех')) return Icons.laptop_chromebook_outlined;
  return Icons.home_repair_service_outlined;
}

Color _categoryColor(String label) {
  final value = label.toLowerCase();
  if (value.contains('сант')) return const Color(0xFF60A5FA);
  if (value.contains('элект')) return const Color(0xFFFACC15);
  if (value.contains('ремонт')) return const Color(0xFFFB7185);
  if (value.contains('меб')) return const Color(0xFF34D399);
  if (value.contains('уборк')) return const Color(0xFFA78BFA);
  if (value.contains('груз')) return const Color(0xFFF59E0B);
  if (value.contains('конд')) return const Color(0xFF22D3EE);
  if (value.contains('тех')) return const Color(0xFF94A3B8);
  return const Color(0xFF2B5DE0);
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'US';
  if (parts.length == 1) {
    return parts.first.characters.take(2).toString().toUpperCase();
  }
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}

Color _masterAccent(String seed) {
  final accents = [
    const Color(0xFF2563EB),
    const Color(0xFF10B981),
    const Color(0xFF8B5CF6),
    const Color(0xFFF59E0B),
  ];
  return accents[seed.hashCode.abs() % accents.length];
}

Color _portfolioColor(int index) {
  const colors = [
    Color(0xFF1D4ED8),
    Color(0xFF059669),
    Color(0xFF6D28D9),
    Color(0xFFF59E0B),
  ];
  return colors[index % colors.length];
}
