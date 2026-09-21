import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/presentation/trip_presenter.dart';
import '../../../core/presentation/view_models.dart';
import '../../../data/models/models.dart';
import '../../../core/text/bidi.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/attribution_note.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../domain/entities/trip_endpoint.dart';
import '../../../domain/repositories/planner_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../itinerary/view/itinerary_page.dart';
import '../view_model/results_cubit.dart';
import '../view_model/results_state.dart';
import '../widgets/itinerary_card.dart';

class ResultsPage extends StatelessWidget {
  const ResultsPage({
    super.key,
    required this.from,
    required this.to,
    required this.departAt,
  });

  final TripEndpoint from;
  final TripEndpoint to;
  final DateTime departAt;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ResultsCubit(
        repository: context.read<PlannerRepository>(),
        presenter: TripPresenter(
          languageCode: Localizations.localeOf(context).languageCode,
        ),
        from: from,
        to: to,
        departAt: departAt,
      )..load(),
      child: _ResultsView(from: from, to: to),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.from, required this.to});

  final TripEndpoint from;
  final TripEndpoint to;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.resultsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
                Insets.lg, 0, Insets.lg, Insets.md),
            child: Text(
              '${bidiIsolate(from.label)} ← ${bidiIsolate(to.label)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<ResultsCubit, ResultsState>(
          builder: (context, state) {
            switch (state) {
              case ResultsLoading():
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2),
                      SizedBox(height: Insets.lg),
                      Text(l.searching,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                );

              case ResultsFailed(:final failure):
                return AppErrorView(
                  failure: failure,
                  onRetry: () => context.read<ResultsCubit>().load(),
                );

              case ResultsLoaded(:final plan):
                return plan.hasResults
                    ? _ResultList(plan: plan)
                    : _NothingFound(plan: plan);
            }
          },
        ),
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.plan});

  final PlanVm plan;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsetsDirectional.all(Insets.lg),
      itemCount: plan.itineraries.length + 1,
      separatorBuilder: (_, _) => SizedBox(height: Insets.md),
      itemBuilder: (context, index) {
        if (index == plan.itineraries.length) {
          return Padding(
            padding: EdgeInsetsDirectional.only(top: Insets.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HonestyPanel(text: AppLocalizations.of(context).honestyNoRealtime),
                AttributionNote(plan.attribution),
              ],
            ),
          );
        }
        final itinerary = plan.itineraries[index];
        return ItineraryCard(
          itinerary: itinerary,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ItineraryPage(
                itinerary: itinerary,
                attribution: plan.attribution,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Nothing to show, and a reason for it.
///
/// This is not an error state. Either the trip is outside Greater Cairo —
/// the only place in Egypt with transit data at all — or nothing runs at the
/// hour asked for, or the only thing the router could offer was a walk, which
/// was dropped because a walk is not an answer.
///
/// This is also the emptiest screen a passenger will meet, and the most
/// common one outside the covered area — so it is written in Arabic like
/// every other screen. The server sends a `note_code`; the copy is ours. Its
/// English `note` is shown only when the code is missing or from a newer
/// server than this build knows, because an English sentence beats a blank
/// screen and loses to Arabic copy.
class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.plan});

  final PlanVm plan;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final (title, body) = switch (plan.noteCode) {
      NoteCode.outOfCoverage => (l.noCoverage, l.noCoverageBody),
      NoteCode.outsideServiceHours => (l.noServiceNow, l.noServiceBody),
      NoteCode.noRoute => (l.noRouteTitle, l.noRouteBody),
      NoteCode.unknown || null => (
          l.nothingFoundTitle,
          plan.note ?? l.walkOnlyExplain,
        ),
    };

    return ListView(
      padding: EdgeInsetsDirectional.all(Insets.lg),
      children: [
        SizedBox(height: Insets.xl),
        Icon(Icons.explore_off_outlined, size: 34, color: context.colors.ink3),
        SizedBox(height: Insets.lg),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        SizedBox(height: Insets.md),
        Text(
          // Isolated because the fallback is English prose carrying decimal
          // coordinates in brackets, which reorder inside an RTL column.
          bidiIsolate(body),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        SizedBox(height: Insets.xl),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.changeSearch),
        ),
        SizedBox(height: Insets.xl),
        AttributionNote(plan.attribution),
      ],
    );
  }
}
