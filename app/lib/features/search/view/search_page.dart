import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/location/location_service.dart';
import '../../../core/presentation/trip_presenter.dart';
import '../../../core/text/bidi.dart';
import '../../../core/text/formatting.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../domain/entities/trip_endpoint.dart';
import '../../../domain/repositories/planner_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../about/view/about_page.dart';
import '../../results/view/results_page.dart';
import '../../stops/view/stop_picker_page.dart';
import '../view_model/my_location_cubit.dart';
import '../view_model/search_cubit.dart';
import '../view_model/search_state.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SearchCubit()),
        BlocProvider(
          create: (_) => MyLocationCubit(context.read<LocationService>()),
        ),
      ],
      child: const _SearchView(),
    );
  }
}

class _SearchView extends StatelessWidget {
  const _SearchView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l.aboutTitle,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsetsDirectional.all(Insets.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: Insets.sm),
              Text(
                l.searchTitle,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              SizedBox(height: Insets.xl),
              const _EndpointFields(),
              SizedBox(height: Insets.sm),
              const _MyLocation(),
              SizedBox(height: Insets.sm),
              const _DepartureRow(),
              SizedBox(height: Insets.xl),
              BlocBuilder<SearchCubit, SearchState>(
                builder: (context, state) => FilledButton(
                  onPressed: state.canSearch
                      ? () => _openResults(context, state)
                      : null,
                  child: Text(l.findTrips),
                ),
              ),
              SizedBox(height: Insets.xxl),
              HonestyPanel(text: l.honestyNoRealtime),
              SizedBox(height: Insets.lg),
              Text(
                l.aboutCoverage,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openResults(BuildContext context, SearchState state) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResultsPage(
          from: state.from!,
          to: state.to!,
          // "Now" is resolved here, not when the screen opened — sitting on
          // this form for ten minutes should not plan a trip from the past.
          departAt: state.resolvedDeparture(DateTime.now()),
        ),
      ),
    );
  }
}

class _EndpointFields extends StatelessWidget {
  const _EndpointFields();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(Radii.card),
              ),
              child: Column(
                children: [
                  _EndpointField(
                    label: l.fromLabel,
                    hint: l.fromHint,
                    value: state.from,
                    onPick: (e) => context.read<SearchCubit>().setFrom(e),
                  ),
                  Divider(
                    height: 1,
                    color: p.line,
                    indent: Insets.lg,
                    endIndent: 56,
                  ),
                  _EndpointField(
                    label: l.toLabel,
                    hint: l.toHint,
                    value: state.to,
                    onPick: (e) => context.read<SearchCubit>().setTo(e),
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              end: Insets.md,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: p.raise,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: l.swap,
                    icon: Icon(
                      Icons.swap_vert_rounded,
                      size: 20,
                      color: p.ink2,
                    ),
                    onPressed: (state.from == null && state.to == null)
                        ? null
                        : () => context.read<SearchCubit>().swap(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EndpointField extends StatelessWidget {
  const _EndpointField({
    required this.label,
    required this.hint,
    required this.value,
    required this.onPick,
  });

  final String label;
  final String hint;
  final TripEndpoint? value;
  final ValueChanged<TripEndpoint?> onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final filled = value != null;

    return InkWell(
      onTap: () async {
        final picked = await Navigator.of(context).push<TripEndpoint>(
          MaterialPageRoute(
            builder: (_) => StopPickerPage(
              title: label,
              presenter: TripPresenter(
                languageCode: Localizations.localeOf(context).languageCode,
              ),
              repository: context.read<PlannerRepository>(),
            ),
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          Insets.lg,
          Insets.md,
          56,
          Insets.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    // Isolated: a metro stop's Latin name inside an Arabic
                    // form would otherwise reorder around the label.
                    filled ? bidiIsolate(value!.label) : hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: filled ? p.ink : p.ink3,
                      fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        final when = state.departAt;
        return Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: p.ink2),
            SizedBox(width: Insets.sm),
            Text(
              when == null ? l.departNow : l.departAt(clockTime(when)),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: p.ink),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _pick(context, state),
              child: Text(l.changeTime),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, SearchState state) async {
    final now = DateTime.now();
    final base = state.departAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      // No past departures: the router would answer, and the answer
      // would be about a trip that has already gone.
      firstDate: DateTime(now.year, now.month, now.day),
      // The feeds' calendars run to the end of 2027; beyond that there is no
      // service defined and every answer would be an empty one.
      lastDate: DateTime(2027, 12, 31),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !context.mounted) return;
    context.read<SearchCubit>().setDeparture(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }
}

/// "Start from my location".
///
/// The whole flow is here rather than in the Cubit because every part of it
/// is a thing the user is told: why we want the fix, that it is approximate,
/// that we could not get it and what they can do instead. Only the decisions
/// live in [MyLocationCubit].
class _MyLocation extends StatelessWidget {
  const _MyLocation();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return BlocConsumer<MyLocationCubit, MyLocationState>(
      listenWhen: (_, state) => state is MyLocationResolved,
      listener: (context, state) {
        // The form owns the endpoints; this only hands one over.
        context.read<SearchCubit>().setFrom(
          (state as MyLocationResolved).endpoint,
        );
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: state is MyLocationLocating
                    ? null
                    : () => _start(context),
                icon: Icon(Icons.my_location_rounded, size: 18.r),
                label: Text(
                  state is MyLocationLocating ? l.locating : l.useMyLocation,
                ),
              ),
            ),
            if (state is MyLocationResolved && state.approximate) ...[
              SizedBox(height: Insets.sm),
              HonestyPanel(
                text: l.locationApproximate(state.accuracyM.round()),
                severity: HonestySeverity.warning,
              ),
            ],
            if (state is MyLocationOutsideCoverage) ...[
              SizedBox(height: Insets.sm),
              _Problem(
                title: l.locationOutsideCoverage,
                help: l.locationOutsideCoverageHelp,
              ),
            ],
            if (state is MyLocationFailed) ...[
              SizedBox(height: Insets.sm),
              _failureFor(context, state),
            ],
          ],
        );
      },
    );
  }

  Widget _failureFor(BuildContext context, MyLocationFailed state) {
    final l = AppLocalizations.of(context);

    return switch (state.reason) {
      LocationDenied(permanently: true) => _Problem(
        title: l.locationDeniedForever,
        help: l.locationDeniedHelp,
        actionLabel: l.openSettings,
        onAction: () => context.read<MyLocationCubit>().openSettings(),
      ),
      LocationDenied() => _Problem(
        title: l.locationDenied,
        help: l.locationDeniedHelp,
      ),
      LocationOff() => _Problem(title: l.locationOff, help: l.locationOffHelp),
      LocationUnavailable() || LocationFound() => _Problem(
        title: l.locationUnavailable,
        help: l.locationDeniedHelp,
      ),
    };
  }

  Future<void> _start(BuildContext context) async {
    final cubit = context.read<MyLocationCubit>();
    final label = AppLocalizations.of(context).myLocationName;

    // Explain before the OS prompt, and only when there is going to be one.
    // A permission dialog with no context is the one most likely to be
    // refused, and repeating the explanation once it is granted is nagging.
    if (await cubit.needsExplaining) {
      if (!context.mounted) return;
      final agreed = await _explain(context);
      if (agreed != true) return;
    }
    await cubit.locate(label: label);
  }

  Future<bool?> _explain(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.locationWhyTitle),
        content: Text(l.locationWhyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.notNow),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.locationWhyContinue),
          ),
        ],
      ),
    );
  }
}

/// Something did not work, said in terms of what to do instead.
class _Problem extends StatelessWidget {
  const _Problem({
    required this.title,
    required this.help,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String help;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsetsDirectional.all(Insets.md),
      decoration: BoxDecoration(
        color: p.raise,
        borderRadius: BorderRadius.circular(Radii.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: Insets.xs),
          Text(help, style: Theme.of(context).textTheme.bodySmall),
          if (actionLabel != null) ...[
            SizedBox(height: Insets.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ),
          ],
        ],
      ),
    );
  }
}
