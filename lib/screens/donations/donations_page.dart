import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/repository.dart';
import '../../utils/string_utils.dart';
import '../../ui/custom_toast.dart';
import 'donation_form_page.dart';

class DonationsPage extends StatelessWidget {
  final String role;
  final String? userId;

  const DonationsPage({super.key, required this.role, required this.userId});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';

    // if (!isAdmin && userId == null) {
    //   return const Center(child: Text('Sign in to view your donations.'));
    // }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DonationFormPage(donorId: userId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.volunteer_activism_rounded),
                  label: const Text('Offer a donation'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: (!isAdmin && userId == null)
              ? const Center(
                  child: Text(
                    'Sign in to view your history.\nYou can still donate as a Guest.',
                    textAlign: TextAlign.center,
                  ),
                )
              : StreamBuilder<QuerySnapshot>(
                  stream: isAdmin
                      ? CareCenterRepository.donationsCol.snapshots()
                      : CareCenterRepository.donationsCol
                          .where('donorId', isEqualTo: userId)
                          .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const Center(
                  child: Text('No donations yet. Be the first!'),
                );
              }

              final docs = snap.data!.docs.toList();
              // Pending first, then createdAt desc
              docs.sort((a, b) {
                final da = a.data() as Map<String, dynamic>;
                final db = b.data() as Map<String, dynamic>;
                final sa = (da['status'] ?? 'pending').toString();
                final sb = (db['status'] ?? 'pending').toString();
                int rank(String s) => s == 'pending' ? 0 : 1;
                final r = rank(sa) - rank(sb);
                if (r != 0) return r;
                final ca = da['createdAt'];
                final cb = db['createdAt'];
                if (ca == null || cb == null) return 0;
                return (cb as Timestamp).compareTo(ca as Timestamp);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  return _DonationTile(
                    docId: doc.id,
                    data: data,
                    isAdmin: isAdmin,
                    adminId: userId,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DonationTile extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool isAdmin;
  final String? adminId;

  const _DonationTile({
    required this.docId,
    required this.data,
    required this.isAdmin,
    required this.adminId,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'added_to_inventory':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawName = (data['donorName'] ?? '').toString();
    final rawType = (data['itemType'] ?? 'Item').toString();
    final displayName = rawName.isNotEmpty
        ? rawName
        : formatEnumString(rawType);

    final status = (data['status'] ?? 'pending').toString();
    final donor = data['donorName'] ?? 'Donor';
    final color = _statusColor(status);
    final photos = (data['photos'] as List?)?.cast<String>() ?? [];
    final imageUrl = photos.isNotEmpty ? photos.first : null;

    final isPending = status == 'pending';
    final isClosed = status == 'added_to_inventory' || status == 'rejected';
    final cardColor = isClosed ? Colors.grey.shade200 : Colors.white;
    final opacity = isClosed ? 0.6 : 1.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: opacity,
      child: Card(
        color: cardColor,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[200],
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, err, stack) => const Icon(
                                Icons.card_giftcard_rounded,
                                size: 32,
                              ),
                            )
                          : const Icon(Icons.card_giftcard_rounded, size: 32),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.toString(),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text('Donor: $donor'),
                        const SizedBox(height: 2),
                        Text('${data['donorContact'] ?? ''}'),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      formatEnumString(status),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (photos.length > 1)
                SizedBox(
                  height: 56,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length > 5 ? 5 : photos.length,
                    itemBuilder: (context, index) {
                      final img = photos[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            img,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (isAdmin && isPending)
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade500,
                      ),
                      onPressed: () async {
                        final qty = (data['quantity'] ?? 1) as int;
                        final photos =
                            (data['photos'] as List?)?.cast<String>() ?? [];

                        final eqId = await CareCenterRepository.addEquipment(
                          name: displayName.toString(),
                          type: (data['itemType'] ?? 'other').toString(),
                          description: (data['description'] ?? 'Donated item')
                              .toString(),
                          condition: (data['condition'] ?? 'good').toString(),
                          quantityTotal: qty,
                          location: 'Main branch',
                          rentalPricePerDay: null,
                          images: photos,
                          isDonatedItem: true,
                          donorId: data['donorId'] as String?,
                          originalDonationId: docId,
                        );

                        await CareCenterRepository.updateDonationStatus(
                          donationId: docId,
                          status: 'added_to_inventory',
                          reviewerAdminId: adminId,
                          linkedEquipmentId: eqId,
                        );

                        await CareCenterRepository.addNotification(
                          userId: data['donorId'] ?? 'unknown',
                          type: 'donation_status',
                          title: 'Donation approved',
                          message:
                              'Your donation "$displayName" was added to inventory. Thank you!',
                          donationId: docId,
                          equipmentId: eqId,
                        );

                        if (!context.mounted) return;
                        ToastService.showSuccess(
                          context,
                          'Success',
                          'Donation approved and added',
                        );
                      },
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Accept & add'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                      ),
                      onPressed: () async {
                        await CareCenterRepository.updateDonationStatus(
                          donationId: docId,
                          status: 'rejected',
                          reviewerAdminId: adminId,
                        );
                        await CareCenterRepository.addNotification(
                          userId: data['donorId'] ?? 'unknown',
                          type: 'donation_status',
                          title: 'Donation rejected',
                          message:
                              'Your donation for "$displayName" was rejected.',
                          donationId: docId,
                        );

                        if (!context.mounted) return;
                        ToastService.showInfo(
                          context,
                          'Info',
                          'Donation rejected',
                        );
                      },
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Reject'),
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
