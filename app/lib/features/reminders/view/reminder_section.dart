import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/notifications/notification_permission_prompt.dart';
import '../../../core/text/formatting.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/reminder_ledger.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../view_model/reminder_cubit.dart';

/// "Remind me before this trip" (#22), on the itinerary screen.
///
/// The estimate caveat is on screen next to the button, not only inside the
/// notification: someone deciding whether to rely on a reminder is owed the
/// reason it is approximate *before* they set it, and the notification then
/// repeats it for whoever sees only the notification.
class ReminderSection extends StatelessWidget {
  const ReminderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<ReminderCubit>();
    final p = context.colors;

    return BlocBuilder<ReminderCubit, ReminderState>(
      builder: (context, state) {
        final reminder = state.reminder;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.reminderTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: Insets.sm),
            if (!cubit.canOffer)
              Text(
                l.reminderCachedUnavailable,
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...[
              Text(
                l.reminderEstimate,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: Insets.md),
              if (reminder != null) ...[
                Text(
                  l.reminderSetLine(
                    clockTime(reminder.remindAt),
                    reminder.leadMinutes,
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                SizedBox(height: Insets.md),
                // The cancel button sits beside the thing it cancels, on the
                // screen where the reminder was made. The notification's own
                // button turns the whole kind off, which is a different act.
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(A11y.minTapTarget),
                  ),
                  icon: const Icon(Icons.notifications_off_outlined, size: 18),
                  label: Text(l.reminderCancel),
                  onPressed: cubit.cancel,
                ),
              ] else
                FilledButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(l.notifyDepartureReminder),
                  onPressed: () => _choose(context, cubit, state.lead),
                ),
              if (_message(l, state.outcome) case final message?) ...[
                SizedBox(height: Insets.sm),
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: p.ink),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  String? _message(AppLocalizations l, ReminderOutcome outcome) =>
      switch (outcome) {
        ReminderOutcome.none || ReminderOutcome.set => null,
        ReminderOutcome.cancelled => l.reminderCancelled,
        ReminderOutcome.timePassed => l.reminderTimePassed,
        ReminderOutcome.tooMany => l.reminderTooMany,
        ReminderOutcome.notificationsOff => l.reminderNotificationsOff,
      };

  Future<void> _choose(
    BuildContext context,
    ReminderCubit cubit,
    int initial,
  ) async {
    final lead = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _LeadPicker(cubit: cubit, initial: initial),
    );
    if (lead == null || !context.mounted) return;

    // Explain and ask here, in the moment the passenger turns a reminder on -
    // never at launch. A refusal still goes through `set`, which reports it.
    await askToNotify(context);
    await cubit.set(lead);
  }
}

class _LeadPicker extends StatelessWidget {
  const _LeadPicker({required this.cubit, required this.initial});

  final ReminderCubit cubit;
  final int initial;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.all(Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.reminderPickTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: Insets.sm),
            for (final minutes in ReminderLedger.leadChoices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: A11y.minTapTarget,
                title: Text(l.durationMinutes(minutes)),
                selected: minutes == initial,
                // A lead that would put the reminder in the past is shown but
                // not offered, rather than hidden: the list stays the same
                // four choices every time.
                enabled: cubit.leadFits(minutes),
                trailing: minutes == initial
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(minutes),
              ),
          ],
        ),
      ),
    );
  }
}
