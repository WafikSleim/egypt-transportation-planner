import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
import '../view_model/search_cubit.dart';
import '../view_model/search_state.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchCubit(),
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
              SizedBox(height: Insets.lg),
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
