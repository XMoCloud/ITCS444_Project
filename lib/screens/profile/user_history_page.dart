import 'package:flutter/material.dart';
import '../reservations/user_rentals_page.dart';
import '../donations/donations_page.dart';

class UserHistoryPage extends StatelessWidget {
  final String userId;
  final String role;
  const UserHistoryPage({super.key, required this.userId, required this.role});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your history'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Rentals'),
              Tab(text: 'Donations'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            UserRentalsPage(userId: userId, initialShowHistory: true),
            DonationsPage(role: role, userId: userId),
          ],
        ),
      ),
    );
  }
}
