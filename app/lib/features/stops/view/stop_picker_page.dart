import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/presentation/trip_presenter.dart';
import '../../../core/text/bidi.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/attribution_note.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../core/widgets/mode_badge.dart';
import '../../../data/repositories/trip_history.dart';
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
    this.history,
  });

  final String title;
  final PlannerRepository repository;
  final TripPresenter presenter;

  /// Optional: without it the picker simply opens on the typing hint, which
  /// is also what a first-ever launch looks like.
  final TripHistory? history;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          StopSearchCubit(repository: repository, presenter: presenter),
      child: _StopPickerView(title: title, history: history),
    );
  }
}

class _StopPickerView extends StatelessWidget {
  const _StopPickerView({required this.title, this.history});

  final String title;
  final TripHistory? history;

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
            Expanded(child: _Results(history: history)),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({this.history});

  final TripHistory? history;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    return BlocBuilder<StopSearchCubit, StopSearchState>(
      builder: (context, state) {
        switch (state) {
          case StopSearchIdle():
            final recents = history?.recents() ?? const [];
            return recents.isEmpty
                ? _Hint(text: l.startTyping)
                : _Recents(recents: recents, history: history!);

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

    // One node, announced as a button: the stop's name, how many routes call
    // there, and its mode chips are one answer to one question, not four
    // stops for a screen reader to walk through.
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
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

/// What the picker shows before anything is typed.
///
/// Recents earn the space only because the alternative is an empty screen
/// with a hint on it. They are on-device and the panel says so, because a
/// list of where somebody goes is the most sensitive thing this app holds —
/// and the only honest way to show it is to say where it lives.
class _Recents extends StatefulWidget {
  const _Recents({required this.recents, required this.history});

  final List<TripEndpoint> recents;
  final TripHistory history;

  @override
  State<_Recents> createState() => _RecentsState();
}

class _RecentsState extends State<_Recents> {
  late List<TripEndpoint> _recents = widget.recents;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    if (_recents.isEmpty) return _Hint(text: l.startTyping);

    return ListView(
      padding: EdgeInsetsDirectional.only(bottom: Insets.xl),
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            Insets.lg,
            Insets.sm,
            Insets.sm,
            Insets.sm,
          ),
          child: Row(
            children: [
              Text(
                l.recentPlaces,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await widget.history.clearRecents();
                  if (mounted) setState(() => _recents = const []);
                },
                child: Text(l.clearRecents),
              ),
            ],
          ),
        ),
        for (final endpoint in _recents)
          MergeSemantics(
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(endpoint),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: A11y.minTapTarget,
                  ),
                  child: Padding(
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: Insets.lg,
                      vertical: Insets.md,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded, size: 18.r, color: p.ink3),
                        SizedBox(width: Insets.md),
                        Expanded(
                          child: Text(
                            bidiIsolate(endpoint.label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsetsDirectional.all(Insets.lg),
          child: Text(
            l.recentsOnDevice,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
