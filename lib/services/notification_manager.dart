import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../firebase_services.dart';
import '../ui/custom_toast.dart';

class NotificationManager {
  static Timer? _timer;
  static StreamSubscription? _notificationSubscription;

  static void init(BuildContext context, String userId, String role) {
    // Start periodic check for overdue items
    _startPeriodicCheck(userId, role);
    
    // Listen for new notifications to show toast
    _listenForNotifications(context, userId);
  }

  static void dispose() {
    _timer?.cancel();
    _notificationSubscription?.cancel();
  }

  static void _listenForNotifications(BuildContext context, String userId) {
    _notificationSubscription?.cancel();
    
    // We capture the start time to filter out old notifications manually
    // This avoids needing a composite index on (userId, createdAt)
    final startTime = DateTime.now();
    
    _notificationSubscription = CareCenterRepository.notificationsCol
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          
          // Only show notifications created after we started listening
          if (createdAt != null && createdAt.isAfter(startTime)) {
            final title = data['title'] ?? 'Notification';
            final message = data['message'] ?? '';
            final type = data['type'] ?? 'info';
            
            // Show toast
            if (type == 'overdue' || type == 'maintenance') {
              ToastService.showWarning(context, title, message);
            } else if (type == 'new_donation') {
              ToastService.showInfo(context, title, message);
            } else {
              ToastService.showInfo(context, title, message);
            }
          }
        }
      }
    });
  }

  static void _startPeriodicCheck(String userId, String role) {
    _timer?.cancel();
    // Run immediately then every minute
    _checkOverdue(userId, role);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _checkOverdue(userId, role));
  }

  static Future<void> _checkOverdue(String userId, String role) async {
    // Only check if user has active rentals or is admin
    // Actually, we need to check for EVERYONE who has rentals, but client-side we can only check for the current user
    // unless we are admin?
    // If we are admin, we could check ALL rentals, but that might be heavy.
    // Let's stick to checking for the CURRENT user's rentals.
    // AND if admin, maybe check for overdue items to notify admin?
    
    // 1. Check for User's approaching/overdue rentals
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    
    final myRentals = await CareCenterRepository.reservationsCol
        .where('renterId', isEqualTo: userId)
        .where('status', isEqualTo: 'checked_out')
        .get();

    for (final doc in myRentals.docs) {
      final data = doc.data();
      final endDate = (data['endDate'] as Timestamp).toDate();
      final reservationId = doc.id;
      final equipmentName = data['equipmentName'] ?? 'Equipment';

      bool shouldNotify = false;
      String type = '';
      String title = '';
      String message = '';

      if (now.isAfter(endDate)) {
        // Overdue
        type = 'overdue';
        title = 'Rental Overdue';
        message = 'Your rental for $equipmentName is overdue. Please return it.';
        shouldNotify = true;
      } else if (endDate.isBefore(tomorrow)) {
        // Approaching (less than 1 day left)
        type = 'approaching';
        title = 'Return Due Soon';
        message = 'Your rental for $equipmentName is due tomorrow.';
        shouldNotify = true;
      }

      if (shouldNotify) {
        // Check if we already sent a notification for this specific state recently?
        // To keep it simple: Check if a notification of this type exists for this reservation
        // created in the last 24 hours.
        
        // Query without createdAt filter to avoid composite index requirement
        final recentNotifs = await CareCenterRepository.notificationsCol
            .where('userId', isEqualTo: userId)
            .where('reservationId', isEqualTo: reservationId)
            .where('type', isEqualTo: type)
            .get();

        // Filter in memory
        final hasRecent = recentNotifs.docs.any((doc) {
          final data = doc.data();
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          if (createdAt == null) return false;
          return createdAt.isAfter(now.subtract(const Duration(hours: 24)));
        });

        if (!hasRecent) {
          await CareCenterRepository.addNotification(
            userId: userId,
            type: type,
            title: title,
            message: message,
            reservationId: reservationId,
            equipmentId: data['equipmentId'],
          );
          
          // If overdue, also notify admins if not done recently
          if (type == 'overdue') {
             await CareCenterRepository.notifyAdmins(
               type: 'admin_overdue',
               title: 'Equipment Overdue',
               message: '${data['renterName']} has overdue rental: $equipmentName',
               reservationId: reservationId,
               equipmentId: data['equipmentId'],
             );
          } else if (type == 'approaching') {
             await CareCenterRepository.notifyAdmins(
               type: 'admin_approaching',
               title: 'Rental Due Soon',
               message: '${data['renterName']} has rental due soon: $equipmentName',
               reservationId: reservationId,
               equipmentId: data['equipmentId'],
             );
          }
        }
      }
    }
  }
}
