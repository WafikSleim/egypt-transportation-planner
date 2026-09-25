import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/generated/app_localizations.dart';
import 'notifications_cubit.dart';

/// Explain, then ask. The one way this app requests notification permission.
///
/// Lifted out of a screen on purpose. `_MyLocation` on the search page does
/// exactly this for location — explain first, and only when the OS is going
/// to prompt — and #22, #23 and #24 each have their own in-context moment to
/// ask from: turning a reminder on, starting to follow a trip. A second
/// hand-rolled version of this flow in each of them is how one of them ends
/// up showing the bare OS prompt with no reason given, which is the prompt
/// most likely to be refused and never offered again.
///
/// Returns whether notifications may now be shown.
Future<bool> askToNotify(BuildContext context) async {
  final cubit = context.read<NotificationsCubit>();

  if (!await cubit.needsExplaining) return true;
  if (!context.mounted) return false;

  final agreed = await _explain(context);
  // Not now means not now. No second prompt later in the same session, and
  // nothing scheduled behind their back.
  if (agreed != true) return false;

  return cubit.askPermission();
}

Future<bool?> _explain(BuildContext context) {
  final l = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.notificationsWhyTitle),
      content: Text(l.notificationsWhyBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.notNow),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.notificationsWhyContinue),
        ),
      ],
    ),
  );
}
