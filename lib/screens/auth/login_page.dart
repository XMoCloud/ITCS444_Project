import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/repository.dart';
import '../../ui/custom_toast.dart';
import '../../ui/loading_animation.dart';
import '../dashboard/main_shell.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
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
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _animController.dispose();
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
        ToastService.showError(context, 'Error', 'Login failed');
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
      ToastService.showError(
        context,
        'Error',
        e.message ?? 'Authentication error',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastService.showError(context, 'Error', 'Unexpected error');
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

  Future<void> _resetPassword() async {
    final emailCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email address to receive a password reset link.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_rounded),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) {
                ToastService.showError(
                  dialogContext,
                  'Error',
                  'Please enter your email',
                );
                return;
              }

              // 1. Local Validation
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailRegex.hasMatch(email)) {
                ToastService.showError(
                  dialogContext,
                  'Error',
                  'Invalid email format',
                );
                return;
              }

              // Don't close dialog yet

              try {
                // 2. Check if user exists in Firestore (to bypass Firebase Auth enumeration protection)
                final userQuery = await CareCenterRepository.usersCol
                    .where('email', isEqualTo: email)
                    .limit(1)
                    .get();

                if (userQuery.docs.isEmpty) {
                  if (dialogContext.mounted) {
                    ToastService.showError(
                      dialogContext,
                      'Error',
                      'No account found with this email.',
                    );
                  }
                  return;
                }

                // Close dialog now that we verified user exists
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                // 3. Send Reset Email
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: email,
                );
                if (mounted) {
                  ToastService.showSuccess(
                    context,
                    'Success',
                    'Password reset email sent to $email',
                  );
                }
              } on FirebaseAuthException catch (e) {
                if (mounted) {
                  // Handle specific error codes
                  String message = e.message ?? 'Failed to send reset email';
                  if (e.code == 'user-not-found') {
                    message = 'No user found with this email address.';
                  } else if (e.code == 'invalid-email') {
                    message = 'The email address is badly formatted.';
                  }
                  ToastService.showError(context, 'Error', message);
                }
              } catch (_) {
                if (mounted) {
                  ToastService.showError(context, 'Error', 'Unexpected error');
                }
              }
            },
            child: const Text('Send Link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LoadingOverlay(
      isLoading: _loading,
      message: 'Signing in...',
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Hero(
                        tag: 'app_logo',
                        child: Icon(
                          Icons.health_and_safety_rounded,
                          size: 80,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Care Center',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rental • Donation • Exchange',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 40),
                      Card(
                        elevation: 4,
                        shadowColor: cs.primary.withOpacity(0.2),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 32,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Welcome Back',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Please sign in to continue',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.grey[600]),
                                  ),
                                ),
                                const SizedBox(height: 24),
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
                                    if (!v.contains('@'))
                                      return 'Invalid email';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscure,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    suffixIcon: IconButton(
                                      onPressed: () {
                                        setState(() => _obscure = !_obscure);
                                      },
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
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
                                    onPressed: _resetPassword,
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _login,
                                    child: const Text('Sign in'),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Divider(color: Colors.grey[200]),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                      ),
                                      child: Text(
                                        'or',
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(color: Colors.grey[200]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _guest,
                                    child: const Text('Continue as guest'),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "Don't have an account? ",
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                    TextButton(
                                      onPressed: _openRegister,
                                      child: const Text('Create account'),
                                    ),
                                  ],
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
          ),
        ),
      ),
    );
  }
}
