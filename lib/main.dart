import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'firebase_options.dart';

/// ------------------------------------------------------------
/// MAIN
/// ------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const CareCenterApp());
}

class CareCenterApp extends StatelessWidget {
  const CareCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Care Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(width: 1.5),
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

/// ------------------------------------------------------------
/// SERVICES (AUTH / DB / STORAGE)
/// ------------------------------------------------------------

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

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

  static Future<User?> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String nationalId,
    required String preferredContact,
    required String role, // "admin", "renter"
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
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

  static Future<String?> uploadImage(XFile file, String path,
      {Duration timeout = const Duration(seconds: 25)}) async {
    try {
      final ref = _storage.ref(path);
      Uint8List bytes = await file.readAsBytes();
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Wait for task to complete, with timeout to avoid UI hanging on web when CORS blocks
      await uploadTask.timeout(timeout, onTimeout: () async {
        try {
          // Try to cancel if possible
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
  static final _db = FirebaseFirestore.instance;

  static final usersCol = _db.collection('users');
  static final equipmentCol = _db.collection('equipment');
  static final reservationsCol = _db.collection('reservations');
  static final donationsCol = _db.collection('donations');
  static final notificationsCol = _db.collection('notifications');
  static final maintenanceCol = _db.collection('maintenanceRecords');

  // USERS
  static Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(
      String uid) {
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
      'availabilityStatus': availabilityStatus, // available, rented, donated, maintenance
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

  static Future<void> updateEquipment(
      String equipmentId, Map<String, dynamic> data) async {
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
      'status': 'pending', // pending -> approved -> checked_out -> returned -> maintenance / declined
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
      'maintenanceUntil':
          maintenanceUntil != null ? Timestamp.fromDate(maintenanceUntil) : null,
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

/// ------------------------------------------------------------
/// LOGIN & REGISTER
/// ------------------------------------------------------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final user = await AuthService.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );
      if (user == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed')),
        );
        return;
      }

      final profileSnap = await CareCenterRepository.getUserProfile(user.uid);
      final profile = profileSnap.data();
      final role = profile?['role'] as String? ?? 'renter';

      if (!mounted) return;
      setState(() => _loading = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainShell(role: role, userId: user.uid),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Authentication error')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error')),
      );
    }
  }

  void _guest() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MainShell(role: 'guest', userId: null),
      ),
    );
  }

  void _openRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.health_and_safety_rounded,
                    size: 64, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  'Care Center',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rental • Donation • Exchange',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Sign in',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_rounded),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter email';
                              }
                              if (!v.contains('@')) return 'Invalid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_rounded),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() => _obscure = !_obscure);
                                },
                                icon: Icon(_obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Enter password';
                              }
                              if (v.length < 6) {
                                return 'Min 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {},
                              child: const Text('Forgot password?'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _login,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: Text(
                                  _loading ? 'Signing in...' : 'Sign in'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child:
                                      Divider(color: Colors.grey[300])),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0),
                                child: Text(
                                  'or',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ),
                              Expanded(
                                  child:
                                      Divider(color: Colors.grey[300])),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _guest,
                              icon: const Icon(Icons.visibility_off_rounded),
                              label: const Text('Continue as guest'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _openRegister,
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('Create a new account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _preferredContact = 'phone';
  String _role = 'renter';
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final user = await AuthService.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        nationalId: _idCtrl.text.trim(),
        preferredContact: _preferredContact,
        role: _role,
      );
      if (!mounted) return;
      setState(() => _loading = false);

      if (user != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => MainShell(role: _role, userId: user.uid),
          ),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Registration error')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Create a new account',
                        style:
                            tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Enter name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_rounded),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter email';
                          }
                          if (!v.contains('@')) return 'Invalid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _idCtrl,
                        decoration: const InputDecoration(
                          labelText: 'National ID',
                          prefixIcon: Icon(Icons.badge_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _preferredContact,
                        decoration: const InputDecoration(
                          labelText: 'Preferred contact',
                          prefixIcon:
                              Icon(Icons.notifications_active_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'phone',
                            child: Text('Phone'),
                          ),
                          DropdownMenuItem(
                            value: 'email',
                            child: Text('Email'),
                          ),
                          DropdownMenuItem(
                            value: 'whatsapp',
                            child: Text('WhatsApp'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _preferredContact = v ?? 'phone'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _role,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          prefixIcon: Icon(Icons.security_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'renter',
                            child: Text('Renter'),
                          ),
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Admin (Donor/Staff)'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _role = v ?? 'renter'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_rounded),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter password';
                          if (v.length < 6) return 'Min 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _register,
                          child: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Create account'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// MAIN SHELL
/// ------------------------------------------------------------

class MainShell extends StatefulWidget {
  final String role;
  final String? userId;

  const MainShell({
    super.key,
    required this.role,
    required this.userId,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  List<Widget> get _pages => [
        DashboardPage(role: widget.role, userId: widget.userId),
        InventoryPage(role: widget.role, userId: widget.userId),
        widget.role == 'admin'
            ? AdminReservationsPage(adminId: widget.userId ?? '')
            : UserRentalsPage(userId: widget.userId),
        DonationsPage(role: widget.role, userId: widget.userId),
        ProfilePage(role: widget.role, userId: widget.userId),
      ];

  String _title() {
    switch (_index) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Inventory';
      case 2:
        return widget.role == 'admin'
            ? 'Manage Reservations'
            : 'My Rentals';
      case 3:
        return 'Donations';
      case 4:
        return 'Profile';
      default:
        return 'Care Center';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.surface,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.health_and_safety_rounded, color: cs.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _title(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: KeyedSubtree(
            key: ValueKey(_index),
            child: _pages[_index],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_repeat_outlined),
            selectedIcon: Icon(Icons.event_repeat_rounded),
            label: 'Rentals',
          ),
          NavigationDestination(
            icon: Icon(Icons.volunteer_activism_outlined),
            selectedIcon: Icon(Icons.volunteer_activism_rounded),
            label: 'Donations',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// DASHBOARD
/// ------------------------------------------------------------

class DashboardPage extends StatefulWidget {
  final String role;
  final String? userId;

  const DashboardPage({
    super.key,
    required this.role,
    required this.userId,
  });

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Attention: $overdueCount rental(s) are overdue!'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
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
        Text(
          isAdmin ? 'Welcome back, Admin 👋' : 'Welcome 👋',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          isAdmin
              ? 'Overview of inventory, rentals and donations.'
              : 'Browse equipment and track your rentals.',
          style: tt.bodyMedium?.copyWith(color: Colors.grey[700]),
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
        final available =
            eqDocs.where((d) => d['availabilityStatus'] == 'available').length;
        final rented =
            eqDocs.where((d) => d['availabilityStatus'] == 'rented').length;
        final maintenance =
            eqDocs.where((d) => d['availabilityStatus'] == 'maintenance').length;

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: _StatCard(
                        title: 'Total Equipment',
                        value: '$total',
                        icon: Icons.inventory_2_rounded,
                        color: Colors.blue)),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatCard(
                        title: 'Available',
                        value: '$available',
                        icon: Icons.check_circle_rounded,
                        color: Colors.green)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _StatCard(
                        title: 'Rented Out',
                        value: '$rented',
                        icon: Icons.shopping_bag_rounded,
                        color: Colors.orange)),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatCard(
                        title: 'Maintenance',
                        value: '$maintenance',
                        icon: Icons.build_rounded,
                        color: Colors.red)),
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
                return _StatCard(
                  title: 'Pending Donations',
                  value: '$pendingDonations',
                  icon: Icons.volunteer_activism_rounded,
                  color: Colors.purple,
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Most Frequently Rented', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...snap.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(data['name'] ?? 'Unknown'),
                        Text('${data['rentalCount'] ?? 0} rentals', style: const TextStyle(fontWeight: FontWeight.bold)),
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
    final rented = allEquipment.where((d) => d['availabilityStatus'] == 'rented').length;
    final maintenance = allEquipment.where((d) => d['availabilityStatus'] == 'maintenance').length;
    
    final utilRate = (rented / total * 100).toStringAsFixed(1);
    final maintRate = (maintenance / total * 100).toStringAsFixed(1);
    
    return Card(
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_rounded, color: Colors.teal),
                const SizedBox(width: 8),
                Text('Service Insights', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
              ],
            ),
            const SizedBox(height: 8),
            Text('• Utilization Rate: $utilRate% of inventory is currently rented.'),
            Text('• Maintenance Health: $maintRate% of items are under repair.'),
            if (rented > total * 0.7) 
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text('• High Demand: Consider acquiring more equipment.', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    'Renter: ${data['renterName']}\nOverdue by $days days'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
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
                child: _StatCard(
                    title: 'Active Rentals',
                    value: '$active',
                    icon: Icons.shopping_bag_rounded,
                    color: Colors.blue)),
            const SizedBox(width: 12),
            Expanded(
                child: _StatCard(
                    title: 'Pending Requests',
                    value: '$pending',
                    icon: Icons.hourglass_empty_rounded,
                    color: Colors.orange)),
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
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No active rentals at the moment.'),
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

            return Card(
              color: isOverdue ? Colors.red.shade50 : null,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  isOverdue ? Icons.warning_rounded : Icons.timer_rounded,
                  color: isOverdue ? Colors.red : Colors.blue,
                ),
                title: Text(data['equipmentName'] ?? ''),
                subtitle: Text(isOverdue
                    ? 'Overdue by ${now.difference(end).inDays} days'
                    : '$daysLeft days remaining'),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// INVENTORY + ADD/EDIT + RESERVATION FORM
/// ------------------------------------------------------------

class InventoryPage extends StatefulWidget {
  final String role;
  final String? userId;

  const InventoryPage({
    super.key,
    required this.role,
    required this.userId,
  });

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String _search = '';
  String _availabilityFilter = 'all';
  String _typeFilter = 'all';
  bool _donatedOnly = false;

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
                        value: 'wheelchair', child: Text('Wheelchair')),
                    DropdownMenuItem(value: 'walker', child: Text('Walker')),
                    DropdownMenuItem(
                        value: 'crutches', child: Text('Crutches')),
                    DropdownMenuItem(value: 'bed', child: Text('Hospital bed')),
                    DropdownMenuItem(value: 'oxygen_machine', child: Text('Oxygen machine')),
                    DropdownMenuItem(value: 'mobility_scooter', child: Text('Mobility scooter')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => tempType = v ?? 'all'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: tempStatus,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'available', child: Text('Available')),
                    DropdownMenuItem(value: 'rented', child: Text('Rented')),
                    DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => tempStatus = v ?? 'all'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Show donated only'),
                  value: tempDonated,
                  onChanged: (v) =>
                      setDialogState(() => tempDonated = v),
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
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search equipment...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) =>
                        setState(() => _search = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.outlined(
                  onPressed: _openFilters,
                  icon: const Icon(Icons.filter_list_rounded),
                  tooltip: 'Filter',
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
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text('No equipment found.'));
                }

                final now = DateTime.now();
                var docs = snap.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final name =
                      (data['name'] ?? '').toString().toLowerCase();
                  final type = (data['type'] ?? '').toString();
                  var status =
                      (data['availabilityStatus'] ?? 'available').toString();
                  final isDonated =
                      (data['isDonatedItem'] ?? false) as bool;
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
                        final resSnap = await CareCenterRepository.reservationsCol
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
                            debugPrint('Failed to delete reservation ${r.id}: $e');
                          }
                        }

                        final maintSnap = await CareCenterRepository.maintenanceCol
                            .where('equipmentId', isEqualTo: d.id)
                            .where('status', isEqualTo: 'open')
                            .get();
                        for (final m in maintSnap.docs) {
                          try {
                            await CareCenterRepository.maintenanceCol.doc(m.id).update({
                              'status': 'closed',
                              'closedAt': FieldValue.serverTimestamp(),
                            });
                          } catch (e) {
                            debugPrint('Failed to close maintenance record ${m.id}: $e');
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
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddEquipmentPage()),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add equipment'),
            )
          : null,
    );
  }
}

class EquipmentCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final String role;
  final String? userId;

  const EquipmentCard({
    super.key,
    required this.docId,
    required this.data,
    required this.role,
    required this.userId,
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

  @override
  State<EquipmentCard> createState() => _EquipmentCardState();
}

class _EquipmentCardState extends State<EquipmentCard> {
  Timer? _timer;
  String _timeRemaining = '';
  bool _autoReleased = false;

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
                    debugPrint('Failed to close maintenance record ${m.id}: $e');
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
            _timeRemaining = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
    final canReserve = !isAdmin && status == 'available';
    final isDonated = (data['isDonatedItem'] ?? false) as bool;
    final donorId = (data['donorId'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 86,
                    height: 86,
                    color: Colors.grey[200],
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            },
                            errorBuilder: (context, err, stack) => Icon(
                              widget._typeIcon(type.toString()),
                              size: 40,
                              color: Colors.grey[700],
                            ),
                          )
                        : Icon(
                            widget._typeIcon(type.toString()),
                            size: 40,
                            color: Colors.grey[700],
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text('Type: $type • Condition: ${data['condition'] ?? 'n/a'}'),
                                if ((data['location'] ?? '').toString().isNotEmpty)
                                  Text('Location: ${data['location']}'),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
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
                            avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                            label: Text('Qty: ${data['quantityAvailable'] ?? data['quantityTotal'] ?? '-'}'),
                          ),
                          if (data['rentalPricePerDay'] != null)
                            Chip(
                              avatar: const Icon(Icons.attach_money_rounded, size: 18),
                              label: Text('Price/day: ${data['rentalPricePerDay']}'),
                            ),
                          if (status == 'maintenance' && _timeRemaining.isNotEmpty)
                            Chip(
                              avatar: const Icon(Icons.build_rounded, size: 18),
                              label: Text('Maintenance: $_timeRemaining'),
                              backgroundColor: Colors.red.shade50,
                            ),
                        ],
                      ),
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
                            if (st != 'approved' && st != 'checked_out') return false;
                            final end = (rd['endDate'] as Timestamp).toDate();
                            return end.isAfter(now);
                          }).toList();
                          if (docs.isEmpty) {
                            return Text(
                              'Not rented currently',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            );
                          }
                          docs.sort((a, b) {
                            final ea = (a.data() as Map<String, dynamic>)['endDate'] as Timestamp;
                            final eb = (b.data() as Map<String, dynamic>)['endDate'] as Timestamp;
                            return ea.toDate().compareTo(eb.toDate());
                          });
                          final soonEnd = (docs.first.data() as Map<String, dynamic>)['endDate'] as Timestamp;
                          final days = soonEnd.toDate().difference(now).inDays;
                          final text = days >= 0 ? 'Remaining: $days day(s)' : 'Overdue';
                          return Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]));
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
                                Icon(Icons.volunteer_activism_rounded, size: 18, color: Colors.purple),
                                SizedBox(width: 6),
                                Text('Donated item', style: TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                            if (donorId.isNotEmpty)
                              FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                future: CareCenterRepository.usersCol.doc(donorId).get(),
                                builder: (context, snap) {
                                  if (!snap.hasData) return const SizedBox.shrink();
                                  final user = snap.data!.data() ?? {};
                                  final dn = user['name'] ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text('Donated by: $dn', style: Theme.of(context).textTheme.bodySmall),
                                  );
                                },
                              ),
                          ],
                        ),
                      const SizedBox(height: 6),
                      if ((data['tags'] as List?)?.isNotEmpty == true)
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: ((data['tags'] as List?)?.cast<String>() ?? [])
                              .map((t) => Chip(label: Text(t)))
                              .toList(),
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
                                  child: Image.network(img, width: 56, height: 56, fit: BoxFit.cover),
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
                    child: FilledButton.icon(
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
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await CareCenterRepository.deleteEquipment(docId);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Equipment deleted')),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: canReserve
                      ? () {
                          if (userId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Sign in to reserve equipment.')),
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
                  icon: const Icon(Icons.event_available_rounded),
                  label: const Text('Reserve'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AddEquipmentPage extends StatefulWidget {
  const AddEquipmentPage({super.key});

  @override
  State<AddEquipmentPage> createState() => _AddEquipmentPageState();
}

class _AddEquipmentPageState extends State<AddEquipmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _locCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  bool _saving = false;

  String _type = 'wheelchair';
  String _condition = 'good';
  String _availability = 'available';
  DateTime? _maintenanceUntil;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _locCtrl.dispose();
    _priceCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final price = _priceCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_priceCtrl.text);
    final imageUrl = _imageCtrl.text.trim();

    await CareCenterRepository.addEquipment(
      name: _nameCtrl.text.trim(),
      type: _type,
      description: _descCtrl.text.trim(),
      condition: _condition,
      quantityTotal: qty,
      location: _locCtrl.text.trim(),
      rentalPricePerDay: price,
      images: imageUrl.isNotEmpty ? [imageUrl] : [],
      isDonatedItem: false,
      availabilityStatus: _availability,
      maintenanceUntil: _availability == 'maintenance' ? _maintenanceUntil : null,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Equipment added')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add equipment')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _imageCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Image URL',
                        prefixIcon: Icon(Icons.link_rounded),
                        hintText: 'https://example.com/image.jpg',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Enter name' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        prefixIcon: Icon(Icons.list_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'wheelchair', child: Text('Wheelchair')),
                        DropdownMenuItem(
                            value: 'walker', child: Text('Walker')),
                        DropdownMenuItem(
                            value: 'crutches', child: Text('Crutches')),
                        DropdownMenuItem(value: 'bed', child: Text('Bed')),
                        DropdownMenuItem(value: 'oxygen_machine', child: Text('Oxygen machine')),
                        DropdownMenuItem(value: 'mobility_scooter', child: Text('Mobility scooter')),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'wheelchair'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _condition,
                      decoration: const InputDecoration(
                        labelText: 'Condition',
                        prefixIcon: Icon(Icons.fact_check_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'new', child: Text('New')),
                        DropdownMenuItem(value: 'good', child: Text('Good')),
                        DropdownMenuItem(value: 'fair', child: Text('Fair')),
                        DropdownMenuItem(
                            value: 'needs_repair',
                            child: Text('Needs repair')),
                      ],
                      onChanged: (v) =>
                          setState(() => _condition = v ?? 'good'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _availability,
                      decoration: const InputDecoration(
                        labelText: 'Availability status',
                        prefixIcon: Icon(Icons.info_outline_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'available', child: Text('Available')),
                        DropdownMenuItem(value: 'rented', child: Text('Rented')),
                        DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
                      ],
                      onChanged: (v) => setState(() => _availability = v ?? 'available'),
                    ),
                    if (_availability == 'maintenance') ...[
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.build_circle_rounded),
                        title: Text(_maintenanceUntil == null
                            ? 'Maintenance until not set'
                            : 'Until: ${_maintenanceUntil!.toLocal().toString().split(' ').first}'),
                        trailing: TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() => _maintenanceUntil = picked);
                            }
                          },
                          child: const Text('Set'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(Icons.description_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        prefixIcon: Icon(Icons.countertops_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        prefixIcon: Icon(Icons.place_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rental price per day (optional)',
                        prefixIcon: Icon(Icons.attach_money_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditEquipmentPage extends StatefulWidget {
  final String equipmentId;
  final Map<String, dynamic> initialData;

  const EditEquipmentPage({
    super.key,
    required this.equipmentId,
    required this.initialData,
  });

  @override
  State<EditEquipmentPage> createState() => _EditEquipmentPageState();
}

class _EditEquipmentPageState extends State<EditEquipmentPage> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _locCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _tagsCtrl;
  late TextEditingController _imageCtrl;

  String _status = 'available';
  String _type = 'wheelchair';
  String _condition = 'good';
  DateTime? _maintenanceUntil;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _nameCtrl = TextEditingController(text: d['name'] ?? '');
    _descCtrl = TextEditingController(text: d['description'] ?? '');
    _locCtrl = TextEditingController(text: d['location'] ?? '');
    _qtyCtrl =
        TextEditingController(text: (d['quantityTotal'] ?? 1).toString());
    _priceCtrl =
        TextEditingController(text: (d['rentalPricePerDay'] ?? '').toString());
    final images = (d['images'] as List?)?.cast<String>() ?? [];
    _imageCtrl = TextEditingController(text: images.isNotEmpty ? images.first : '');
    _status = (d['availabilityStatus'] ?? 'available').toString();
        if (d['maintenanceUntil'] is Timestamp) {
          _maintenanceUntil = (d['maintenanceUntil'] as Timestamp).toDate();
        }
    _type = (d['type'] ?? 'wheelchair').toString();
    _condition = (d['condition'] ?? 'good').toString();
    final tags = (d['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    _tagsCtrl = TextEditingController(text: tags.join(', '));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _tagsCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final price = _priceCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_priceCtrl.text);
    final tags = _tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final updates = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'location': _locCtrl.text.trim(),
      'quantityTotal': qty,
      'rentalPricePerDay': price,
      'availabilityStatus': _status,
      'type': _type,
      'condition': _condition,
      'tags': tags,
      'images': _imageCtrl.text.trim().isEmpty ? [] : [_imageCtrl.text.trim()],
    };
    if (_status == 'maintenance') {
      if (_maintenanceUntil == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select maintenance date & time')), 
          );
        }
        return;
      }
      updates['needsMaintenance'] = true;
      updates['maintenanceUntil'] = Timestamp.fromDate(_maintenanceUntil!);
    } else {
      updates['needsMaintenance'] = false;
      updates['maintenanceUntil'] = null;
    }
    await CareCenterRepository.updateEquipment(widget.equipmentId, updates);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Equipment updated')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit equipment')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextFormField(
                    controller: _imageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Image URL',
                      prefixIcon: Icon(Icons.link_rounded),
                      hintText: 'https://example.com/image.jpg',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.label_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      prefixIcon: Icon(Icons.list_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'wheelchair', child: Text('Wheelchair')),
                      DropdownMenuItem(
                          value: 'walker', child: Text('Walker')),
                      DropdownMenuItem(
                          value: 'crutches', child: Text('Crutches')),
                      DropdownMenuItem(value: 'bed', child: Text('Bed')),
                      DropdownMenuItem(value: 'oxygen_machine', child: Text('Oxygen machine')),
                      DropdownMenuItem(value: 'mobility_scooter', child: Text('Mobility scooter')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? 'wheelchair'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _condition,
                    decoration: const InputDecoration(
                      labelText: 'Condition',
                      prefixIcon: Icon(Icons.fact_check_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'new', child: Text('New')),
                      DropdownMenuItem(value: 'good', child: Text('Good')),
                      DropdownMenuItem(value: 'fair', child: Text('Fair')),
                      DropdownMenuItem(
                          value: 'needs_repair',
                          child: Text('Needs repair')),
                    ],
                    onChanged: (v) =>
                        setState(() => _condition = v ?? 'good'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.description_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      prefixIcon: Icon(Icons.place_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity total',
                      prefixIcon: Icon(Icons.countertops_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Rental price per day',
                      prefixIcon: Icon(Icons.attach_money_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tagsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma separated)',
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.info_outline_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'available', child: Text('Available')),
                      DropdownMenuItem(value: 'rented', child: Text('Rented')),
                      DropdownMenuItem(
                          value: 'donated', child: Text('Donated')),
                      DropdownMenuItem(
                          value: 'maintenance', child: Text('Maintenance')),
                    ],
                    onChanged: (v) =>
                        setState(() => _status = v ?? 'available'),
                  ),
                  if (_status == 'maintenance') ...[
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.build_circle_rounded),
                      title: Text(_maintenanceUntil == null
                          ? 'Maintenance until not set'
                          : 'Until: ${_maintenanceUntil!.toLocal()}'),
                      subtitle: const Text('Select both date and time'),
                      trailing: TextButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: _maintenanceUntil ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (pickedDate == null) return;
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(_maintenanceUntil ?? DateTime.now()),
                          );
                          if (pickedTime == null) return;
                          setState(() {
                            _maintenanceUntil = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              pickedTime.hour,
                              pickedTime.minute,
                            );
                          });
                        },
                        child: const Text('Set'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save changes'),
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

  @override
  void initState() {
    super.initState();
    if (widget.equipmentType == 'wheelchair') {
      _duration = 14;
    }
    _end = _start.add(Duration(days: _duration));
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('End date must be after start date')));
      return;
    }

    final profileSnap =
        await CareCenterRepository.getUserProfile(widget.renterId);
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
    await CareCenterRepository.addNotification(
      userId: 'admin_inbox',
      type: 'reservation_request',
      title: 'New reservation request',
      message: '$renterName requested ${widget.equipmentName}',
    );

    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reservation request submitted')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text('Reserve ${widget.equipmentName}')),
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
                        'Start: ${_start.toLocal().toString().split(' ').first}'),
                    trailing: TextButton(
                      onPressed: _immediate ? null : _pickStart,
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.event_available_rounded),
                    title: Text('End: ${_end.toLocal().toString().split(' ').first}'),
                    trailing: TextButton(
                      onPressed: _pickEnd,
                      child: const Text('Change'),
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

/// ------------------------------------------------------------
/// ADMIN RESERVATIONS (with status change + maintenance timer)
/// ------------------------------------------------------------

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
          'availabilityStatus': 'rented',
          'rentalCount': FieldValue.increment(1),
        });
      } else if (status == 'returned' || status == 'declined') {
        await CareCenterRepository.updateEquipment(equipmentId, {
          'availabilityStatus': 'available',
          'needsMaintenance': false,
          'maintenanceUntil': null,
        });
      } else if (status == 'maintenance') {
        final until = maintenanceUntil ?? DateTime.now().add(const Duration(hours: 1));
        await CareCenterRepository.updateEquipment(equipmentId, {
          'availabilityStatus': 'maintenance',
          'needsMaintenance': true,
          'maintenanceUntil': Timestamp.fromDate(until),
        });
        await CareCenterRepository.addMaintenanceRecord(
          equipmentId: equipmentId,
          openedByAdminId: widget.adminId,
          description: 'Sent to maintenance from reservation panel',
          relatedReservationId: reservationId,
          maintenanceUntil: until,
        );
      }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reservation set to $status')),
    );
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
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(child: Text('No reservations yet.'));
        }

        final docs = snap.data!.docs.toList();
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

        final activeStatuses = {'pending', 'approved', 'checked_out', 'maintenance'};
        final historyStatuses = {'returned', 'declined'};
        final filteredDocs = docs.where((d) {
          final status = ((d.data() as Map<String, dynamic>)['status'] ?? 'pending').toString();
          return _showHistory ? historyStatuses.contains(status) : activeStatuses.contains(status);
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Text(_showHistory
                ? 'No historical reservations yet.'
                : 'No active reservations yet.'),
          );
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
              child: ListView.builder(
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
                  final isClosed = status == 'declined' ||
                      status == 'returned' ||
                      status == 'maintenance';
                  final cardColor = isClosed ? Colors.grey.shade200 : Colors.white;
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.toString(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Renter: $renter'),
                                      Text(range),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    status,
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
                                      backgroundColor: Colors.green.shade500,
                                    ),
                                    onPressed: () => _changeStatus(
                                      context,
                                      doc.id,
                                      'checked_out',
                                      equipmentId:
                                          data['equipmentId'] as String?,
                                      renterId: data['renterId'] as String?,
                                    ),
                                    icon: const Icon(Icons.check_circle_rounded),
                                    label: const Text('Accept & Check Out'),
                                  ),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red.shade400,
                                    ),
                                    onPressed: () => _changeStatus(
                                      context,
                                      doc.id,
                                      'declined',
                                      equipmentId:
                                          data['equipmentId'] as String?,
                                      renterId: data['renterId'] as String?,
                                    ),
                                    icon: const Icon(Icons.close_rounded),
                                    label: const Text('Reject'),
                                  ),
                                ] else if (status == 'checked_out' && !_showHistory) ...[
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green.shade500,
                                    ),
                                    onPressed: () => _changeStatus(
                                      context,
                                      doc.id,
                                      'returned',
                                      equipmentId:
                                          data['equipmentId'] as String?,
                                      renterId: data['renterId'] as String?,
                                    ),
                                    icon: const Icon(
                                        Icons.check_circle_outline_rounded),
                                    label: const Text('Mark returned'),
                                  ),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.orange.shade600,
                                    ),
                                    onPressed: () async {
                                      final until =
                                          await _pickMaintenanceUntil(context);
                                      if (until == null) return;
                                      if (!context.mounted) return;
                                      await _changeStatus(
                                        context,
                                        doc.id,
                                        'maintenance',
                                        equipmentId:
                                            data['equipmentId'] as String?,
                                        renterId:
                                            data['renterId'] as String?,
                                        maintenanceUntil: until,
                                      );
                                    },
                                    icon: const Icon(Icons.build_circle_rounded),
                                    label: const Text('Send to maintenance'),
                                  ),
                                ],
                                TextButton.icon(
                                  onPressed: () async {
                                    await CareCenterRepository
                                        .deleteReservation(doc.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Reservation deleted')),
                                    );
                                  },
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  label: const Text('Delete'),
                                ),
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

/// ------------------------------------------------------------
/// USER RENTALS
/// ------------------------------------------------------------

class UserRentalsPage extends StatefulWidget {
  final String? userId;
  final bool initialShowHistory;
  const UserRentalsPage({super.key, required this.userId, this.initialShowHistory = false});

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
    if (widget.userId == null) {
      return const Center(
        child: Text('Sign in to view your rentals.'),
      );
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
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(child: Text('No reservations yet.'));
        }

        final docs = snap.data!.docs.toList();
        docs.sort((a, b) {
          final da = (a.data() as Map<String, dynamic>)['createdAt'];
          final db = (b.data() as Map<String, dynamic>)['createdAt'];
          if (da == null || db == null) return 0;
          return (db as Timestamp).compareTo(da as Timestamp);
        });

        final activeStatuses = {'pending', 'approved', 'checked_out', 'maintenance'};
        final historyStatuses = {'returned', 'declined'};
        final filteredDocs = docs.where((d) {
          final status = ((d.data() as Map<String, dynamic>)['status'] ?? 'pending').toString();
          return _showHistory ? historyStatuses.contains(status) : activeStatuses.contains(status);
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Text(_showHistory
                ? 'No historical rentals yet.'
                : 'No active rentals yet.'),
          );
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
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredDocs.length,
                itemBuilder: (context, i) {
                  final data = filteredDocs[i].data() as Map<String, dynamic>;
            final name = data['equipmentName'] ?? 'Equipment';
            final status = (data['status'] ?? 'pending').toString();
            final color = _statusColor(status);
            final start = (data['startDate'] as Timestamp).toDate();
            final end = (data['endDate'] as Timestamp).toDate();
            final range =
                '${start.toLocal().toString().split(' ').first} → ${end.toLocal().toString().split(' ').first}';

                  return Card(
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
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  status,
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

/// ------------------------------------------------------------
/// DONATIONS + FORM (with image upload)
/// ------------------------------------------------------------

class DonationsPage extends StatelessWidget {
  final String role;
  final String? userId;

  const DonationsPage({
    super.key,
    required this.role,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';

    if (!isAdmin && userId == null) {
      return const Center(child: Text('Sign in to view your donations.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: userId == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  DonationFormPage(donorId: userId!),
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
          child: StreamBuilder<QuerySnapshot>(
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
                    child: Text('No donations yet. Be the first!'));
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
    final displayName = (data['donorName'] ?? '').toString().isNotEmpty
      ? data['donorName']
      : data['itemType']
        ?? 'Item';
    final status = (data['status'] ?? 'pending').toString();
    final donor = data['donorName'] ?? 'Donor';
    final color = _statusColor(status);
    final photos = (data['photos'] as List?)?.cast<String>() ?? [];
    final imageUrl = photos.isNotEmpty ? photos.first : null;

    final isPending = status == 'pending';
    final isClosed =
        status == 'added_to_inventory' || status == 'rejected';
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
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              },
                              errorBuilder: (context, err, stack) => const Icon(
                                Icons.card_giftcard_rounded,
                                size: 32,
                              ),
                            )
                          : const Icon(Icons.card_giftcard_rounded,
                              size: 32),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.toString(),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
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
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status,
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
                          child: Image.network(img,
                              width: 56, height: 56, fit: BoxFit.cover),
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

                        final eqId =
                            await CareCenterRepository.addEquipment(
                            name: displayName.toString(),
                            type: (data['itemType'] ?? 'other').toString(),
                          description:
                              (data['description'] ?? 'Donated item')
                                  .toString(),
                          condition:
                              (data['condition'] ?? 'good').toString(),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Donation approved and added')),
                        );
                      },
                      icon:
                          const Icon(Icons.check_circle_rounded),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Donation rejected')),
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

class DonationFormPage extends StatefulWidget {
  final String donorId;
  const DonationFormPage({super.key, required this.donorId});

  @override
  State<DonationFormPage> createState() => _DonationFormPageState();
}

class _DonationFormPageState extends State<DonationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _donorNameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _descCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  String _itemType = 'wheelchair';
  String _condition = 'good';
  bool _saving = false;

  @override
  void dispose() {
    _donorNameCtrl.dispose();
    _contactCtrl.dispose();
    _qtyCtrl.dispose();
    _descCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final imageUrl = _imageCtrl.text.trim();

    await CareCenterRepository.addDonation(
      donorId: widget.donorId,
      donorName: _donorNameCtrl.text.trim(),
      donorContact: _contactCtrl.text.trim(),
      itemType: _itemType,
      condition: _condition,
      quantity: qty,
      description: _descCtrl.text.trim(),
      photos: imageUrl.isNotEmpty ? [imageUrl] : [],
    );

    await CareCenterRepository.addNotification(
      userId: 'admin_inbox',
      type: 'new_donation',
      title: 'New donation',
      message:
          '${_donorNameCtrl.text.trim()} offered $_itemType (x$qty)',
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Donation submitted')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offer a donation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _imageCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Image URL',
                        prefixIcon: Icon(Icons.link_rounded),
                        hintText: 'https://example.com/image.jpg',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _donorNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _contactCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contact info',
                        prefixIcon:
                            Icon(Icons.contact_phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _itemType,
                      decoration: const InputDecoration(
                        labelText: 'Item type',
                        prefixIcon:
                            Icon(Icons.medical_services_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'wheelchair', child: Text('Wheelchair')),
                        DropdownMenuItem(
                            value: 'walker', child: Text('Walker')),
                        DropdownMenuItem(
                            value: 'crutches', child: Text('Crutches')),
                        DropdownMenuItem(value: 'bed', child: Text('Bed')),
                        DropdownMenuItem(value: 'oxygen_machine', child: Text('Oxygen machine')),
                        DropdownMenuItem(value: 'mobility_scooter', child: Text('Mobility scooter')),
                      ],
                      onChanged: (v) =>
                          setState(() => _itemType = v ?? 'wheelchair'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _condition,
                      decoration: const InputDecoration(
                        labelText: 'Condition',
                        prefixIcon: Icon(Icons.fact_check_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'new', child: Text('New')),
                        DropdownMenuItem(value: 'good', child: Text('Good')),
                        DropdownMenuItem(value: 'fair', child: Text('Fair')),
                        DropdownMenuItem(
                            value: 'needs_repair',
                            child: Text('Needs repair')),
                      ],
                      onChanged: (v) =>
                          setState(() => _condition = v ?? 'good'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        prefixIcon: Icon(Icons.countertops_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(Icons.description_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Submit donation'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// PROFILE
/// ------------------------------------------------------------

class ProfilePage extends StatelessWidget {
  final String role;
  final String? userId;

  const ProfilePage({
    super.key,
    required this.role,
    required this.userId,
  });

  Future<void> _signOut(BuildContext context) async {
    await AuthService.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    if (userId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('You are browsing as guest.'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: CareCenterRepository.usersCol.doc(userId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final name = data['name'] ?? 'User';
        final email = data['email'] ?? '';
        final phone = data['phone'] ?? '';
        final id = data['nationalId'] ?? '';
        final preferred = data['preferredContact'] ?? '';
        final roleStr = data['role'] ?? role;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      child: Icon(Icons.person_rounded, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.toString(),
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Role: $roleStr',
                            style: tt.bodyMedium
                                ?.copyWith(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email.toString(),
                            style: tt.bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_rounded),
                    title: const Text('Personal information'),
                    subtitle: Text('ID: $id\nPhone: $phone'),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading:
                        const Icon(Icons.notifications_active_rounded),
                    title: const Text('Preferred contact'),
                    subtitle: Text(preferred.toString()),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: const Text('Rental & donation history'),
                    subtitle: const Text('View your full history'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserHistoryPage(
                            userId: userId!,
                            role: roleStr,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Sign out'),
                onTap: () => _signOut(context),
              ),
            ),
          ],
        );
      },
    );
  }
}

class UserHistoryPage extends StatelessWidget {
  final String userId;
  final String role;
  const UserHistoryPage({super.key, required this.userId, required this.role});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your history'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Rentals'),
              Tab(text: 'Donations'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            UserRentalsPage(userId: userId, initialShowHistory: true),
            DonationsPage(role: role, userId: userId),
          ],
        ),
      ),
    );
  }
}
