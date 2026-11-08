import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/notifications/notification_kind.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Opens the one post-trip question when its notification is tapped (#23).
///
/// Sits above the navigator, so it works from whichever screen the passenger
/// was on, and finds the navigator through [navigatorKey].
///
/// **Dismissible without answering, and asked once.** The dialog has three
/// ways out - yes, no and "not now" - and only the first two record anything.
/// Closing it, swiping the notification away, or never tapping it all leave
/// the question spent, because the cap is enforced where the notification is
/// posted (`NotificationService.post`), not here.
///
/// **A tap that starts a cold app is not handled.** The plugin hands over a
/// launch-time tap through a separate call this app does not make, so a
/// passenger who opens the app from the notification while it was closed
/// sees the app and no dialog. Losing a question nobody was owed is the safe
/// way to fail here; it is listed as unverified, as is everything that
/// needs a phone.
class PostTripListener extends StatefulWidget {
  const PostTripListener({
    super.key,
    required this.service,
    required this.navigatorKey,
    required this.child,
  });

  final NotificationService service;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<PostTripListener> createState() => _PostTripListenerState();
}

class _PostTripListenerState extends State<PostTripListener> {
  StreamSubscription<NotificationAction>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.actions.listen((action) {
      // A plain tap on the question. Its buttons are handled elsewhere: the
      // opt-out inside the service itself.
      if (action.kind == NotificationKind.postTripQuestion &&
          action.actionId == null) {
        _ask();
      }
    });
  }

  Future<void> _ask() async {
    final context = widget.navigatorKey.currentContext;
    final session = widget.service.preferences.lastPostTripSession;
    if (context == null || session == null) return;

    final l = AppLocalizations.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.notifyPostTripTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.postTripDialogQuestion),
            const SizedBox(height: 12),
            Text(
              l.postTripLocalOnly,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.notNow),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.postTripNo),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.postTripYes),
          ),
        ],
      ),
    );

    if (answer == null) return;
    await widget.service.preferences.recordPostTripAnswer(
      session,
      wasRight: answer,
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
