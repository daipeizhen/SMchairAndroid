import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../state/chair_sync_controller.dart';
import 'auth_page.dart';
import 'dashboard.dart';
import 'notification.dart';
import 'setting.dart';
import 'ai_advice_page.dart';
import 'health_garden_page.dart';
import '../state/wellness_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.chairSyncController,
    required this.wellnessController,
  });

  final ChairSyncController chairSyncController;
  final WellnessController wellnessController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int currentIndex = 0;
  bool _isLoggedIn = false;
  String? _userEmail;
  int _authRefreshVersion = 0;

  final List<Map<String, dynamic>> navItems = const [
    {'icon': Icons.event_seat, 'label': '健康總覽', 'hint': '坐姿監測'},
    {'icon': Icons.psychology_alt_rounded, 'label': 'AI 建議', 'hint': '治療師建議'},
    {'icon': Icons.local_florist_rounded, 'label': '健康花園', 'hint': '每日養成'},
    {'icon': Icons.notifications_active_rounded, 'label': '通知', 'hint': '提醒中心'},
  ];

  @override
  void initState() {
    super.initState();
    _refreshAuthState();
  }

  Future<void> _refreshAuthState() async {
    final refreshVersion = ++_authRefreshVersion;
    final wasLoggedIn = _isLoggedIn;
    final loggedIn = await ApiService.isLoggedIn();
    final email = await ApiService.getUserEmail();
    final chairId = loggedIn ? await ApiService.getSavedChairId() : null;
    if (mounted && refreshVersion == _authRefreshVersion) {
      setState(() {
        _isLoggedIn = loggedIn;
        _userEmail = email;
        if (!loggedIn) {
          currentIndex = 0;
        }
      });

      if (loggedIn && chairId != null && chairId.isNotEmpty) {
        widget.chairSyncController.startSession();
        widget.chairSyncController.startAutoSync();
      } else if (!loggedIn && wasLoggedIn) {
        widget.chairSyncController.stopSession();
        widget.chairSyncController.stopAutoSync();
      }
    }
    if (refreshVersion == _authRefreshVersion) {
      await widget.wellnessController.initialize(email);
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openAuth(AuthMode mode) async {
    final String? email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => AuthPage(initialMode: mode)),
    );

    if (email != null && mounted) {
      _showMsg(mode == AuthMode.login ? '登入成功' : '註冊成功');
      await _refreshAuthState();
      if (mounted) {
        setState(() => currentIndex = 0);
      }
    }
  }

  Future<void> _logout() async {
    // 在登出前嘗試 checkout（代表使用者離開椅子）
    try {
      await ApiService.chairCheckout();
    } catch (_) {
      // 忽略 checkout 錯誤，仍然繼續登出流程
    }

    await ApiService.logout();
    if (!mounted) return;
    widget.chairSyncController.stopSession();
    widget.chairSyncController.clearUserData();
    _showMsg('已登出');
    await _refreshAuthState();
  }

  Future<void> _accountDeleted() async {
    if (!mounted) return;
    widget.chairSyncController.stopSession();
    widget.chairSyncController.stopAutoSync();
    widget.chairSyncController.clearUserData();
    _showMsg('帳號已刪除');
    await _refreshAuthState();
  }

  Future<void> _logoutFromSettings() async {
    await _logout();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _accountDeletedFromSettings() async {
    await _accountDeleted();
    if (mounted) Navigator.of(context).pop();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('設定')),
          body: SettingPage(
            isLoggedIn: _isLoggedIn,
            userEmail: _userEmail,
            wellnessController: widget.wellnessController,
            onLogout: _logoutFromSettings,
            onAccountDeleted: _accountDeletedFromSettings,
            onProfileChanged: _refreshAuthState,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isLoggedIn) {
      return _AuthLandingPage(
        onLogin: () => _openAuth(AuthMode.login),
        onRegister: () => _openAuth(AuthMode.register),
      );
    }

    final pages = [
      DashboardPage(
        controller: widget.chairSyncController,
        isLoggedIn: _isLoggedIn,
        wellnessController: widget.wellnessController,
        onOpenAi: () => setState(() => currentIndex = 1),
        onOpenGarden: () => setState(() => currentIndex = 2),
        onOpenSettings: _openSettings,
      ),
      AiAdvicePage(
        controller: widget.chairSyncController,
        isLoggedIn: _isLoggedIn,
        wellnessController: widget.wellnessController,
      ),
      HealthGardenPage(
        controller: widget.wellnessController,
        postureCode: widget.chairSyncController.postureCode,
      ),
      NotificationPage(
        controller: widget.chairSyncController,
        wellnessController: widget.wellnessController,
      ),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE9F7FC), Color(0xFFF5F8FA)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _BrandBadge(
                        colorScheme: colorScheme,
                        showAndroidTag: false,
                        compact: true,
                      ),
                    ),
                    IconButton(
                      onPressed: _openSettings,
                      tooltip: '設定',
                      icon: const Icon(Icons.settings_rounded),
                    ),
                    IconButton(
                      onPressed: _logout,
                      tooltip: '登出',
                      icon: const Icon(Icons.logout_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(child: pages[currentIndex]),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => setState(() => currentIndex = index),
        backgroundColor: Colors.white,
        elevation: 8,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final item in navItems)
            NavigationDestination(
              icon: Icon(item['icon'] as IconData),
              selectedIcon: Icon(item['icon'] as IconData),
              label: item['label'] as String,
            ),
        ],
      ),
    );
  }
}

class _AuthLandingPage extends StatelessWidget {
  const _AuthLandingPage({required this.onLogin, required this.onRegister});

  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE6F7FB), Color(0xFFF7FAFC), Color(0xFFF1F8F6)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _BrandBadge(
                      colorScheme: colorScheme,
                      showAndroidTag: true,
                      compact: false,
                    ),
                    const SizedBox(height: 36),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onLogin,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                              side: BorderSide(color: colorScheme.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              '登入',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: onRegister,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              '註冊',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({
    required this.colorScheme,
    required this.showAndroidTag,
    required this.compact,
  });

  final ColorScheme colorScheme;
  final bool showAndroidTag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout = compact || constraints.maxWidth < 300;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compactLayout ? 32 : 40,
              height: compactLayout ? 32 : 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.event_seat_rounded,
                color: colorScheme.primary,
                size: compactLayout ? 20 : 26,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '智慧座椅',
              style: TextStyle(
                fontSize: compactLayout ? 28 : 40,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
                letterSpacing: compactLayout ? 0.5 : 1.2,
              ),
            ),
            if (showAndroidTag) ...[
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compactLayout ? 8 : 14,
                  vertical: compactLayout ? 5 : 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'Android',
                  style: TextStyle(
                    fontSize: compactLayout ? 14 : 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F766E),
                    letterSpacing: compactLayout ? 0.5 : 1.2,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
