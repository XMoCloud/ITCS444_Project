import 'package:flutter/material.dart';

class CustomToast extends StatelessWidget {
  final String title;
  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback? onDismiss;

  const CustomToast({
    super.key,
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}

class ToastService {
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    Color color = Colors.blue,
    IconData icon = Icons.info_outline_rounded,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top,
        left: 0,
        right: 0,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: -100, end: 0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, value),
              child: child,
            );
          },
          child: SafeArea(
            child: CustomToast(
              title: title,
              message: message,
              color: color,
              icon: icon,
              onDismiss: () {
                entry.remove();
              },
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    Future.delayed(duration, () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  static void showSuccess(BuildContext context, String title, String message) {
    show(
      context,
      title: title,
      message: message,
      color: Colors.green,
      icon: Icons.check_circle_outline_rounded,
    );
  }

  static void showError(BuildContext context, String title, String message) {
    show(
      context,
      title: title,
      message: message,
      color: Colors.red,
      icon: Icons.error_outline_rounded,
    );
  }

  static void showWarning(BuildContext context, String title, String message) {
    show(
      context,
      title: title,
      message: message,
      color: Colors.orange,
      icon: Icons.warning_amber_rounded,
    );
  }
  
  static void showInfo(BuildContext context, String title, String message) {
    show(
      context,
      title: title,
      message: message,
      color: Colors.blue,
      icon: Icons.info_outline_rounded,
    );
  }
}
