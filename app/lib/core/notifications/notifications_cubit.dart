import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'notification_kind.dart';
import 'notification_service.dart';

class NotificationsState extends Equatable {
  const NotificationsState({required this.permission, required this.allowed});

  /// What the OS currently says. `null` before the first read — the switches
  /// are drawn from the stored preferences either way, so nothing has to wait
  /// on a platform call.
  final NotificationPermission? permission;

  final Map<NotificationKind, bool> allowed;

  bool get granted => permission?.isAllowed ?? false;

  /// The OS will not show the prompt again, so the only way back is the
  /// system settings screen.
  bool get blockedInSettings =>
      permission is NotificationsDenied &&
      (permission! as NotificationsDenied).permanently;

  @override
  List<Object?> get props => [permission, allowed];
}

/// ViewModel for the notification switches, and for the permission flow that
/// every feature scheduling a notification goes through.
///
/// App-wide rather than per screen, like `SettingsCubit`: the same three
/// switches are the opt-out on the About screen and the gate that #22 and
/// #24 ask before they schedule anything.
class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit(this._service)
    : super(
        NotificationsState(
          permission: null,
          allowed: _service.preferences.all,
        ),
      );

  final NotificationService _service;

  /// True when the OS would show a prompt, so this app's own explanation is a
  /// warning rather than an interruption. Same rule as "use my location":
  /// explain before the prompt, and only when there is going to be one.
  Future<bool> get needsExplaining async =>
      !(await _service.permission()).isAllowed;

  Future<void> refresh() async {
    final permission = await _service.permission();
    emit(
      NotificationsState(
        permission: permission,
        allowed: _service.preferences.all,
      ),
    );
  }

  /// Asks the OS. Call it after the explanation, never before.
  Future<bool> askPermission() async {
    final permission = await _service.request();
    emit(
      NotificationsState(
        permission: permission,
        allowed: _service.preferences.all,
      ),
    );
    return permission.isAllowed;
  }

  Future<void> setAllowed(NotificationKind kind, {required bool allowed}) async {
    await _service.preferences.setAllowed(kind, allowed: allowed);
    emit(
      NotificationsState(
        permission: state.permission,
        allowed: _service.preferences.all,
      ),
    );
  }

  Future<void> openSettings() => _service.openSettings();
}
