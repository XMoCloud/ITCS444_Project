import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/repository.dart';
import '../auth/login_page.dart';
import 'user_history_page.dart';

class ProfilePage extends StatelessWidget {
  final String role;
  final String? userId;

  const ProfilePage({super.key, required this.role, required this.userId});

  Future<void> _signOut(BuildContext context) async {
    await AuthService.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    if (userId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('You are browsing as guest.'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: CareCenterRepository.usersCol.doc(userId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final name = data['name'] ?? 'User';
        final email = data['email'] ?? '';
        final phone = data['phone'] ?? '';
        final id = data['nationalId'] ?? '';
        final preferred = data['preferredContact'] ?? '';
        final roleStr = data['role'] ?? role;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      child: Icon(Icons.person_rounded, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.toString(),
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Role: $roleStr',
                            style: tt.bodyMedium?.copyWith(
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email.toString(),
                            style: tt.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_rounded),
                    title: const Text('Personal information'),
                    subtitle: Text('ID: $id\nPhone: $phone'),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_rounded),
                    title: const Text('Preferred contact'),
                    subtitle: Text(preferred.toString()),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: const Text('Rental & donation history'),
                    subtitle: const Text('View your full history'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserHistoryPage(userId: userId!, role: roleStr),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Sign out'),
                onTap: () => _signOut(context),
              ),
            ),
          ],
        );
      },
    );
  }
}
