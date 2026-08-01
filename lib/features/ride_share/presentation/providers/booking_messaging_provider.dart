import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider, StateProvider;

// =============== BOOKING MESSAGING STATE ===============

/// Current booking being discussed
final currentBookingIdProvider =
    StateProvider<int?>((ref) => null);

/// Booking status state: {bookingId: status}
final bookingStatusProvider = StateProvider<Map<int, String>>((ref) => {});

/// Check-in reminders sent: {bookingId: sent}
final checkInRemindersSentProvider =
    StateProvider<Map<int, bool>>((ref) => {});

/// Last booking update timestamp
final lastBookingUpdateProvider = StateProvider<DateTime?>((ref) => null);

/// Booking chat status: {bookingId: chatId}
final bookingChatMappingProvider =
    StateProvider<Map<int, String>>((ref) => {});

// =============== BOOKING EVENT HANDLERS ===============

/// Service for handling booking messaging events
class BookingMessagingNotifier extends StateNotifier<Map<int, String>> {
  BookingMessagingNotifier() : super({});

  /// Update booking status in local state
  void updateBookingStatus(int bookingId, String status) {
    state = {...state, bookingId: status};
  }

  /// Get current booking status
  String? getBookingStatus(int bookingId) {
    return state[bookingId];
  }

  /// Clear booking status
  void clearBookingStatus(int bookingId) {
    final newState = Map<int, String>.from(state);
    newState.remove(bookingId);
    state = newState;
  }
}

/// Booking status notifier provider
final bookingMessagingNotifierProvider =
    StateNotifierProvider<BookingMessagingNotifier, Map<int, String>>(
  (ref) => BookingMessagingNotifier(),
);

// =============== BOOKING NOTIFICATION HANDLERS ===============

/// Handle booking notification event
Future<void> handleBookingNotification(
  WidgetRef ref,
  int bookingId,
  String notificationType,
  Map<String, dynamic> data,
) async {
  switch (notificationType) {
    case 'status_change':
      ref
          .read(bookingMessagingNotifierProvider.notifier)
          .updateBookingStatus(bookingId, data['status'] ?? 'UNKNOWN');
      ref.read(lastBookingUpdateProvider.notifier).state = DateTime.now();
      break;

    case 'check_in_reminder':
      ref.read(checkInRemindersSentProvider.notifier).state = {
        ...ref.read(checkInRemindersSentProvider),
        bookingId: true,
      };
      break;

    case 'checkout_instructions':
      // Handle checkout
      break;

    case 'review_request':
      // Handle review request
      break;

    case 'special_offers':
      // Handle special offers
      break;
  }
}
