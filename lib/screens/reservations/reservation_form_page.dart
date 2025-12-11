import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/repository.dart';
import '../../ui/custom_toast.dart';

class ReservationFormPage extends StatefulWidget {
  final String equipmentId;
  final String equipmentName;
  final String equipmentType;
  final String renterId;

  const ReservationFormPage({
    super.key,
    required this.equipmentId,
    required this.equipmentName,
    required this.equipmentType,
    required this.renterId,
  });
  @override
  State<ReservationFormPage> createState() => _ReservationFormPageState();
}

class _ReservationFormPageState extends State<ReservationFormPage> {
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 7));
  bool _immediate = true;
  int _duration = 7;
  bool _loading = false;
  List<DateTimeRange> _blockedRanges = [];

  @override
  void initState() {
    super.initState();
    if (widget.equipmentType == 'wheelchair') {
      _duration = 14;
    }
    _end = _start.add(Duration(days: _duration));
    _fetchBlockedDates();
  }

  Future<void> _fetchBlockedDates() async {
    final now = DateTime.now();
    final ranges = <DateTimeRange>[];

    // 1. Fetch reservations
    final snap = await CareCenterRepository.reservationsCol
        .where('equipmentId', isEqualTo: widget.equipmentId)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString();
      // Block dates for approved, checked_out, or return_requested
      if (status == 'approved' ||
          status == 'checked_out' ||
          status == 'return_requested') {
        final s = (data['startDate'] as Timestamp).toDate();
        final e = (data['endDate'] as Timestamp).toDate();
        if (e.isAfter(now)) {
          ranges.add(DateTimeRange(start: s, end: e));
        }
      }
    }

    // 2. Fetch equipment status for maintenance
    final eqDoc = await CareCenterRepository.equipmentCol
        .doc(widget.equipmentId)
        .get();
    if (eqDoc.exists) {
      final data = eqDoc.data() as Map<String, dynamic>;
      final status = data['availabilityStatus'];
      if (status == 'maintenance') {
        final untilTs = data['maintenanceUntil'];
        if (untilTs is Timestamp) {
          final until = untilTs.toDate();
          if (until.isAfter(now)) {
            // Block from now until the exact maintenance end time
            ranges.add(DateTimeRange(start: now, end: until));
          }
        }
      }
    }

    setState(() {
      _blockedRanges = ranges;
      // Update start date to first available date
      _start = _findFirstAvailableDate(DateTime.now());
      _end = _start.add(Duration(days: _duration));
    });
  }

  bool _isDateBlocked(DateTime date) {
    // Normalize date to midnight to match showDatePicker behavior
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    for (final range in _blockedRanges) {
      // Check if the day overlaps with any blocked range
      // Overlap exists if (StartA < EndB) and (EndA > StartB)
      if (dayStart.isBefore(range.end) && dayEnd.isAfter(range.start)) {
        return true;
      }
    }
    return false;
  }

  bool _isRangeBlocked(DateTime start, DateTime end) {
    for (final range in _blockedRanges) {
      // Check for overlap
      if (start.isBefore(range.end) && end.isAfter(range.start)) {
        return true;
      }
    }
    return false;
  }

  DateTime _findFirstAvailableDate(DateTime from) {
    // Start checking from midnight of the given date
    DateTime date = DateTime(from.year, from.month, from.day);
    int daysChecked = 0;
    while (_isDateBlocked(date) && daysChecked < 365) {
      date = date.add(const Duration(days: 1));
      daysChecked++;
    }
    return date;
  }

  Future<void> _pickStart() async {
    final initialDate = _findFirstAvailableDate(_start);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (day) => !_isDateBlocked(day),
    );
    if (picked != null) {
      setState(() {
        _start = picked;
        if (_end.isBefore(_start)) {
          _end = _start.add(Duration(days: _duration));
        }
      });
    }
  }

  Future<void> _pickEnd() async {
    var initialDate = _end;
    if (initialDate.isBefore(_start)) initialDate = _start;
    initialDate = _findFirstAvailableDate(initialDate);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (day) => !_isDateBlocked(day),
    );
    if (picked != null) {
      setState(() {
        _end = picked;
        _duration = _end.difference(_start).inDays;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    if (_end.isBefore(_start)) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastService.showError(
        context,
        'Error',
        'End date must be after start date',
      );
      return;
    }

    if (_isRangeBlocked(_start, _end)) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastService.showError(
        context,
        'Error',
        'Selected dates overlap with an existing reservation.',
      );
      return;
    }

    final profileSnap = await CareCenterRepository.getUserProfile(
      widget.renterId,
    );
    final profile = profileSnap.data() ?? {};
    final renterName = profile['name'] ?? 'Renter';
    final isTrusted = profile['isTrusted'] == true;
    final userType = isTrusted ? 'trusted' : 'normal';

    await CareCenterRepository.addReservation(
      equipmentId: widget.equipmentId,
      equipmentName: widget.equipmentName,
      equipmentType: widget.equipmentType,
      renterId: widget.renterId,
      renterName: renterName,
      startDate: _start,
      endDate: _end,
      requestType: _immediate ? 'immediate' : 'date_range',
      userTypeAtBooking: userType,
    );

    // Notify admins
    await CareCenterRepository.notifyAdmins(
      type: 'reservation_request',
      title: 'New reservation request',
      message: '$renterName requested ${widget.equipmentName}',
    );

    if (!mounted) return;
    setState(() => _loading = false);
    ToastService.showSuccess(
      context,
      'Success',
      'Reservation request submitted',
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reserve ${widget.equipmentName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Immediate pickup'),
                    subtitle: const Text('Start from today'),
                    value: _immediate,
                    onChanged: (v) {
                      setState(() {
                        _immediate = v;
                        _start = DateTime.now();
                        _end = _start.add(Duration(days: _duration));
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.today_rounded),
                    title: Text(
                      'Start: ${_start.toLocal().toString().split(' ').first}',
                    ),
                    trailing: TextButton(
                      onPressed: _immediate ? null : _pickStart,
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.event_available_rounded),
                    title: Text(
                      'End: ${_end.toLocal().toString().split(' ').first}',
                    ),
                    trailing: TextButton(
                      onPressed: _pickEnd,
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Real-time availability feedback
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isRangeBlocked(_start, _end)
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isRangeBlocked(_start, _end)
                            ? Colors.red.shade200
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isRangeBlocked(_start, _end)
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: _isRangeBlocked(_start, _end)
                              ? Colors.red
                              : Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isRangeBlocked(_start, _end)
                                ? 'Selected dates overlap with an existing reservation.'
                                : 'Dates are available.',
                            style: TextStyle(
                              color: _isRangeBlocked(_start, _end)
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Submit request'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
