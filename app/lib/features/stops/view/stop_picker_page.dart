import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/presentation/trip_presenter.dart';
import '../../../core/text/bidi.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/attribution_note.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../core/widgets/mode_badge.dart';
import '../../../domain/entities/trip_endpoint.dart';
import '../../../domain/repositories/planner_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../view_model/stop_search_cubit.dart';
import '../view_model/stop_search_state.dart';

/// Pick a stop. Pops with a [TripEndpoint], or null if the user backs out.
///
/// Stops only for now. The full picker in `design/app-prototype.html` also
/// covers places, recents and picking on the map; places need the `places`
/// table that is not built yet, so offering an empty tab here would promise
/// something the backend cannot answer.
class StopPickerPage extends StatelessWidget {
  const StopPickerPage({
    super.key,
    required this.title,
    required this.repository,
    required this.presenter,
  });

  final String title;
  final PlannerRepository repository;
  final TripPresenter presenter;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          StopSearchCubit(repository: repository, presenter: presenter),
      child: _StopPickerView(title: title),
    );
  }
}

class _StopPickerView extends StatelessWidget {
  const _StopPickerView({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                Insets.lg,
                Insets.sm,
                Insets.lg,
                Insets.md,
              ),
              child: TextField(
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.stopSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (v) =>
                    context.read<StopSearchCubit>().queryChanged(v),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: Insets.lg),
              // Stated, not left to be discovered. Stop search is prefix-based
              // server-side: منيب finds nothing, المنيب finds sixteen. A user
              // who types the short form and sees an empty list concludes the
              // app is broken, not that they typed a suffix.
              child: HonestyPanel(
                text: l.stopSearchPrefixNote,
                icon: Icons.lightbulb_outline_rounded,
              ),
            ),
            SizedBox(height: Insets.md),
            const Expanded(child: _Results()),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    return BlocBuilder<StopSearchCubit, StopSearchState>(
      builder: (context, state) {
        switch (state) {
          case StopSearchIdle():
            return _Hint(text: l.startTyping);

          case StopSearchLoading():
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );

          case StopSearchFailed(:final failure):
            return AppErrorView(failure: failure);

          case StopSearchLoaded(
            :final results,
            :final truncated,
            :final totalMatches,
            :final attribution,
          ):
            if (results.isEmpty) return _Hint(text: l.stopSearchEmpty);

            final anyLatin = results.any((r) => isLatinName(r.stop.name));

            return ListView.separated(
              padding: EdgeInsetsDirectional.only(bottom: Insets.xl),
              itemCount: results.length + 1,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: p.line,
                indent: Insets.lg,
                endIndent: Insets.lg,
              ),
              itemBuilder: (context, index) {
                if (index == results.length) {
                  return Padding(
                    padding: EdgeInsetsDirectional.all(Insets.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (truncated)
                          Text(
                            l.stopSearchTruncated(totalMatches),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (anyLatin) ...[
                          SizedBox(height: Insets.sm),
                          Text(
                            l.honestyLatinName,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        AttributionNote(attribution),
                      ],
                    ),
                  );
                }
                return _StopRow(result: results[index]);
              },
            );
        }
      },
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.result});

  final StopResultVm result;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;
    final stop = result.stop;
    final latin = isLatinName(stop.name);

    return InkWell(
      onTap: () => Navigator.of(context).pop(TripEndpoint.fromStop(stop)),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A stop mark, distinct from the place mark the picker will use
            // once places exist: a stop is where a vehicle calls, a place is
            // where you're going, and they behave differently in search.
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.modeColors.microbus.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.signpost_outlined,
                size: 17,
                color: context.modeColors.microbus,
              ),
            ),
            SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bidiIsolate(stop.name),
                    textDirection: latin ? TextDirection.ltr : null,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: Insets.xs),
                  Text(
                    l.routesServed(stop.routeCount),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (result.badges.isNotEmpty) ...[
                    SizedBox(height: Insets.sm),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.xs,
                      children: [
                        for (final badge in result.badges)
                          ModeBadge(badge, compact: true),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Points the way the page reads, which is not the same in both
            // locales - Material does not mirror this glyph for us.
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              color: p.ink3,
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsetsDirectional.all(Insets.xl),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
