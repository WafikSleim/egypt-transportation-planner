import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../network/api_failure.dart';
import '../theme/mode_theme.dart';
import '../theme/tokens.dart';

/// A failure, explained in terms of what the user can do about it.
///
/// Three cases, because only three lead to different advice. "Something went
/// wrong" with a retry button is not an explanation, and a server outage is
/// not the user's fault — saying so is the difference between an app that
/// feels broken and one that feels honest.
class AppErrorView extends StatelessWidget {
  const AppErrorView({super.key, required this.failure, this.onRetry});

  final ApiFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    final (title, help) = switch (failure.kind) {
      FailureKind.offline => (l.errorOffline, l.errorOfflineHelp),
      FailureKind.serverDown => (l.errorServerDown, l.errorServerDownHelp),
      FailureKind.badRequest => (l.errorUnexpected, failure.detail ?? ''),
      FailureKind.unexpected => (l.errorUnexpected, failure.detail ?? ''),
    };

    return Center(
      child: Padding(
        padding: EdgeInsetsDirectional.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failure.kind == FailureKind.offline
                  ? Icons.wifi_off_rounded
                  : Icons.cloud_off_rounded,
              size: 34,
              color: p.ink3,
            ),
            SizedBox(height: Insets.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (help.isNotEmpty) ...[
              SizedBox(height: Insets.sm),
              Text(
                help,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: Insets.xl),
              TextButton(onPressed: onRetry, child: Text(l.tryAgain)),
            ],
          ],
        ),
      ),
    );
  }
}
