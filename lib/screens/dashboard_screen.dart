import 'package:flutter/material.dart';
import '../services/event_service.dart';
import '../services/storage_service.dart';
import 'dispatched_screen.dart';
import 'billed_archive_screen.dart';
import 'login_screen.dart';
import 'manage_parties_screen.dart';
import 'manage_monthcodes_screen.dart';
import 'advanced_search_screen.dart';
import 'reel_manager_screen.dart';
import 'edit_reel_screen.dart';
import 'map_screen.dart';
import 'scan_qr_screen.dart';
import 'search_reel_screen.dart';
import 'advanced_reel_search_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  bool _isAdmin = false;
  bool _isLoading = true;

  String _serverUrl = '';
  int _userId = 0;
  String _authKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EventService().disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _connectToEvents();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        EventService().disconnect();
        break;
    }
  }

  Future<void> _checkAuth() async {
    final session = await StorageService.getSession();
    if (session['authKey'] == null) {
      _logout();
      return;
    }

    _serverUrl = session['serverUrl']?.toString() ?? '';
    _userId = int.tryParse(session['userId']?.toString() ?? '0') ?? 0;
    _authKey = session['authKey']?.toString() ?? '';

    _connectToEvents();

    setState(() {
      _isAdmin = session['isAdmin'] == 'true';
      _isLoading = false;
    });
  }

  void _connectToEvents() {
    if (_serverUrl.isNotEmpty && _userId != 0 && _authKey.isNotEmpty) {
      EventService().connect(
        serverUrl: _serverUrl,
        userId: _userId,
        authKey: _authKey,
      );
    }
  }

  Future<void> _logout() async {
    EventService().disconnect();
    await StorageService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            // Standard Options
            _DashboardTile(
              icon: Icons.map,
              title: 'Map',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen())),
            ),
            _DashboardTile(
              icon: Icons.search,
              title: 'Search',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchReelScreen())),
            ),
            _DashboardTile(
              icon: Icons.qr_code_scanner,
              title: 'QR Code',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanQrScreen())),
            ),
            _DashboardTile(
              icon: Icons.local_shipping,
              title: 'Dispatched',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DispatchedScreen())),
            ),
            _DashboardTile(
              icon: Icons.archive,
              title: 'Billed Reels',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BilledArchiveScreen())),
            ),
            _DashboardTile(
              icon: Icons.playlist_add_check_circle_outlined,
              title: 'Reels dashboard',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReelManagerScreen())),
            ),
            _DashboardTile(
              icon: Icons.edit_note,
              title: 'Add Reel Entry',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditReelScreen())),
            ),
            _DashboardTile(
              icon: Icons.manage_search_rounded,
              title: 'Reel Search',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdvancedReelSearchScreen())),
            ),

            // Admin Options
            if (_isAdmin) ...[
              _DashboardTile(
                icon: Icons.pageview,
                title: 'Adv Search',
                isAdmin: true,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdvancedSearchScreen())),
              ),
              _DashboardTile(
                icon: Icons.group,
                title: 'Edit Parties',
                isAdmin: true,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagePartiesScreen())),
              ),
              _DashboardTile(
                icon: Icons.edit_calendar,
                title: 'Edit Monthcodes',
                isAdmin: true,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageMonthcodesScreen())),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isAdmin;

  const _DashboardTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      color: isAdmin ? colorScheme.errorContainer : colorScheme.primaryContainer,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: isAdmin ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isAdmin ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}