import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/repository.dart';
import '../../utils/string_utils.dart';
import '../../ui/custom_toast.dart';
import 'edit_equipment_page.dart';
import '../reservations/reservation_form_page.dart';

class EquipmentCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final String role;
  final String? userId;
  final bool isGrid;

  const EquipmentCard({
    super.key,
    required this.docId,
    required this.data,
    required this.role,
    required this.userId,
    this.isGrid = false,
  });

  IconData _typeIcon(String type) {
    switch (type) {
      case 'wheelchair':
        return Icons.wheelchair_pickup_rounded;
      case 'walker':
        return Icons.elderly_rounded;
      case 'crutches':
        return Icons.accessibility_new_rounded;
      case 'bed':
        return Icons.bed_rounded;
      case 'oxygen_machine':
        return Icons.air_rounded;
      case 'mobility_scooter':
        return Icons.electric_scooter_rounded;
      default:
        return Icons.medical_services_rounded;
    }
  }

  Color _statusColor(String status, BuildContext ctx) {
    final s = status.toLowerCase();
    if (s == 'available') return Colors.green;
    if (s == 'rented') return Colors.orange;
    if (s == 'donated') return Colors.blueGrey;
    if (s == 'maintenance') return Colors.red;
    return Theme.of(ctx).colorScheme.primary;
  }

  Widget _buildImage(String? url, {double? width, double? height, BoxFit? fit}) {
    final type = data['type'] ?? 'type';
    if (url == null || url.isEmpty) {
      return Icon(
        _typeIcon(type.toString()),
        size: 40,
        color: Colors.grey,
      );
    }
    if (url.startsWith('http')) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Icon(
          _typeIcon(type.toString()),
          size: 40,
          color: Colors.grey,
        ),
      );
    }
    // Assume asset
    final assetPath = url.startsWith('assets/') ? url : 'assets/images/$url';
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Icon(
        _typeIcon(type.toString()),
        size: 40,
        color: Colors.grey,
      ),
    );
  }

  @override
  State<EquipmentCard> createState() => _EquipmentCardState();
}

class _EquipmentCardState extends State<EquipmentCard> {
  Timer? _timer;
  String _timeRemaining = '';
  bool _autoReleased = false;
  bool _isDescriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _computeRemaining();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _computeRemaining());
    });
  }

  void _computeRemaining() {
    final data = widget.data;
    final status = (data['availabilityStatus'] ?? 'available').toString();
    if (status == 'maintenance') {
      final maintTs = data['maintenanceUntil'];
      if (maintTs is Timestamp) {
        final remaining = maintTs.toDate().difference(DateTime.now());
        if (remaining.isNegative) {
          _timeRemaining = 'Done';
          if (!_autoReleased) {
            _autoReleased = true;
            // auto-release on maintenance end
            (() async {
              try {
                await CareCenterRepository.updateEquipment(widget.docId, {
                  'availabilityStatus': 'available',
                  'needsMaintenance': false,
                  'maintenanceUntil': null,
                });
                // delete any reservations with status maintenance
                final resSnap = await CareCenterRepository.reservationsCol
                    .where('equipmentId', isEqualTo: widget.docId)
                    .where('status', isEqualTo: 'maintenance')
                    .get();
                for (final r in resSnap.docs) {
                  try {
                    await CareCenterRepository.updateReservationStatus(
                      reservationId: r.id,
                      status: 'returned',
                      closedAt: DateTime.now(),
                    );
                  } catch (e) {
                    debugPrint('Failed to delete reservation ${r.id}: $e');
                  }
                }
                final maintSnap = await CareCenterRepository.maintenanceCol
                    .where('equipmentId', isEqualTo: widget.docId)
                    .where('status', isEqualTo: 'open')
                    .get();
                for (final m in maintSnap.docs) {
                  try {
                    await CareCenterRepository.maintenanceCol.doc(m.id).update({
                      'status': 'closed',
                      'closedAt': FieldValue.serverTimestamp(),
                    });
                  } catch (e) {
                    debugPrint(
                      'Failed to close maintenance record ${m.id}: $e',
                    );
                  }
                }
              } catch (e) {
                debugPrint('Error during per-card maintenance release: $e');
              }
            })();
          }
        } else {
          final d = remaining.inDays;
          final h = remaining.inHours % 24;
          final m = remaining.inMinutes % 60;
          final s = remaining.inSeconds % 60;
          if (d > 0) {
            _timeRemaining = '$d day${d > 1 ? 's' : ''} left';
          } else {
            _timeRemaining =
                '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
          }
        }
      } else {
        _timeRemaining = '';
      }
    } else {
      _timeRemaining = '';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docId = widget.docId;
    final data = widget.data;
    final role = widget.role;
    final userId = widget.userId;
    final name = data['name'] ?? 'Equipment';
    final type = data['type'] ?? 'type';
    final status = (data['availabilityStatus'] ?? 'available').toString();
    final images = (data['images'] as List?)?.cast<String>() ?? [];
    final imageUrl = images.isNotEmpty ? images.first : null;
    final statusColor = widget._statusColor(status, context);
    final isAdmin = role == 'admin';
    final isDonated = (data['isDonatedItem'] ?? false) as bool;
    final donorId = (data['donorId'] ?? '').toString();
    final description = (data['description'] ?? '').toString();

    if (widget.isGrid) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF9DB2BF).withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF526D82).withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                  color: Colors.grey[100],
                  child: widget._buildImage(
                    imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatEnumString(type.toString())} • ${data['condition'] ?? 'n/a'}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withOpacity(0.15),
                          statusColor.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      formatEnumString(status),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: isAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EditEquipmentPage(
                                          equipmentId: docId,
                                          initialData: data,
                                        ),
                                      ),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    side:
                                        BorderSide(color: Colors.blue.shade300),
                                  ),
                                  child: const Icon(Icons.edit, size: 16),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await CareCenterRepository.deleteEquipment(
                                        docId);
                                    if (!mounted) return;
                                    ToastService.showSuccess(
                                      context,
                                      'Success',
                                      'Equipment deleted',
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    side:
                                        BorderSide(color: Colors.red.shade300),
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Icon(Icons.delete, size: 16),
                                ),
                              ),
                            ],
                          )
                        : FilledButton(
                            onPressed: () {
                              if (userId == null) {
                                ToastService.showInfo(
                                  context,
                                  'Info',
                                  'Sign in',
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReservationFormPage(
                                    equipmentId: docId,
                                    equipmentName: name.toString(),
                                    equipmentType: type.toString(),
                                    renterId: userId,
                                  ),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text('Reserve',
                                style: TextStyle(fontSize: 12)),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9DB2BF).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF526D82).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF9DB2BF).withOpacity(0.2),
                        const Color(0xFF9DB2BF).withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: const Color(0xFF9DB2BF).withOpacity(0.3),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 90,
                      height: 90,
                      color: Colors.transparent,
                      child: widget._buildImage(
                        imageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
                                  name.toString(),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Type: ${formatEnumString(type.toString())} • Condition: ${data['condition'] ?? 'n/a'}',
                                ),
                                if ((data['location'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Text('Location: ${data['location']}'),
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _isDescriptionExpanded =
                                            !_isDescriptionExpanded;
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        Text(
                                          'Description',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blueGrey,
                                              ),
                                        ),
                                        Icon(
                                          _isDescriptionExpanded
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons.keyboard_arrow_down_rounded,
                                          color: Colors.blueGrey,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_isDescriptionExpanded)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2.0),
                                      child: Text(
                                        description,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  statusColor.withOpacity(0.15),
                                  statusColor.withOpacity(0.05),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: statusColor.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              formatEnumString(status),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            avatar: const Icon(
                              Icons.inventory_2_outlined,
                              size: 18,
                            ),
                            label: Text(
                              'Qty: ${data['quantityAvailable'] ?? data['quantityTotal'] ?? '-'}',
                            ),
                          ),
                          if (data['rentalPricePerDay'] != null)
                            Chip(
                              avatar: const Icon(
                                Icons.attach_money_rounded,
                                size: 18,
                              ),
                              label: Text(
                                'Price/day: ${data['rentalPricePerDay']}',
                              ),
                            ),
                          if (status == 'maintenance' &&
                              _timeRemaining.isNotEmpty)
                            Chip(
                              avatar: const Icon(Icons.build_rounded, size: 18),
                              label: Text('Maintenance: $_timeRemaining'),
                              backgroundColor: Colors.red.shade50,
                            ),
                        ],
                      ),
                      if ((data['tags'] as List?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children:
                              ((data['tags'] as List?)?.cast<String>() ?? [])
                                  .map((t) => Chip(label: Text(t)))
                                  .toList(),
                        ),
                      ],
                      const SizedBox(height: 6),
                      StreamBuilder<QuerySnapshot>(
                        stream: CareCenterRepository.reservationsCol
                            .where('equipmentId', isEqualTo: docId)
                            .snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const SizedBox.shrink();
                          final now = DateTime.now();
                          final docs = snap.data!.docs.where((d) {
                            final rd = d.data() as Map<String, dynamic>;
                            final st = (rd['status'] ?? '').toString();
                            if (st != 'approved' && st != 'checked_out') {
                              return false;
                            }
                            final end = (rd['endDate'] as Timestamp).toDate();
                            return end.isAfter(now);
                          }).toList();
                          if (docs.isEmpty) {
                            return Text(
                              'Not rented currently',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey[600]),
                            );
                          }
                          docs.sort((a, b) {
                            final ea =
                                (a.data() as Map<String, dynamic>)['endDate']
                                    as Timestamp;
                            final eb =
                                (b.data() as Map<String, dynamic>)['endDate']
                                    as Timestamp;
                            return ea.toDate().compareTo(eb.toDate());
                          });

                          // Find the first 'checked_out' reservation to show remaining time
                          final checkedOutDocs = docs.where(
                            (d) =>
                                (d.data() as Map<String, dynamic>)['status'] ==
                                'checked_out',
                          );
                          final activeRental = checkedOutDocs.isNotEmpty
                              ? checkedOutDocs.first
                              : docs.first;

                          final rd =
                              activeRental.data() as Map<String, dynamic>;
                          final st = (rd['status'] ?? '').toString();

                          if (st == 'approved') {
                            return Text(
                              'Reserved (Not picked up)',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.blue[700]),
                            );
                          }

                          final soonEnd = (rd['endDate'] as Timestamp);
                          final days = soonEnd.toDate().difference(now).inDays;
                          final text = days >= 0
                              ? 'Remaining: $days day(s)'
                              : 'Overdue';
                          return Text(
                            text,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[700]),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      if (isDonated)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.volunteer_activism_rounded,
                                  size: 18,
                                  color: Colors.purple,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Donated item',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            if (donorId.isNotEmpty)
                              FutureBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                future: CareCenterRepository.usersCol
                                    .doc(donorId)
                                    .get(),
                                builder: (context, snap) {
                                  if (!snap.hasData) {
                                    return const SizedBox.shrink();
                                  }
                                  final user = snap.data!.data() ?? {};
                                  final dn = user['name'] ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      'Donated by: $dn',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      if (images.length > 1) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 56,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: images.length > 5 ? 5 : images.length,
                            itemBuilder: (context, index) {
                              final img = images[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: widget._buildImage(
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
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            if (isAdmin)
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditEquipmentPage(
                              equipmentId: docId,
                              initialData: data,
                            ),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue.shade500,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_rounded),
                          SizedBox(width: 4),
                          Text('Edit'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await CareCenterRepository.deleteEquipment(docId);
                        if (!mounted) return;
                        ToastService.showSuccess(
                          context,
                          'Success',
                          'Equipment deleted',
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded),
                          SizedBox(width: 4),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: !isAdmin
                      ? () {
                          if (userId == null) {
                            ToastService.showInfo(
                              context,
                              'Info',
                              'Sign in to reserve equipment.',
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReservationFormPage(
                                equipmentId: docId,
                                equipmentName: name.toString(),
                                equipmentType: type.toString(),
                                renterId: userId,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available_rounded),
                      SizedBox(width: 4),
                      Text('Reserve'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
