import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

import '../../data/models/place_models.dart';
import '../../domain/entities/trip_endpoint.dart';

/// Which name a place is missing, when the one on screen is the other one.
///
/// The server says so in `name_is_fallback` + `name_language`; this is that
/// pair turned into the one thing a screen has to decide. Never a
/// transliteration — a wrong Arabic name is worse than an honest English one.
enum NameNote {
  /// Shown in Latin because OSM has no `name:ar`. The common case here.
  noArabicName,

  /// Shown in Arabic because OSM has no English name, on an English screen.
  noEnglishName,
}

/// One place, ready to draw. No wire field is left to interpret.
class PlaceVm extends Equatable {
  const PlaceVm({
    required this.name,
    required this.nameDirection,
    required this.categoryLabel,
    required this.endpoint,
    this.area,
    this.distanceM,
    this.nameNote,
  });

  /// The name for the requested language, or the other one with [nameNote]
  /// set — whichever the server resolved.
  final String name;

  /// Direction of [name] itself, from the server's `name_language`. A Latin
  /// name inside an Arabic page is set left-to-right; the characters are not
  /// sniffed on the client.
  final TextDirection nameDirection;

  /// Already localised by the server.
  final String categoryLabel;
  final String? area;

  /// Straight-line metres from the point the search was ordered by. Null when
  /// no such point was sent — shown as nothing, never as zero.
  final int? distanceM;

  final NameNote? nameNote;

  /// What picking this row returns.
  final TripEndpoint endpoint;

  @override
  List<Object?> get props => [
    name,
    nameDirection,
    categoryLabel,
    area,
    distanceM,
    nameNote,
    endpoint,
  ];
}

/// Maps `/places` rows to [PlaceVm]. Like [TripPresenter], it maps and does
/// not derive: every decision it reflects was made by the server.
class PlacePresenter {
  const PlacePresenter({required this.languageCode});

  final String languageCode;

  bool get _isArabic => languageCode == 'ar';

  PlaceVm place(PlaceResult p) {
    final direction = p.nameLanguage == 'en'
        ? TextDirection.ltr
        : TextDirection.rtl;
    return PlaceVm(
      name: p.name,
      nameDirection: direction,
      categoryLabel: _isArabic ? p.category.labelAr : p.category.labelEn,
      area: p.area,
      distanceM: p.distanceM,
      nameNote: !p.nameIsFallback
          ? null
          : p.nameLanguage == 'en'
          ? NameNote.noArabicName
          : NameNote.noEnglishName,
      endpoint: TripEndpoint.fromPlace(p, label: p.name),
    );
  }

  List<PlaceVm> places(Iterable<PlaceResult> results) =>
      results.map(place).toList(growable: false);
}
