import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/repository.dart';
import '../../utils/string_utils.dart';
import '../../ui/custom_toast.dart';

class AdminReservationsPage extends StatefulWidget {
  final String adminId;
  const AdminReservationsPage({super.key, required this.adminId});

  @override
  State<AdminReservationsPage> createState() => _AdminReservationsPageState();
}

class _AdminReservationsPageState extends State<AdminReservationsPage> {
  bool _showHistory = false;

  Future<DateTime?> _pickMaintenanceUntil(BuildContext context) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null) return null;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (pickedTime == null) return null;
    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    String reservationId,
    String status, {
    String? equipmentId,
    String? renterId,
    DateTime? maintenanceUntil,
  }) async {
    // If checking out, mark equipment as rented
    if (status == 'checked_out' && equipmentId != null) {
      await CareCenterRepository.updateEquipment(equipmentId, {
        'availabilityStatus': 'rented',
      });
    }
    // If returned, mark equipment as available
    if (status == 'returned' && equipmentId != null) {
      await CareCenterRepository.updateEquipment(equipmentId, {
        'availabilityStatus': 'available',
        'needsMaintenance': false,
        'maintenanceUntil': null,
      });
    }
    // If maintenance, mark equipment as maintenance
    if (status == 'maintenance' && equipmentId != null) {
      await CareCenterRepository.updateEquipment(equipmentId, {
        'availabilityStatus': 'maintenance',
        'needsMaintenance': true,
        'maintenanceUntil': maintenanceUntil != null
            ? Timestamp.fromDate(maintenanceUntil)
            : null,
      });
      // Also create maintenance record
      await CareCenterRepository.maintenanceCol.add({
        'equipmentId': equipmentId,
        'reportedBy': widget.adminId,
        'description': 'Routine maintenance from admin panel',
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await CareCenterRepository.updateReservationStatus(
      reservationId: reservationId,
      status: status,
      adminId: widget.adminId,
      closedAt: status == 'returned' || status == 'declined'
          ? DateTime.now()
          : null,
    );

    if (equipmentId != null) {
      if (status == 'checked_out') {
        await CareCenterRepository.updateEquipment(equipmentId, {
          'rentalCount': FieldValue.increment(1),
        });
      }
      // Note: availabilityStatus updates are handled above
    }
    if (renterId != null) {
      await CareCenterRepository.addNotification(
        userId: renterId,
        type: 'reservation_status',
        title: 'Reservation $status',
        message: 'Your reservation is now $status',
        reservationId: reservationId,
        equipmentId: equipmentId,
      );
    }
    if (!context.mounted) return;
    ToastService.showSuccess(context, 'Success', 'Reservation set to $status');
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.blue;
      case 'checked_out':
        return Colors.purple;
      case 'returned':
        return Colors.green;
      case 'maintenance':
        return Colors.red;
      case 'declined':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: CareCenterRepository.reservationsCol.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs.toList() ?? [];
        // Pending on top, then by createdAt desc
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

        final activeStatuses = {
          'pending',
          'approved',
          'checked_out',
          'maintenance',
          'return_requested',
        };
        final historyStatuses = {'returned', 'declined'};
        final filteredDocs = docs.where((d) {
          final status =
              ((d.data() as Map<String, dynamic>)['status'] ?? 'pending')
                  .toString();
          return _showHistory
              ? historyStatuses.contains(status)
              : activeStatuses.contains(status);
        }).toList();

        // Identify which equipment is currently physically rented out
        final rentedEquipmentIds = <String>{};
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final st = (data['status'] ?? '').toString();
          if (st == 'checked_out' || st == 'return_requested') {
            final eqId = data['equipmentId'] as String?;
            if (eqId != null) rentedEquipmentIds.add(eqId);
          }
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Active'),
                    selected: !_showHistory,
                    onSelected: (v) {
                      if (!v) return;
                      setState(() => _showHistory = false);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('History'),
                    selected: _showHistory,
                    onSelected: (v) {
                      if (!v) return;
                      setState(() => _showHistory = true);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredDocs.isEmpty
                  ? Center(
                      child: Text(
                        _showHistory
                            ? 'No historical reservations yet.'
                            : 'No active reservations yet.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, i) {
                        final doc = filteredDocs[i];
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data['equipmentName'] ?? 'Equipment';
                        final renter = data['renterName'] ?? 'Renter';
                        final status = (data['status'] ?? 'pending').toString();
                        final start = (data['startDate'] as Timestamp).toDate();
                        final end = (data['endDate'] as Timestamp).toDate();
                        final range =
                            '${start.toLocal().toString().split(' ').first} → ${end.toLocal().toString().split(' ').first}';

                        final isPending = status == 'pending';
                        final isClosed =
                            status == 'declined' ||
                            status == 'returned' ||
                            status == 'maintenance';
                        final cardColor = isClosed
                            ? Colors.grey.shade200
                            : Colors.white;
                        final opacity = isClosed ? 0.6 : 1.0;
                        final color = _statusColor(status);

                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: opacity,
                          child: Card(
                            color: cardColor,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.event_repeat_rounded),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name.toString(),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text('Renter: $renter'),
                                            Text(range),
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
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
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
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      if (isPending && !_showHistory) ...[
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                Colors.green.shade500,
                                          ),
                                          onPressed: () => _changeStatus(
                                            context,
                                            doc.id,
                                            'approved',
                                            equipmentId:
                                                data['equipmentId'] as String?,
                                            renterId:
                                                data['renterId'] as String?,
                                          ),
                                          icon: const Icon(
                                            Icons.check_circle_rounded,
                                          ),
                                          label: const Text('Accept'),
                                        ),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                Colors.red.shade400,
                                          ),
                                          onPressed: () => _changeStatus(
                                            context,
                                            doc.id,
                                            'declined',
                                            equipmentId:
                                                data['equipmentId'] as String?,
                                            renterId:
                                                data['renterId'] as String?,
                                          ),
                                          icon: const Icon(Icons.close_rounded),
                                          label: const Text('Reject'),
                                        ),
                                      ] else if (status == 'approved' &&
                                          !_showHistory) ...[
                                        Builder(
                                          builder: (context) {
                                            final eqId =
                                                data['equipmentId'] as String?;
                                            final isBlocked =
                                                eqId != null &&
                                                rentedEquipmentIds.contains(
                                                  eqId,
                                                );
                                            return FilledButton.icon(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: isBlocked
                                                    ? Colors.grey
                                                    : Colors.purple.shade500,
                                              ),
                                              onPressed: isBlocked
                                                  ? null
                                                  : () => _changeStatus(
                                                      context,
                                                      doc.id,
                                                      'checked_out',
                                                      equipmentId: eqId,
                                                      renterId:
                                                          data['renterId']
                                                              as String?,
                                                    ),
                                              icon: const Icon(
                                                Icons.outbond_rounded,
                                              ),
                                              label: const Text('Check Out'),
                                            );
                                          },
                                        ),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                Colors.red.shade400,
                                          ),
                                          onPressed: () => _changeStatus(
                                            context,
                                            doc.id,
                                            'declined',
                                            equipmentId:
                                                data['equipmentId'] as String?,
                                            renterId:
                                                data['renterId'] as String?,
                                          ),
                                          icon: const Icon(
                                            Icons.cancel_rounded,
                                          ),
                                          label: const Text('Cancel'),
                                        ),
                                      ] else if ((status == 'checked_out' ||
                                              status == 'return_requested') &&
                                          !_showHistory) ...[
                                        if (status == 'return_requested')
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8.0,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.info_outline_rounded,
                                                  size: 16,
                                                  color:
                                                      data['userReportedMaintenance'] ==
                                                          true
                                                      ? Colors.orange
                                                      : Colors.green,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'User marked as returned${data['userReportedMaintenance'] == true ? ' (Needs Maintenance)' : ''}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        data['userReportedMaintenance'] ==
                                                            true
                                                        ? Colors.orange
                                                        : Colors.green,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8.0,
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.info_outline_rounded,
                                                  size: 16,
                                                  color: Colors.red,
                                                ),
                                                const SizedBox(width: 4),
                                                const Text(
                                                  'Not returned yet',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                (status == 'checked_out' ||
                                                    data['userReportedMaintenance'] ==
                                                        true)
                                                ? Colors.grey
                                                : Colors.green.shade500,
                                          ),
                                          onPressed:
                                              (status == 'checked_out' ||
                                                  data['userReportedMaintenance'] ==
                                                      true)
                                              ? null
                                              : () => _changeStatus(
                                                  context,
                                                  doc.id,
                                                  'returned',
                                                  equipmentId:
                                                      data['equipmentId']
                                                          as String?,
                                                  renterId:
                                                      data['renterId']
                                                          as String?,
                                                ),
                                          icon: const Icon(
                                            Icons.check_circle_outline_rounded,
                                          ),
                                          label: const Text('Mark returned'),
                                        ),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                status == 'checked_out'
                                                ? Colors.grey
                                                : Colors.orange.shade600,
                                          ),
                                          onPressed: status == 'checked_out'
                                              ? null
                                              : () async {
                                                  final until =
                                                      await _pickMaintenanceUntil(
                                                        context,
                                                      );
                                                  if (until == null) return;
                                                  if (!context.mounted) return;
                                                  await _changeStatus(
                                                    context,
                                                    doc.id,
                                                    'maintenance',
                                                    equipmentId:
                                                        data['equipmentId']
                                                            as String?,
                                                    renterId:
                                                        data['renterId']
                                                            as String?,
                                                    maintenanceUntil: until,
                                                  );
                                                },
                                          icon: const Icon(
                                            Icons.build_circle_rounded,
                                          ),
                                          label: const Text(
                                            'Send to maintenance',
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
