import 'package:flutter/material.dart';
import '../../services/notification_manager.dart';
import 'dashboard_page.dart';
import '../inventory/inventory_page.dart';
import '../reservations/admin_reservations_page.dart';
import '../reservations/user_rentals_page.dart';
import '../donations/donations_page.dart';
import '../profile/profile_page.dart';

class MainShell extends StatefulWidget {
  final String role;
  final String? userId;

  const MainShell({super.key, required this.role, required this.userId});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.userId != null) {
      // Initialize notification system
      NotificationManager.init(context, widget.userId!, widget.role);
    }
  }

  @override
  void dispose() {
    NotificationManager.dispose();
    super.dispose();
  }

  List<Widget> get _pages => [
    DashboardPage(role: widget.role, userId: widget.userId),
    InventoryPage(role: widget.role, userId: widget.userId),
    widget.role == 'admin'
        ? AdminReservationsPage(adminId: widget.userId ?? '')
        : UserRentalsPage(userId: widget.userId),
    DonationsPage(role: widget.role, userId: widget.userId),
    ProfilePage(role: widget.role, userId: widget.userId),
  ];

  String _title() {
    switch (_index) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Inventory';
      case 2:
        return widget.role == 'admin' ? 'Manage Reservations' : 'My Rentals';
      case 3:
        return 'Donations';
      case 4:
        return 'Profile';
      default:
        return 'Care Center';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.surface,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.health_and_safety_rounded, color: cs.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _title(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.05),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(key: ValueKey(_index), child: _pages[_index]),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF526D82).withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          indicatorColor: const Color(0xFF27374D).withOpacity(0.1),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'Inventory',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_repeat_outlined),
              selectedIcon: Icon(Icons.event_repeat_rounded),
              label: 'Rentals',
            ),
            NavigationDestination(
              icon: Icon(Icons.volunteer_activism_outlined),
              selectedIcon: Icon(Icons.volunteer_activism_rounded),
              label: 'Donations',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
