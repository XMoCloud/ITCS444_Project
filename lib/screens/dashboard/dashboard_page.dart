import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/repository.dart';
import '../../ui/custom_toast.dart';
import '../../widgets/stat_card.dart';

class DashboardPage extends StatefulWidget {
  final String role;
  final String? userId;

  const DashboardPage({super.key, required this.role, required this.userId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    if (widget.role == 'admin') {
      _checkOverdue();
    }
  }

  Future<void> _checkOverdue() async {
    // Simple check to notify admin about overdue items
    final now = DateTime.now();
    final snap = await CareCenterRepository.reservationsCol
        .where('status', isEqualTo: 'checked_out')
        .get();

    int overdueCount = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final end = (data['endDate'] as Timestamp).toDate();
      if (end.isBefore(now)) {
        overdueCount++;
      }
    }

    if (overdueCount > 0 && mounted) {
      ToastService.showWarning(
        context,
        'Attention',
        '$overdueCount rental(s) are overdue!',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isAdmin = widget.role == 'admin';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF27374D), Color(0xFF526D82)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF27374D).withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAdmin ? 'Welcome back, Admin 👋' : 'Welcome 👋',
                style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAdmin
                    ? 'Overview of inventory, rentals and donations.'
                    : 'Browse equipment and track your rentals.',
                style: tt.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (isAdmin) ...[
          _buildAdminStats(),
          const SizedBox(height: 24),
          _buildAnalytics(context),
          const SizedBox(height: 24),
          Text(
            'Attention Needed',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildOverdueList(),
        ] else ...[
          _buildUserStats(),
          const SizedBox(height: 24),
          Text(
            'My Active Rentals',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildUserActiveRentals(),
        ],
      ],
    );
  }

  Widget _buildAdminStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: CareCenterRepository.equipmentCol.snapshots(),
      builder: (context, eqSnap) {
        final eqDocs = eqSnap.data?.docs ?? [];
        final total = eqDocs.length;
        final available = eqDocs
            .where((d) => d['availabilityStatus'] == 'available')
            .length;
        final rented = eqDocs
            .where((d) => d['availabilityStatus'] == 'rented')
            .length;
        final maintenance = eqDocs
            .where((d) => d['availabilityStatus'] == 'maintenance')
            .length;

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: 'Total Equipment',
                    value: '$total',
                    icon: Icons.inventory_2_rounded,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    title: 'Available',
                    value: '$available',
                    icon: Icons.check_circle_rounded,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: 'Rented Out',
                    value: '$rented',
                    icon: Icons.shopping_bag_rounded,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    title: 'Maintenance',
                    value: '$maintenance',
                    icon: Icons.build_rounded,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: CareCenterRepository.donationsCol
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (ctx, donSnap) {
                final pendingDonations = donSnap.data?.docs.length ?? 0;
                if (pendingDonations == 0) return const SizedBox.shrink();
                return SizedBox(
                  width: double.infinity,
                  child: StatCard(
                    title: 'Pending Donations',
                    value: '$pendingDonations',
                    icon: Icons.volunteer_activism_rounded,
                    color: Colors.purple,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildInsights(eqDocs),
          ],
        );
      },
    );
  }

  Widget _buildAnalytics(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analytics & Reports',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildPopularEquipment(),
      ],
    );
  }

  Widget _buildPopularEquipment() {
    return StreamBuilder<QuerySnapshot>(
      stream: CareCenterRepository.equipmentCol
          .orderBy('rentalCount', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty)
          return const SizedBox.shrink();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF9DB2BF).withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF526D82).withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF27374D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.trending_up_rounded,
                        color: Color(0xFF27374D),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Most Frequently Rented',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF27374D),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...snap.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(data['name'] ?? 'Unknown'),
                        Text(
                          '${data['rentalCount'] ?? 0} rentals',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInsights(List<QueryDocumentSnapshot> allEquipment) {
    if (allEquipment.isEmpty) return const SizedBox.shrink();

    final total = allEquipment.length;
    final rented = allEquipment
        .where((d) => d['availabilityStatus'] == 'rented')
        .length;
    final maintenance = allEquipment
        .where((d) => d['availabilityStatus'] == 'maintenance')
        .length;

    final utilRate = (rented / total * 100).toStringAsFixed(1);
    final maintRate = (maintenance / total * 100).toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF9DB2BF).withOpacity(0.3), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9DB2BF).withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF27374D).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.lightbulb_rounded,
                    color: Color(0xFF27374D),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Service Insights',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF27374D),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• Utilization Rate: $utilRate% of inventory is currently rented.',
            ),
            Text(
              '• Maintenance Health: $maintRate% of items are under repair.',
            ),
            if (rented > total * 0.7)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text(
                  '• High Demand: Consider acquiring more equipment.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverdueList() {
    return StreamBuilder<QuerySnapshot>(
      stream: CareCenterRepository.reservationsCol
          .where('status', isEqualTo: 'checked_out')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        final docs = snap.data!.docs.where((d) {
          final end = (d['endDate'] as Timestamp).toDate();
          return end.isBefore(now);
        }).toList();

        if (docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: const [
                  Icon(Icons.check_circle_outline, color: Colors.green),
                  SizedBox(width: 12),
                  Text('No overdue rentals. Great job!'),
                ],
              ),
            ),
          );
        }

        return Column(
          children: docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            final end = (data['endDate'] as Timestamp).toDate();
            final days = now.difference(end).inDays;
            return Card(
              color: Colors.red.shade50,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.warning_rounded, color: Colors.red),
                title: Text(data['equipmentName'] ?? 'Equipment'),
                subtitle: Text(
                  'Renter: ${data['renterName']}\nOverdue by $days days',
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildUserStats() {
    if (widget.userId == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: CareCenterRepository.reservationsCol
          .where('renterId', isEqualTo: widget.userId)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final active = docs.where((d) => d['status'] == 'checked_out').length;
        final pending = docs.where((d) => d['status'] == 'pending').length;

        return Row(
          children: [
            Expanded(
              child: StatCard(
                title: 'Active Rentals',
                value: '$active',
                icon: Icons.shopping_bag_rounded,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: 'Pending Requests',
                value: '$pending',
                icon: Icons.hourglass_empty_rounded,
                color: Colors.orange,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUserActiveRentals() {
    if (widget.userId == null) return const Text('Sign in to see your rentals');
    return StreamBuilder<QuerySnapshot>(
      stream: CareCenterRepository.reservationsCol
          .where('renterId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'checked_out')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF9DB2BF).withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.event_busy_rounded,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  'No active rentals',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your active rentals will appear here',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ],
            ),
          );
        }
        return Column(
          children: snap.data!.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            final end = (data['endDate'] as Timestamp).toDate();
            final now = DateTime.now();
            final isOverdue = end.isBefore(now);
            final daysLeft = end.difference(now).inDays;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isOverdue
                      ? [Colors.red.shade50, Colors.white]
                      : [
                          const Color(0xFF9DB2BF).withOpacity(0.1),
                          Colors.white,
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isOverdue
                      ? Colors.red.withOpacity(0.3)
                      : const Color(0xFF9DB2BF).withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isOverdue ? Colors.red : const Color(0xFF526D82))
                        .withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isOverdue ? Colors.red : const Color(0xFF27374D))
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isOverdue ? Icons.warning_rounded : Icons.timer_rounded,
                    color: isOverdue ? Colors.red : const Color(0xFF27374D),
                    size: 24,
                  ),
                ),
                title: Text(
                  data['equipmentName'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    isOverdue
                        ? 'Overdue by ${now.difference(end).inDays} days'
                        : '$daysLeft days remaining',
                    style: TextStyle(
                      color: isOverdue ? Colors.red : const Color(0xFF526D82),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
