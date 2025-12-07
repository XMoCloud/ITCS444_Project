import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Shared Firebase helpers (auth, storage, firestore repositories).
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    return cred.user;
  }

  static Future<User?> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String nationalId,
    required String preferredContact,
    required String role, // "admin" | "renter"
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final user = cred.user;
    if (user == null) return null;

    await _db.collection('users').doc(user.uid).set({
      'name': name,
      'email': email,
      'phone': phone,
      'nationalId': nationalId,
      'preferredContact': preferredContact,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
      'rentalsCount': 0,
      'overdueCount': 0,
      'isTrusted': false,
    });

    return user;
  }

  static Future<void> signOut() => _auth.signOut();
}

class StorageService {
  static final _storage = FirebaseStorage.instance;

  static Future<String?> uploadImage(XFile file, String path, {Duration timeout = const Duration(seconds: 25)}) async {
    try {
      final ref = _storage.ref(path);
      final bytes = await file.readAsBytes();
      final uploadTask = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));

      await uploadTask.timeout(timeout, onTimeout: () async {
        try {
          await uploadTask.cancel();
        } catch (_) {}
        throw Exception('Upload timed out');
      });

      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Storage upload error: $e');
      return null;
    }
  }
}

class CareCenterRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final usersCol = _db.collection('users');
  static final equipmentCol = _db.collection('equipment');
  static final reservationsCol = _db.collection('reservations');
  static final donationsCol = _db.collection('donations');
  static final notificationsCol = _db.collection('notifications');
  static final maintenanceCol = _db.collection('maintenanceRecords');

  // USERS
  static Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(String uid) {
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
      'availabilityStatus': availabilityStatus,
      'rentalPricePerDay': rentalPricePerDay,
      'tags': tags ?? [],
      'images': images ?? [],
      'isDonatedItem': isDonatedItem,
      'donorId': donorId,
      'originalDonationId': originalDonationId,
      'needsMaintenance': availabilityStatus == 'maintenance',
      'maintenanceUntil': maintenanceUntil != null ? Timestamp.fromDate(maintenanceUntil) : null,
      'lastMaintenanceAt': null,
      'rentalCount': 0,
      'donationCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  static Future<void> updateEquipment(String equipmentId, Map<String, dynamic> data) async {
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
      'status': 'pending',
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
    if (closedAt != null) updates['closedAt'] = Timestamp.fromDate(closedAt);
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
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'reviewerAdminId': null,
      'linkedEquipmentId': null,
    });
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
    if (linkedEquipmentId != null) updates['linkedEquipmentId'] = linkedEquipmentId;
    await donationsCol.doc(donationId).update(updates);
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
      'maintenanceUntil': maintenanceUntil != null ? Timestamp.fromDate(maintenanceUntil) : null,
    });

    await equipmentCol.doc(equipmentId).update({
      'needsMaintenance': true,
      'availabilityStatus': 'maintenance',
      'lastMaintenanceAt': FieldValue.serverTimestamp(),
      'maintenanceUntil': maintenanceUntil != null ? Timestamp.fromDate(maintenanceUntil) : null,
    });

    return docRef.id;
  }
}
