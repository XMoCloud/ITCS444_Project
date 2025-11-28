import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sign in existing user
  static Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return cred.user;
  }

  /// Sign up + create user profile document
  static Future<User?> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String nationalId,
    required String preferredContact,
    required String role, // "admin" | "renter" | "guest"
  }) async {
    // 1) Auth user
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user;
    if (user == null) return null;

    // 2) Firestore profile doc
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

class CareCenterRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // references
  static CollectionReference get usersCol => _db.collection('users');
  static CollectionReference get equipmentCol => _db.collection('equipment');
  static CollectionReference get reservationsCol => _db.collection('reservations');
  static CollectionReference get donationsCol => _db.collection('donations');
  static CollectionReference get notificationsCol => _db.collection('notifications');
  static CollectionReference get maintenanceCol => _db.collection('maintenanceRecords');

  // ---- USERS ----
  static Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(String uid) {
    return usersCol.doc(uid).get() as Future<DocumentSnapshot<Map<String, dynamic>>>;
  }

  // ---- EQUIPMENT ----
  static Future<String> addEquipment({
    required String name,
    required String type,
    required String description,
    required String condition,
    required int quantityTotal,
    required String location,
    double? rentalPricePerDay,
    List<String>? tags,
  }) async {
    final docRef = await equipmentCol.add({
      'name': name,
      'type': type,
      'description': description,
      'condition': condition,
      'quantityTotal': quantityTotal,
      'quantityAvailable': quantityTotal,
      'location': location,
      'availabilityStatus': 'available',
      'rentalPricePerDay': rentalPricePerDay,
      'tags': tags ?? [],
      'images': [],
      'isDonatedItem': false,
      'donorId': null,
      'originalDonationId': null,
      'needsMaintenance': false,
      'lastMaintenanceAt': null,
      'rentalCount': 0,
      'donationCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  // ---- RESERVATIONS ----
  static Future<String> addReservation({
    required String equipmentId,
    required String renterId,
    required DateTime startDate,
    required DateTime endDate,
    required String requestType, // "immediate" | "date_range"
  }) async {
    final docRef = await reservationsCol.add({
      'equipmentId': equipmentId,
      'renterId': renterId,
      'adminId': null,
      'requestType': requestType,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending', // pending -> approved -> checked_out -> returned
      'suggestedEndDate': null,
      'finalEndDate': Timestamp.fromDate(endDate),
      'durationDays': endDate.difference(startDate).inDays,
      'userTypeAtBooking': 'new',
      'progressStep': 0,
      'notesUser': null,
      'notesAdmin': null,
      'returnedAt': null,
      'overdueDays': 0,
    });
    return docRef.id;
  }

  // ---- DONATIONS ----
  static Future<String> addDonation({
    String? donorId,
    required String donorName,
    required String donorContact,
    required String itemType,
    required String condition,
    required int quantity,
    String? description,
  }) async {
    final docRef = await donationsCol.add({
      'donorId': donorId,
      'donorName': donorName,
      'donorContact': donorContact,
      'itemType': itemType,
      'condition': condition,
      'quantity': quantity,
      'description': description ?? '',
      'photos': [],
      'status': 'pending', // pending, approved, rejected, added_to_inventory
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'reviewerAdminId': null,
      'linkedEquipmentId': null,
    });
    return docRef.id;
  }

  // ---- NOTIFICATIONS ----
  static Future<String> addNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? reservationId,
    String? equipmentId,
    String? donationId,
  }) async {
    final docRef = await notificationsCol.add({
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
    return docRef.id;
  }
}
