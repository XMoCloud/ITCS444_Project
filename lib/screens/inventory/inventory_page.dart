import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/repository.dart';
import '../../ui/loading_animation.dart';
import 'equipment_card.dart';
import 'add_equipment_page.dart';

class InventoryPage extends StatefulWidget {
  final String role;
  final String? userId;

  const InventoryPage({super.key, required this.role, required this.userId});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String _search = '';
  String _availabilityFilter = 'all';
  String _typeFilter = 'all';
  bool _donatedOnly = false;
  bool _isGridView = false;

  void _openFilters() {
    String tempType = _typeFilter;
    String tempStatus = _availabilityFilter;
    bool tempDonated = _donatedOnly;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Filter equipment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: tempType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All types')),
                    DropdownMenuItem(
                      value: 'wheelchair',
                      child: Text('Wheelchair'),
                    ),
                    DropdownMenuItem(value: 'walker', child: Text('Walker')),
                    DropdownMenuItem(
                      value: 'crutches',
                      child: Text('Crutches'),
                    ),
                    DropdownMenuItem(value: 'bed', child: Text('Hospital bed')),
                    DropdownMenuItem(
                      value: 'oxygen_machine',
                      child: Text('Oxygen machine'),
                    ),
                    DropdownMenuItem(
                      value: 'mobility_scooter',
                      child: Text('Mobility scooter'),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => tempType = v ?? 'all'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: tempStatus,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(
                      value: 'available',
                      child: Text('Available'),
                    ),
                    DropdownMenuItem(value: 'rented', child: Text('Rented')),
                    DropdownMenuItem(
                      value: 'maintenance',
                      child: Text('Maintenance'),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => tempStatus = v ?? 'all'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Show donated only'),
                  value: tempDonated,
                  onChanged: (v) => setDialogState(() => tempDonated = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _typeFilter = tempType;
                    _availabilityFilter = tempStatus;
                    _donatedOnly = tempDonated;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role == 'admin';

    return Scaffold(
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF27374D), Color(0xFF526D82)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF27374D).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search equipment...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      fillColor: Colors.white.withOpacity(0.15),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: () => setState(() => _isGridView = !_isGridView),
                    icon: Icon(
                      _isGridView
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded,
                      color: Colors.white,
                    ),
                    tooltip: _isGridView ? 'List view' : 'Grid view',
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: _openFilters,
                    icon: const Icon(
                      Icons.filter_list_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Filter',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: CareCenterRepository.equipmentCol.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: LoadingAnimation());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text('No equipment found.'));
                }

                final now = DateTime.now();
                var docs = snap.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final type = (data['type'] ?? '').toString();
                  var status = (data['availabilityStatus'] ?? 'available')
                      .toString();
                  final isDonated = (data['isDonatedItem'] ?? false) as bool;
                  final maintTs = data['maintenanceUntil'];

                  // auto release maintenance if time passed
                  if (status == 'maintenance' &&
                      maintTs is Timestamp &&
                      now.isAfter(maintTs.toDate())) {
                    // Update equipment availability
                    CareCenterRepository.updateEquipment(d.id, {
                      'availabilityStatus': 'available',
                      'needsMaintenance': false,
                      'maintenanceUntil': null,
                    });
                    status = 'available';

                    // Close maintenance records and remove reservation entries related to maintenance
                    // Fire-and-forget operations (keep UI responsive)
                    (() async {
                      try {
                        final resSnap = await CareCenterRepository
                            .reservationsCol
                            .where('equipmentId', isEqualTo: d.id)
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
                            debugPrint(
                              'Failed to delete reservation ${r.id}: $e',
                            );
                          }
                        }

                        final maintSnap = await CareCenterRepository
                            .maintenanceCol
                            .where('equipmentId', isEqualTo: d.id)
                            .where('status', isEqualTo: 'open')
                            .get();
                        for (final m in maintSnap.docs) {
                          try {
                            await CareCenterRepository.maintenanceCol
                                .doc(m.id)
                                .update({
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
                        debugPrint('Error during maintenance auto-release: $e');
                      }
                    })();
                  }

                  if (_search.isNotEmpty && !name.contains(_search)) {
                    return false;
                  }
                  if (_typeFilter != 'all' && type != _typeFilter) {
                    return false;
                  }
                  if (_availabilityFilter != 'all' &&
                      status != _availabilityFilter) {
                    return false;
                  }
                  if (_donatedOnly && !isDonated) {
                    return false;
                  }
                  return true;
                }).toList();

                docs.sort((a, b) {
                  final da = (a.data() as Map<String, dynamic>)['createdAt'];
                  final db = (b.data() as Map<String, dynamic>)['createdAt'];
                  if (da == null || db == null) return 0;
                  return (db as Timestamp).compareTo(da as Timestamp);
                });

                if (_isGridView) {
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      return EquipmentCard(
                        docId: doc.id,
                        data: data,
                        role: widget.role,
                        userId: widget.userId,
                        isGrid: true,
                      );
                    },
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return EquipmentCard(
                      docId: doc.id,
                      data: data,
                      role: widget.role,
                      userId: widget.userId,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF27374D), Color(0xFF526D82)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF27374D).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddEquipmentPage(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Add equipment',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
