import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../ui/custom_toast.dart';
import '../../ui/loading_animation.dart';
import '../dashboard/main_shell.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _preferredContact = 'phone';
  String _role = 'renter';
  bool _loading = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    _animController.dispose();
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
      ToastService.showError(
        context,
        'Error',
        e.message ?? 'Registration error',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastService.showError(context, 'Error', 'Unexpected error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return LoadingOverlay(
      isLoading: _loading,
      message: 'Creating account...',
      child: Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    elevation: 4,
                    shadowColor: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Join Care Center',
                              style: tt.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Fill in your details to get started',
                              style: tt.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Enter name'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Enter email';
                                }
                                if (!v.contains('@')) return 'Invalid email';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _idCtrl,
                              decoration: const InputDecoration(
                                labelText: 'National ID',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _preferredContact,
                              decoration: const InputDecoration(
                                labelText: 'Preferred contact',
                                prefixIcon: Icon(
                                  Icons.notifications_active_outlined,
                                ),
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
                              onChanged: (v) => setState(
                                () => _preferredContact = v ?? 'phone',
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _role,
                              decoration: const InputDecoration(
                                labelText: 'Role',
                                prefixIcon: Icon(Icons.security_outlined),
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
                              onChanged: (v) =>
                                  setState(() => _role = v ?? 'renter'),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty)
                                  return 'Enter password';
                                if (v.length < 6) return 'Min 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _register,
                                child: const Text('Create account'),
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
          ),
        ),
      ),
    );
  }
}
