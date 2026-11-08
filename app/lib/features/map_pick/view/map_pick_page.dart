import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/map/map_view.dart';
import '../../../core/map/tile_source.dart';
import '../../../core/presentation/place_presenter.dart';
import '../../../core/text/bidi.dart';
import '../../../core/text/distance_text.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/attribution_note.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../domain/entities/trip_endpoint.dart';
import '../../../domain/repositories/places_repository.dart';
import '../../../domain/repositories/planner_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../view_model/map_pick_cubit.dart';
import '../view_model/map_pick_state.dart';

/// Drag the map under a fixed centre pin, and say what is there (P-18).
///
/// Pops with a [TripEndpoint] at the **pin's coordinates**, or null if the
/// user backs out or asks to search by name instead.
///
/// Large parts of Greater Cairo have no addressing a stranger could use, so
/// pointing is often genuinely easier than naming. The cost of pointing is
/// that the name this screen shows comes from somewhere with gaps — so it is
/// labelled as OpenStreetMap's, apart from the nearest stop, which is the
/// transit data's. Neither is allowed to imply the other.
class MapPickPage extends StatelessWidget {
  const MapPickPage({
    super.key,
    required this.planner,
    required this.places,
    this.initialCenter,
    this.source,
    this.surfaceBuilder,
  });

  final PlannerRepository planner;
  final PlacesRepository places;

  /// Where the pin starts. Defaults to Tahrir; the picker passes the other end
  /// of the trip when there is one, so a destination pick opens near where the
  /// passenger already is.
  final GeoPoint? initialCenter;

  /// Injected by tests, which have no platform view to draw into.
  final MapTileSource? source;
  final MapSurfaceBuilder? surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final start =
        initialCenter ?? const GeoPoint(MapCamera.cairoLat, MapCamera.cairoLon);

    return BlocProvider(
      // The opening position is asked about too. The map only reports where
      // the camera *came to rest*, and a passenger who confirms without
      // touching the map is confirming the place it opened on.
      create: (_) => MapPickCubit(
        places: places,
        planner: planner,
        presenter: PlacePresenter(languageCode: lang),
      )..pointSettled(start),
      child: _MapPickView(
        start: start,
        source: source,
        surfaceBuilder: surfaceBuilder,
      ),
    );
  }
}

class _MapPickView extends StatelessWidget {
  const _MapPickView({
    required this.start,
    required this.source,
    required this.surfaceBuilder,
  });

  final GeoPoint start;
  final MapTileSource? source;
  final MapSurfaceBuilder? surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    return Scaffold(
      appBar: AppBar(title: Text(l.mapPickTitle)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A fraction, not a fixed height, for the reason the coverage map
            // gives: the text under the map is the honest part.
            final mapHeight = (constraints.maxHeight * 0.42).clamp(
              180.0,
              380.0,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: mapHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        bottom: BorderSide(color: p.line),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Semantics(
                            label: l.mapPickMapLabel,
                            child: CityMapView(
                              source: source,
                              surfaceBuilder: surfaceBuilder,
                              showCoverage: false,
                              initialCenter: start,
                              initialZoom: MapCamera.pickZoom,
                              onSettled: (point) => context
                                  .read<MapPickCubit>()
                                  .pointSettled(point),
                            ),
                          ),
                        ),
                        const _CentrePin(),
                      ],
                    ),
                  ),
                ),
                const Expanded(child: _Panel()),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The fixed pin. Drawn over the map's centre and never moved: the *map*
/// moves under it, so what the pin points at is always what the screen shows
/// at its middle. Ignores touches, or it would swallow every drag.
class _CentrePin extends StatelessWidget {
  const _CentrePin();

  @override
  Widget build(BuildContext context) {
    final size = 40.r;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            label: AppLocalizations.of(context).mapPickPinLabel,
            // Lifted by half its height so the **tip**, not the middle of the
            // glyph, sits on the map's centre — the point that is looked up.
            child: Transform.translate(
              offset: Offset(0, -size / 2),
              child: Icon(
                Icons.location_on,
                size: size,
                color: context.colors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;

    return BlocBuilder<MapPickCubit, MapPickState>(
      builder: (context, state) {
        final ready = state is MapPickReady;
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  Insets.lg,
                  Insets.lg,
                  Insets.lg,
                  Insets.sm,
                ),
                children: [
                  Text(l.mapPickInstruction, style: theme.titleLarge),
                  SizedBox(height: Insets.md),
                  switch (state) {
                    MapPickIdle() ||
                    MapPickLoading() => _Looking(text: l.mapPickLooking),
                    MapPickOutside() => HonestyPanel(
                      text: l.mapPickOutside,
                      severity: HonestySeverity.warning,
                      icon: Icons.crop_free,
                    ),
                    MapPickReady() => _Ready(state: state),
                  },
                  SizedBox(height: Insets.md),
                  // Always there, not only when a name is: the screen's main
                  // claim is that the name is OSM's and may be wrong, and it
                  // has to be visible before somebody trusts it, not after.
                  HonestyPanel(
                    text: l.mapPickOsmNote,
                    severity: HonestySeverity.warning,
                    icon: Icons.translate,
                  ),
                  SizedBox(height: Insets.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, A11y.minTapTarget),
                      ),
                      child: Text(l.mapPickByName),
                    ),
                  ),
                ],
              ),
            ),
            // Outside the scroll, so the one thing this screen is for is never
            // below the fold of a small phone with the text turned up.
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                Insets.lg,
                Insets.sm,
                Insets.lg,
                Insets.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: ready ? () => _confirm(context) : null,
                  child: Text(l.mapPickConfirm),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirm(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<MapPickCubit>();
    final s = cubit.state;
    if (s is! MapPickReady) return;
    final endpoint = cubit.confirmedEndpoint(
      unnamedLabel: l.mapPickUnnamedLabel(
        coordinateText(s.point.lat, s.point.lon),
      ),
    );
    if (endpoint != null) Navigator.of(context).pop(endpoint);
  }
}

class _Looking extends StatelessWidget {
  const _Looking({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16.r,
          height: 16.r,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: Insets.md),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

/// The two answers, **as two labelled things**: the name (OSM) and the nearest
/// stop (TfC). Each can be present, empty, or unavailable on its own.
class _Ready extends StatelessWidget {
  const _Ready({required this.state});

  final MapPickReady state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;
    final theme = Theme.of(context).textTheme;
    final place = state.place;
    final stop = state.nearestStop;

    return Container(
      padding: EdgeInsetsDirectional.all(Insets.lg),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (place != null) ...[
            Text(
              bidiIsolate(place.name),
              textDirection: place.nameDirection,
              style: theme.titleMedium,
            ),
            SizedBox(height: Insets.xs),
            Text(
              [
                bidiIsolate(place.categoryLabel),
                if (place.area != null) bidiIsolate(place.area!),
              ].join(' · '),
              style: theme.bodySmall,
            ),
            if (place.nameNote != null) ...[
              SizedBox(height: Insets.xs),
              Text(switch (place.nameNote!) {
                NameNote.noArabicName => l.placeNoArabicName,
                NameNote.noEnglishName => l.placeNoEnglishName,
              }, style: theme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ] else if (state.nameUnavailable) ...[
            Text(l.mapPickNameUnavailable, style: theme.titleMedium),
          ] else ...[
            // A real answer, not a failure: OSM has nothing named here.
            Text(l.mapPickNoName, style: theme.titleMedium),
            SizedBox(height: Insets.xs),
            Text(l.mapPickNoNameHelp, style: theme.bodySmall),
          ],
          SizedBox(height: Insets.xs),
          // The point itself is always shown. For a spot with no name it is
          // the only handle there is; for a named one it shows exactly what
          // the trip will be planned from.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              coordinateText(state.point.lat, state.point.lon),
              style: TextStyle(
                fontFamily: Faces.mono,
                fontSize: 12,
                color: p.ink2,
              ),
            ),
          ),
          Divider(height: Insets.xl, color: p.line),
          Text(l.mapPickNearestStop, style: theme.labelMedium),
          SizedBox(height: Insets.xs),
          if (stop != null)
            Text(
              '${bidiIsolate(stop.name)} · ${distanceText(l, stop.distanceM)}',
              textDirection: isLatinName(stop.name) ? TextDirection.ltr : null,
              style: theme.titleMedium,
            )
          else if (state.stopUnavailable)
            Text(l.mapPickStopUnavailable, style: theme.bodyMedium)
          else
            // "No stop within a kilometre" is a finding: it says the point may
            // not be reachable, which is what this line is here to let a
            // passenger judge before committing.
            Text(
              l.mapPickNoStopNearby(distanceText(l, state.stopRadiusM)),
              style: theme.bodyMedium,
            ),
          // Two datasets, two credits — each only when something from it is
          // on this screen.
          if (place != null && state.placesAttribution != null)
            AttributionNote(state.placesAttribution!),
          if (stop != null && state.stopsAttribution != null)
            AttributionNote(state.stopsAttribution!),
        ],
      ),
    );
  }
}
