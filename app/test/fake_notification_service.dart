import 'package:egypt_transport/core/notifications/notification_copy.dart';
import 'package:egypt_transport/core/notifications/notification_kind.dart';
import 'package:egypt_transport/core/notifications/notification_service.dart';

/// A notifier that records instead of notifying.
///
/// It overrides only [deliver] and [retract], which is the point: the gate on
/// [NotificationService.post] and the opt-out inside
/// [NotificationService.handleResponse] are the real ones, so a test against
/// this fake is a test of the code that ships.
final class FakeNotificationService extends NotificationService {
  FakeNotificationService({
    required super.preferences,
    super.copy = _copy,
    this.permitted = const NotificationsAllowed(),
  });

  /// What the OS says. A test can refuse, refuse permanently, or allow.
  NotificationPermission permitted;

  int requests = 0;
  int settingsOpened = 0;

  final delivered = <NotificationRequest>[];
  final retracted = <int>[];

  @override
  Future<NotificationPermission> permission() async => permitted;

  @override
  Future<NotificationPermission> request() async {
    requests++;
    await preferences.markAsked();
    return permitted;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> deliver(
    NotificationRequest request,
    NotificationText text, {
    required String silenceLabel,
  }) async {
    delivered.add(request);
    lastText = text;
  }

  @override
  Future<void> retract(int id) async => retracted.add(id);

  NotificationText? lastText;

  /// Drives the same path the platform callback does.
  Future<void> tap(
    NotificationKind kind, {
    int slot = 0,
    String? actionId,
  }) => handleResponse(kind, slot: slot, actionId: actionId);

  static NotificationCopy _copy() => const _StubCopy();
}

/// Words are not what these tests are about; `screens_smoke_test.dart` is
/// where the real strings have to exist.
class _StubCopy implements NotificationCopy {
  const _StubCopy();

  @override
  NotificationText forRequest(NotificationRequest request) =>
      NotificationText(title: request.kind.name, body: '');

  @override
  String silenceAction(NotificationKind kind) => 'off';

  @override
  String channelName(NotificationKind kind) => kind.name;
}
