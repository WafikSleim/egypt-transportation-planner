import 'package:equatable/equatable.dart';

import '../../core/storage/key_value_store.dart';

/// A departure reminder the passenger set and that has not fired yet (#22).
///
/// This is what the OS is holding on this app's behalf, written down so the
/// itinerary screen can say "we will remind you at 08:05" and offer to cancel
/// it. The OS keeps its own copy of the *words*; this keeps what the app needs
/// to show and to take back. It is on the phone only, like everything in
/// `TripHistory`, and holds a trip label and two times - no coordinates.
class PlannedReminder extends Equatable {
  const PlannedReminder({
    required this.slot,
    required this.tripKey,
    required this.tripLabel,
    required this.departureAt,
    required this.remindAt,
    required this.leadMinutes,
  });

  /// 0 to [ReminderLedger.maxPending] - 1. Becomes the notification's slot,
  /// so two reminders are two notifications and cancelling one leaves the
  /// other alone.
  final int slot;

  /// Identifies the itinerary, so reopening it finds its reminder.
  final String tripKey;

  final String tripLabel;

  /// The **estimated** departure, from a recorded schedule.
  final DateTime departureAt;

  final DateTime remindAt;
  final int leadMinutes;

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'trip_key': tripKey,
    'trip_label': tripLabel,
    'departure_at': departureAt.toIso8601String(),
    'remind_at': remindAt.toIso8601String(),
    'lead_minutes': leadMinutes,
  };

  static PlannedReminder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final slot = raw['slot'];
    final key = raw['trip_key'];
    final label = raw['trip_label'];
    final departure = DateTime.tryParse('${raw['departure_at']}');
    final remind = DateTime.tryParse('${raw['remind_at']}');
    final lead = raw['lead_minutes'];
    if (slot is! int ||
        key is! String ||
        label is! String ||
        departure == null ||
        remind == null ||
        lead is! int) {
      return null;
    }
    return PlannedReminder(
      slot: slot,
      tripKey: key,
      tripLabel: label,
      departureAt: departure,
      remindAt: remind,
      leadMinutes: lead,
    );
  }

  @override
  List<Object?> get props => [
    slot,
    tripKey,
    tripLabel,
    departureAt,
    remindAt,
    leadMinutes,
  ];
}

/// Pending reminders, and the lead time the passenger last chose.
///
/// Reads are synchronous, like [TripHistory] and for the same reason: the
/// itinerary screen has to know in its first frame whether to offer "remind
/// me" or "cancel the reminder".
class ReminderLedger {
  ReminderLedger(this._store);

  static const _key = 'reminders';
  static const _leadKey = 'reminder_lead';

  /// The lead times offered, in minutes. A microbus does not keep a
  /// timetable, so the figure is how early to be told rather than how early
  /// to be ready - a short list is easier to choose from than a stepper.
  static const leadChoices = [5, 10, 15, 30];
  static const defaultLead = 10;

  /// Enough for the trips someone has coming up. Also bounds the OS's alarm
  /// table, and gives each reminder a slot of its own below 1000.
  static const maxPending = 10;

  final KeyValueStore _store;

  /// Reminders that have yet to fire. Anything whose time has passed is
  /// dropped on read: the OS has shown it or lost it, and either way there is
  /// nothing left to cancel.
  List<PlannedReminder> pending({DateTime? now}) {
    final cutoff = now ?? DateTime.now();
    final items = _store.readJson(_key)?['items'];
    final all = items is List
        ? items.map(PlannedReminder.fromJson).whereType<PlannedReminder>()
        : const Iterable<PlannedReminder>.empty();
    return all.where((r) => r.remindAt.isAfter(cutoff)).toList(growable: false);
  }

  PlannedReminder? forTrip(String tripKey, {DateTime? now}) =>
      pending(now: now).where((r) => r.tripKey == tripKey).firstOrNull;

  /// The lowest unused slot, or null when [maxPending] are already set.
  int? freeSlot({DateTime? now}) {
    final used = pending(now: now).map((r) => r.slot).toSet();
    for (var slot = 0; slot < maxPending; slot++) {
      if (!used.contains(slot)) return slot;
    }
    return null;
  }

  /// Setting a second reminder for the same trip replaces the first.
  Future<void> put(PlannedReminder reminder, {DateTime? now}) {
    final kept = pending(now: now).where((r) => r.tripKey != reminder.tripKey);
    return _write([...kept, reminder]);
  }

  Future<void> remove(String tripKey, {DateTime? now}) {
    final kept = pending(now: now).where((r) => r.tripKey != tripKey);
    return _write(kept);
  }

  int get lastLead {
    final value = _store.readJson(_leadKey)?['minutes'];
    return value is int && leadChoices.contains(value) ? value : defaultLead;
  }

  Future<void> rememberLead(int minutes) =>
      _store.writeJson(_leadKey, {'minutes': minutes});

  Future<void> _write(Iterable<PlannedReminder> reminders) => _store.writeJson(
    _key,
    {'items': reminders.map((r) => r.toJson()).toList()},
  );
}
