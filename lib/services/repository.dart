import 'package:cloud_firestore/cloud_firestore.dart';

class CareCenterRepository {
  static final _db = FirebaseFirestore.instance;

  static final usersCol = _db.collection('users');
  static final equipmentCol = _db.collection('equipment');
  static final reservationsCol = _db.collection('reservations');
  static final donationsCol = _db.collection('donations');
  static final notificationsCol = _db.collection('notifications');
  static final maintenanceCol = _db.collection('maintenanceRecords');

  // USERS
  static Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(
    String uid,
  ) {
    return usersCol.doc(uid).get();
  }

  // EQUIPMENT
  static Future<String> addEquipment({
    required String name,
    required String type,
    required String description,
    required String condition,
    required int quantityTotal,
    required String location,
    double? rentalPricePerDay,
    List<String>? tags,
    bool isDonatedItem = false,
    String? donorId,
    String? originalDonationId,
    List<String>? images,
    String availabilityStatus = 'available',
    DateTime? maintenanceUntil,
  }) async {
    final docRef = await equipmentCol.add({
      'name': name,
      'type': type,
      'description': description,
      'condition': condition,
      'quantityTotal': quantityTotal,
      'quantityAvailable': quantityTotal,
      'location': location,
      'availabilityStatus':
          availabilityStatus, // available, rented, donated, maintenance
      'rentalPricePerDay': rentalPricePerDay,
      'tags': tags ?? [],
      'images': images ?? [],
      'isDonatedItem': isDonatedItem,
      'donorId': donorId,
      'originalDonationId': originalDonationId,
      'needsMaintenance': availabilityStatus == 'maintenance',
      'maintenanceUntil': maintenanceUntil != null
          ? Timestamp.fromDate(maintenanceUntil)
          : null,
      'lastMaintenanceAt': null,
      'rentalCount': 0,
      'donationCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  static Future<void> updateEquipment(
    String equipmentId,
    Map<String, dynamic> data,
  ) async {
    await equipmentCol.doc(equipmentId).update(data);
  }

  static Future<void> deleteEquipment(String equipmentId) async {
    await equipmentCol.doc(equipmentId).delete();
  }

  // RESERVATIONS
  static Future<String> addReservation({
    required String equipmentId,
    required String equipmentName,
    required String equipmentType,
    required String renterId,
    required String renterName,
    required DateTime startDate,
    required DateTime endDate,
    required String requestType,
    required String userTypeAtBooking,
  }) async {
    final durationDays = endDate.difference(startDate).inDays;
    final docRef = await reservationsCol.add({
      'equipmentId': equipmentId,
      'equipmentName': equipmentName,
      'equipmentType': equipmentType,
      'renterId': renterId,
      'renterName': renterName,
      'adminId': null,
      'requestType': requestType,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'createdAt': FieldValue.serverTimestamp(),
      'status':
          'pending', // pending -> approved -> checked_out -> returned -> maintenance / declined
      'suggestedEndDate': Timestamp.fromDate(endDate),
      'finalEndDate': Timestamp.fromDate(endDate),
      'durationDays': durationDays,
      'userTypeAtBooking': userTypeAtBooking,
      'progressStep': 1,
      'returnedAt': null,
      'overdueDays': 0,
      'closedAt': null,
    });
    return docRef.id;
  }

  static int _statusToStep(String status) {
    switch (status) {
      case 'pending':
        return 1;
      case 'approved':
        return 2;
      case 'checked_out':
        return 3;
      case 'return_requested':
        return 4;
      case 'returned':
        return 4;
      case 'maintenance':
        return 5;
      case 'declined':
        return 0;
      default:
        return 0;
    }
  }

  static int statusToStepPublic(String status) => _statusToStep(status);

  static Future<void> updateReservationStatus({
    required String reservationId,
    required String status,
    String? adminId,
    DateTime? closedAt,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'progressStep': _statusToStep(status),
    };
    if (adminId != null) updates['adminId'] = adminId;
    if (closedAt != null) {
      updates['closedAt'] = Timestamp.fromDate(closedAt);
    }
    if (status == 'returned') {
      updates['returnedAt'] = FieldValue.serverTimestamp();
    }
    if (status == 'maintenance') {
      updates['returnedAt'] = FieldValue.serverTimestamp();
    }
    await reservationsCol.doc(reservationId).update(updates);
  }

  static Future<void> deleteReservation(String reservationId) async {
    await reservationsCol.doc(reservationId).delete();
  }

  // NOTIFICATIONS
  static Future<void> addNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? reservationId,
    String? equipmentId,
    String? donationId,
  }) async {
    await notificationsCol.add({
      'userId': userId,
      'type': type,
      'title': title,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'reservationId': reservationId,
      'equipmentId': equipmentId,
      'donationId': donationId,
    });
  }

  static Future<void> notifyAdmins({
    required String type,
    required String title,
    required String message,
    String? reservationId,
    String? equipmentId,
    String? donationId,
  }) async {
    final admins = await usersCol.where('role', isEqualTo: 'admin').get();
    for (final doc in admins.docs) {
      await addNotification(
        userId: doc.id,
        type: type,
        title: title,
        message: message,
        reservationId: reservationId,
        equipmentId: equipmentId,
        donationId: donationId,
      );
    }
  }

  // DONATIONS
  static Future<String> addDonation({
    String? donorId,
    required String donorName,
    required String donorContact,
    required String itemType,
    required String condition,
    required int quantity,
    String? description,
    List<String>? photos,
  }) async {
    final docRef = await donationsCol.add({
      'donorId': donorId,
      'donorName': donorName,
      'donorContact': donorContact,
      'itemType': itemType,
      'condition': condition,
      'quantity': quantity,
      'description': description ?? '',
      'photos': photos ?? [],
      'status': 'pending', // pending, added_to_inventory, rejected
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'reviewerAdminId': null,
      'linkedEquipmentId': null,
    });

    // Notify admins about new donation
    await notifyAdmins(
      type: 'new_donation',
      title: 'New Donation Submitted',
      message: '$donorName submitted a donation of $quantity $itemType(s).',
      donationId: docRef.id,
    );

    return docRef.id;
  }

  static Future<void> updateDonationStatus({
    required String donationId,
    required String status,
    String? reviewerAdminId,
    String? linkedEquipmentId,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'reviewedAt': FieldValue.serverTimestamp(),
    };
    if (reviewerAdminId != null) updates['reviewerAdminId'] = reviewerAdminId;
    if (linkedEquipmentId != null)
      updates['linkedEquipmentId'] = linkedEquipmentId;
    await donationsCol.doc(donationId).update(updates);
  }

  // MAINTENANCE
  static Future<String> addMaintenanceRecord({
    required String equipmentId,
    required String openedByAdminId,
    String? description,
    String? relatedReservationId,
    DateTime? maintenanceUntil,
  }) async {
    final docRef = await maintenanceCol.add({
      'equipmentId': equipmentId,
      'openedByAdminId': openedByAdminId,
      'createdAt': FieldValue.serverTimestamp(),
      'description': description ?? '',
      'relatedReservationId': relatedReservationId,
      'status': 'open',
      'closedAt': null,
      'maintenanceUntil': maintenanceUntil != null
          ? Timestamp.fromDate(maintenanceUntil)
          : null,
    });

    await equipmentCol.doc(equipmentId).update({
      'needsMaintenance': true,
      'availabilityStatus': 'maintenance',
      'lastMaintenanceAt': FieldValue.serverTimestamp(),
      'maintenanceUntil': maintenanceUntil != null
          ? Timestamp.fromDate(maintenanceUntil)
          : null,
    });

    return docRef.id;
  }
}
