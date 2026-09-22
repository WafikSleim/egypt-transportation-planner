import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/notifications/notification_kind.dart';
import '../../../core/notifications/notification_permission_prompt.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/notifications_cubit.dart';
import '../../../core/settings/settings_cubit.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/attribution_note.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../data/models/models.dart';
import '../../../domain/repositories/planner_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/view/coverage_map_page.dart';

/// Attribution, coverage, and the things this app will not do.
///
/// The attribution is fetched rather than hard-coded, so the wording in the
/// app cannot drift from the wording the licence requires. Everything else
/// here is a limitation stated up front: fares are absent on purpose, metro
/// stop names are in English because the data has no Arabic, and coverage
/// stops at Greater Cairo.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  Attribution? _attribution;
  ApiFailure? _failure;

  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState: the repository is read from an inherited widget, and
    // this is the callback where that is legal. The flag keeps it to one
    // request rather than one per dependency change.
    if (_requested) return;
    _requested = true;
    _load(context.read<PlannerRepository>());
  }

  Future<void> _load(PlannerRepository repository) async {
    try {
      final a = await repository.attribution();
      if (mounted) setState(() => _attribution = a);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _failure = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;
    final settings = context.watch<SettingsCubit>().state;

    return BlocProvider(
      // Created here rather than at the root of the app: the switches are the
      // only thing in the build that needs it today, and #22 and #24 will
      // each provide it at their own screen the same way.
      create: (_) =>
          NotificationsCubit(context.read<NotificationService>())..refresh(),
      child: Scaffold(
        appBar: AppBar(title: Text(l.aboutTitle)),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsetsDirectional.all(Insets.lg),
            children: [
              Text(l.aboutIntro, style: Theme.of(context).textTheme.bodyLarge),
              SizedBox(height: Insets.lg),
              _Point(text: l.aboutNonProfit),
              _Point(text: l.aboutCoverage),
              // The coverage sentence above is abstract until you can see the
              // box. This is the map's only entry point today — there is no
              // map on the planning screens yet, because `/plan` returns no leg
              // geometry to draw. See features/map/view/coverage_map_page.dart.
              Padding(
                padding: EdgeInsetsDirectional.only(bottom: Insets.md),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(l.mapOpenCoverage),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CoverageMapPage(),
                      ),
                    ),
                  ),
                ),
              ),
              _Point(text: l.aboutFares),
              _Point(text: l.aboutMetroArabic),
              SizedBox(height: Insets.xl),
              Text(l.language, style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: Insets.sm),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'ar', label: Text(l.arabic)),
                  ButtonSegment(value: 'en', label: Text(l.english)),
                ],
                selected: {settings.locale.languageCode},
                onSelectionChanged: (s) =>
                    context.read<SettingsCubit>().setLanguage(s.first),
              ),
              SizedBox(height: Insets.xl),
              Text(l.theme, style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: Insets.sm),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l.themeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l.themeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(l.themeDark),
                  ),
                ],
                selected: {settings.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    context.read<SettingsCubit>().setThemeMode(s.first),
              ),
              SizedBox(height: Insets.xl),
              const _NotificationSwitches(),
              SizedBox(height: Insets.xl),
              Text(
                l.dataSource,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_attribution != null) ...[
                AttributionNote(_attribution!, compact: false),
              ] else if (_failure != null) ...[
                SizedBox(height: Insets.sm),
                Text(
                  l.errorServerDown,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ] else ...[
                SizedBox(height: Insets.md),
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: p.ink3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The in-app half of "disabling them is one tap away".
///
/// The other half is the action on the notification itself, which does the
/// same thing without the app being opened. Both land on
/// `NotificationPreferences`, so they cannot disagree.
class _NotificationSwitches extends StatelessWidget {
  const _NotificationSwitches();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return BlocBuilder<NotificationsCubit, NotificationsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.notificationsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: Insets.sm),
            HonestyPanel(text: l.notificationsOnlyThree),
            SizedBox(height: Insets.sm),
            for (final kind in NotificationKind.values)
              // The ongoing tracking notice has no switch, because it has no
              // off. It is described below instead of pretending otherwise.
              if (kind.canBeSilenced)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(_label(l, kind)),
                  value: state.allowed[kind] ?? true,
                  onChanged: (value) => context
                      .read<NotificationsCubit>()
                      .setAllowed(kind, allowed: value),
                ),
            SizedBox(height: Insets.sm),
            _Point(text: l.notificationsTrackingNotice),
            // Asked here only because no feature schedules anything yet. Once
            // #22 and #24 exist, the in-context moment is turning a reminder
            // on or starting to follow a trip — both of which call
            // `askToNotify` the same way this does.
            if (!state.granted && !state.blockedInSettings)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => askToNotify(context),
                  child: Text(l.notificationsAsk),
                ),
              ),
            if (state.blockedInSettings) ...[
              _Point(text: l.notificationsBlockedHelp),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () =>
                      context.read<NotificationsCubit>().openSettings(),
                  child: Text(l.openSettings),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _label(AppLocalizations l, NotificationKind kind) => switch (kind) {
    NotificationKind.departureReminder => l.notifyDepartureReminder,
    NotificationKind.tripInProgress => l.notifyTripInProgress,
    NotificationKind.nextStopAlert => l.notifyNextStopAlert,
    NotificationKind.postTripQuestion => l.notifyPostTripQuestion,
  };
}

class _Point extends StatelessWidget {
  const _Point({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsetsDirectional.only(top: Insets.sm, end: Insets.md),
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: p.ink3, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
