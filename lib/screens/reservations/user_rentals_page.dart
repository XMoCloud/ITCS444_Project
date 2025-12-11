import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/repository.dart';
import '../../utils/string_utils.dart';
import '../../ui/custom_toast.dart';

class UserRentalsPage extends StatefulWidget {
  final String? userId;
  final bool initialShowHistory;
  const UserRentalsPage({
    super.key,
    required this.userId,
    this.initialShowHistory = false,
  });

  @override
  State<UserRentalsPage> createState() => _UserRentalsPageState();
}

class _UserRentalsPageState extends State<UserRentalsPage> {
  late bool _showHistory;

  @override
  void initState() {
    super.initState();
    _showHistory = widget.initialShowHistory;
  }

  Future<void> _showReturnDialog(String reservationId) async {
    bool needsMaintenance = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Return Equipment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Are you sure you want to return this item?'),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Report Maintenance Issue'),
                subtitle: const Text(
                  'Check this if the item is damaged or not working',
                ),
                value: needsMaintenance,
                onChanged: (val) =>
                    setState(() => needsMaintenance = val ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await CareCenterRepository.reservationsCol
                    .doc(reservationId)
                    .update({
                      'status': 'return_requested',
                      'userReportedMaintenance': needsMaintenance,
                    });

                // Notify admins
                await CareCenterRepository.notifyAdmins(
                  type: needsMaintenance ? 'maintenance' : 'return_requested',
                  title: needsMaintenance
                      ? 'Maintenance Reported'
                      : 'Equipment Returned',
                  message: needsMaintenance
                      ? 'A user reported maintenance issue for a returned item.'
                      : 'A user has returned an equipment.',
                  reservationId: reservationId,
                );

                if (mounted) {
                  ToastService.showSuccess(
                    context,
                    'Success',
                    'Return requested successfully',
                  );
                }
              },
              child: const Text('Confirm Return'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateReturnDate(
    String reservationId,
    DateTime start,
    DateTime currentEnd,
  ) async {
    // Normalize start date to midnight to ensure valid range
    final firstDate = DateTime(start.year, start.month, start.day);
    final lastDate = DateTime(
      currentEnd.year,
      currentEnd.month,
      currentEnd.day,
    );

    final picked = await showDatePicker(
      context: context,
      initialDate: lastDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select New Return Date',
    );

    if (picked != null && mounted) {
      // Set time to end of day (23:59:59) or preserve original time?
      // Usually end date is inclusive, so let's keep it simple.
      // We'll just update the date part and keep time or set to end of day.
      // The original logic seems to use full timestamps.
      // Let's set it to the same time as the original end date, but on the new day.
      final newEnd = DateTime(
        picked.year,
        picked.month,
        picked.day,
        currentEnd.hour,
        currentEnd.minute,
        currentEnd.second,
      );

      await CareCenterRepository.reservationsCol.doc(reservationId).update({
        'endDate': Timestamp.fromDate(newEnd),
      });

      ToastService.showSuccess(
        context,
        'Success',
        'Return date updated successfully',
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.blue;
      case 'checked_out':
        return Colors.purple;
      case 'return_requested':
        return Colors.orange;
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
    if (widget.userId == null) {
      return const Center(child: Text('Sign in to view your rentals.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: CareCenterRepository.reservationsCol
          .where('renterId', isEqualTo: widget.userId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs.toList() ?? [];
        docs.sort((a, b) {
          final da = (a.data() as Map<String, dynamic>)['createdAt'];
          final db = (b.data() as Map<String, dynamic>)['createdAt'];
          if (da == null || db == null) return 0;
          return (db as Timestamp).compareTo(da as Timestamp);
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
                            ? 'No historical rentals yet.'
                            : 'No active rentals yet.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, i) {
                        final data =
                            filteredDocs[i].data() as Map<String, dynamic>;
                        final name = data['equipmentName'] ?? 'Equipment';
                        final status = (data['status'] ?? 'pending').toString();
                        final color = _statusColor(status);
                        final start = (data['startDate'] as Timestamp).toDate();
                        final end = (data['endDate'] as Timestamp).toDate();
                        final range =
                            '${start.toLocal().toString().split(' ').first} → ${end.toLocal().toString().split(' ').first}';

                        final isHistoryItem = historyStatuses.contains(status);
                        final cardColor = isHistoryItem
                            ? Colors.grey.shade200
                            : Colors.white;
                        final opacity = isHistoryItem ? 0.6 : 1.0;

                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: opacity,
                          child: Card(
                            color: cardColor,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const Icon(Icons.event_repeat_rounded),
                              title: Text(name.toString()),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(range),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
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
                                      const SizedBox(width: 8),
                                      Text(
                                        'Step: ${CareCenterRepository.statusToStepPublic(status)}/5',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: status == 'checked_out'
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit_calendar_rounded,
                                          ),
                                          tooltip: 'Update Return Date',
                                          onPressed: () {
                                            final start =
                                                (data['startDate'] as Timestamp)
                                                    .toDate();
                                            final end =
                                                (data['endDate'] as Timestamp)
                                                    .toDate();
                                            _updateReturnDate(
                                              filteredDocs[i].id,
                                              start,
                                              end,
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton(
                                          onPressed: () => _showReturnDialog(
                                            filteredDocs[i].id,
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                          ),
                                          child: const Text('Return'),
                                        ),
                                      ],
                                    )
                                  : null,
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
