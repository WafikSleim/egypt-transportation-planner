import '../../data/models/place_models.dart';
import '../entities/trip_endpoint.dart';

/// The Model side for the **OSM place index**.
///
/// A seam of its own, not more methods on `PlannerRepository`. That one
/// carries transit data under TfC's licence; this one carries OpenStreetMap
/// under ODbL, and the two must not end up in one derived dataset. Keeping
/// them behind two interfaces means nothing can join them by accident — a
/// ViewModel that wants both has to ask for both, and shows them as two
/// labelled things.
abstract class PlacesRepository {
  /// Fuzzy substring search over names, in either script, whatever the app's
  /// language is — `lang` only chooses which name comes back.
  ///
  /// [near] orders results by distance when given. **It must be a point the
  /// passenger already chose** (the other end of the trip), never a location
  /// fix taken to sort this list: location is read on demand, for a stated
  /// purpose, and a search box is not one.
  Future<PlacesResponse> search(String query, {GeoPoint? near, int limit});

  /// Names the point a map pin settled on. An empty list is a real answer —
  /// much of Greater Cairo has no addressing a stranger could use.
  Future<PlacesResponse> reverse(GeoPoint at, {int radiusMetres, int limit});
}
