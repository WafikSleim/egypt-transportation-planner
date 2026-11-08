import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/map/tile_source.dart';
import '../../../core/map/map_view.dart';
import '../../../core/presentation/place_presenter.dart';
import '../../../core/presentation/trip_presenter.dart';
import '../../../core/text/bidi.dart';
import '../../../core/text/distance_text.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/attribution_note.dart';
import '../../../core/widgets/endpoint_mark.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../core/widgets/mode_badge.dart';
import '../../../data/repositories/trip_history.dart';
import '../../../domain/entities/trip_endpoint.dart';
import '../../../domain/repositories/places_repository.dart';
import '../../../domain/repositories/planner_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map_pick/view/map_pick_page.dart';
import '../view_model/picker_cubit.dart';
import '../view_model/picker_state.dart';

/// Pick where a trip starts or ends. Pops with a [TripEndpoint], or null if
/// the user backs out.
///
/// **One field over three sources**: stops (TfC's transit data), places
/// (OpenStreetMap) and what is on the phone already. They are asked in
/// parallel and shown in one list, each with its own mark and its own credit —
/// the sources differ in licence and in how they match, and the screen says
/// both rather than leaving the second to be discovered.
class PickerPage extends StatelessWidget {
  const PickerPage({
    super.key,
    required this.title,
    required this.planner,
    required this.places,
    this.history,
    this.near,
    this.mapSource,
    this.mapSurfaceBuilder,
  });

  final String title;
  final PlannerRepository planner;
  final PlacesRepository places;

  /// Optional: without it the picker opens on the typing hint, which is also
  /// what a first-ever launch looks like.
  final TripHistory? history;

  /// Orders places by distance from here. **Only ever a point the passenger
  /// already chose** — the other end of the trip — never a location fix taken
  /// for this search. Null means "ordered by relevance", and the screen does
  /// not claim otherwise.
  final GeoPoint? near;

  /// Test seams for the map-pick screen this one can open.
  final MapTileSource? mapSource;
  final MapSurfaceBuilder? mapSurfaceBuilder;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return BlocProvider(
      create: (_) => PickerCubit(
        planner: planner,
        places: places,
        tripPresenter: TripPresenter(languageCode: lang),
        placePresenter: PlacePresenter(languageCode: lang),
        history: history,
        near: near,
      ),
      child: _PickerView(
        title: title,
        planner: planner,
        places: places,
        near: near,
        mapSource: mapSource,
        mapSurfaceBuilder: mapSurfaceBuilder,
      ),
    );
  }
}

class _PickerView extends StatelessWidget {
  const _PickerView({
    required this.title,
    required this.planner,
    required this.places,
    required this.near,
    required this.mapSource,
    required this.mapSurfaceBuilder,
  });

  final String title;
  final PlannerRepository planner;
  final PlacesRepository places;
  final GeoPoint? near;
  final MapTileSource? mapSource;
  final MapSurfaceBuilder? mapSurfaceBuilder;

  Future<void> _pickOnMap(BuildContext context) async {
    final picked = await Navigator.of(context).push<TripEndpoint>(
      MaterialPageRoute(
        builder: (_) => MapPickPage(
          planner: planner,
          places: places,
          initialCenter: near,
          source: mapSource,
          surfaceBuilder: mapSurfaceBuilder,
        ),
      ),
    );
    if (picked != null && context.mounted) Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        // The field stays put; everything under it scrolls as one list. The
        // note and the map button used to be fixed above the results, and at
        // 200% text on a small phone they alone filled the screen.
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
                  hintText: l.pickerHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (v) => context.read<PickerCubit>().queryChanged(v),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsetsDirectional.only(bottom: Insets.xl),
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: Insets.lg,
                    ),
                    // Stated, not left to be discovered. The two indexes match
                    // differently — stops from the start of a name, places anywhere
                    // in it — and a user who types منيب and sees no stop concludes
                    // the app is broken, not that they typed a suffix.
                    child: HonestyPanel(
                      text: l.pickerMatchNote,
                      icon: Icons.lightbulb_outline_rounded,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: Insets.lg,
                      vertical: Insets.sm,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => _pickOnMap(context),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(l.pickerOnMap),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, A11y.minTapTarget),
                        ),
                      ),
                    ),
                  ),
                  _Results(showsNear: near != null),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.showsNear});

  final bool showsNear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return BlocBuilder<PickerCubit, PickerState>(
      builder: (context, state) {
        switch (state) {
          case PickerIdle():
            return state.isEmpty
                ? _Hint(text: l.startTyping)
                : _Idle(state: state);

          case PickerLoading():
            return Padding(
              padding: EdgeInsetsDirectional.all(Insets.xl),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );

          case PickerFailed(:final failure):
            return AppErrorView(failure: failure);

          case PickerLoaded():
            return _Loaded(state: state, showsNear: showsNear);
        }
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.showsNear});

  final PickerLoaded state;
  final bool showsNear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;
    final theme = Theme.of(context).textTheme;

    final stops = state.showsStops ? state.stops : const <StopResultVm>[];
    final places = state.showsPlaces ? state.places : const <PlaceVm>[];
    final anyLatinStop = stops.any((r) => isLatinName(r.stop.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: Insets.lg),
          child: Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.xs,
            children: [
              for (final (filter, label) in [
                (PickerFilter.all, l.pickerFilterAll),
                (PickerFilter.stops, l.pickerFilterStops),
                (PickerFilter.places, l.pickerFilterPlaces),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: state.filter == filter,
                  onSelected: (_) =>
                      context.read<PickerCubit>().setFilter(filter),
                ),
            ],
          ),
        ),
        // A source that could not answer is said once, quietly, above the
        // list. It is not an error screen: the other source is still there.
        if (state.placesUnavailable && state.showsPlaces)
          _Quiet(text: l.pickerPlacesUnavailable),
        if (state.stopsUnavailable && state.showsStops)
          _Quiet(text: l.pickerStopsUnavailable),
        if (state.isEmpty &&
            !state.placesUnavailable &&
            !state.stopsUnavailable)
          _Hint(text: l.pickerEmpty),
        for (final entry in state.entries) ...[
          _Separator(color: p.line),
          switch (entry) {
            StopEntry(:final result) => _StopRow(result: result),
            PlaceEntry(:final place) => _PlaceRow(place: place),
          },
        ],
        Padding(
          padding: EdgeInsetsDirectional.all(Insets.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.showsStops && state.stopsTruncated)
                Text(
                  l.stopSearchTruncated(state.stopsTotal),
                  style: theme.bodySmall,
                ),
              if (state.showsPlaces && state.placesTruncated)
                Text(
                  l.placeSearchTruncated(state.placesTotal),
                  style: theme.bodySmall,
                ),
              if (showsNear && places.isNotEmpty) ...[
                SizedBox(height: Insets.sm),
                Text(l.pickerPlacesOrdered, style: theme.bodySmall),
              ],
              if (anyLatinStop) ...[
                SizedBox(height: Insets.sm),
                Text(l.honestyLatinName, style: theme.bodySmall),
              ],
              // Two datasets, two credits, each shown only when something
              // from it is on screen.
              if (state.showsStops && state.stopsAttribution != null)
                AttributionNote(state.stopsAttribution!),
              if (state.showsPlaces && state.placesAttribution != null)
                AttributionNote(state.placesAttribution!),
            ],
          ),
        ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: color, indent: Insets.lg, endIndent: Insets.lg);
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(
      Insets.lg,
      Insets.md,
      Insets.lg,
      Insets.sm,
    ),
    child: HonestyPanel(text: text, icon: Icons.cloud_off_outlined),
  );
}

/// A tappable row: the mark, the words, a chevron. One node to a screen
/// reader, announced as a button — the name, what it is and how far are one
/// answer to one question, not four stops to walk through.
class _Row extends StatelessWidget {
  const _Row({required this.onTap, required this.mark, required this.body});

  final VoidCallback onTap;
  final Widget mark;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: A11y.minTapTarget),
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mark,
                  SizedBox(width: Insets.md),
                  Expanded(child: body),
                  // Points the way the page reads, which is not the same in
                  // both locales - Material does not mirror this glyph.
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
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.result});

  final StopResultVm result;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final stop = result.stop;
    final latin = isLatinName(stop.name);

    return _Row(
      onTap: () => Navigator.of(context).pop(TripEndpoint.fromStop(stop)),
      mark: const EndpointMark(EndpointKind.stop),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bidiIsolate(stop.name),
            textDirection: latin ? TextDirection.ltr : null,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: Insets.xs),
          Text(
            '${l.pickerStopKind} · ${l.routesServed(stop.routeCount)}',
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
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place});

  final PlaceVm place;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;

    // Category, district, distance — each isolated, because the district can
    // be Latin inside an Arabic line and would otherwise reorder around the
    // separator.
    final detail = [
      bidiIsolate(place.categoryLabel),
      if (place.area != null) bidiIsolate(place.area!),
      if (place.distanceM != null) distanceText(l, place.distanceM!),
    ].join(' · ');

    return _Row(
      onTap: () => Navigator.of(context).pop(place.endpoint),
      mark: const EndpointMark(EndpointKind.place),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bidiIsolate(place.name),
            textDirection: place.nameDirection,
            style: theme.titleMedium,
          ),
          SizedBox(height: Insets.xs),
          Text(detail, style: theme.bodySmall),
          if (place.nameNote != null) ...[
            SizedBox(height: Insets.xs),
            // Said, not hidden and never transliterated: a wrong Arabic name
            // is worse than an honest English one.
            Text(switch (place.nameNote!) {
              NameNote.noArabicName => l.placeNoArabicName,
              NameNote.noEnglishName => l.placeNoEnglishName,
            }, style: theme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
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

/// What the picker shows before anything is typed: recents, then the stops and
/// places from saved trips.
///
/// On-device, and the panel says so — a list of where somebody goes is the
/// most sensitive thing this app holds, and the only honest way to show it is
/// to say where it lives.
class _Idle extends StatelessWidget {
  const _Idle({required this.state});

  final PickerIdle state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.recents.isNotEmpty) ...[
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              Insets.lg,
              Insets.sm,
              Insets.sm,
              Insets.sm,
            ),
            child: Row(
              children: [
                Text(l.recentPlaces, style: theme.labelMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => context.read<PickerCubit>().clearRecents(),
                  child: Text(l.clearRecents),
                ),
              ],
            ),
          ),
          for (final e in state.recents) _EndpointRow(endpoint: e),
        ],
        if (state.saved.isNotEmpty) ...[
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              Insets.lg,
              Insets.md,
              Insets.lg,
              Insets.sm,
            ),
            child: Text(l.pickerSavedHeading, style: theme.labelMedium),
          ),
          for (final e in state.saved) _EndpointRow(endpoint: e),
        ],
        Padding(
          padding: EdgeInsetsDirectional.all(Insets.lg),
          child: Text(l.recentsOnDevice, style: theme.bodySmall),
        ),
      ],
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.endpoint});

  final TripEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    return _Row(
      onTap: () => Navigator.of(context).pop(endpoint),
      mark: EndpointMark(endpoint.kind),
      body: Padding(
        // Optically centres a one-line title against the 32px mark.
        padding: EdgeInsetsDirectional.only(top: Insets.xs),
        child: Text(
          bidiIsolate(endpoint.label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
