/// Hand-curated "zonas de influencia" (metro-area groupings) for the
/// directory's "Cercanías" search.
///
/// Problem this solves: a musician who lives in a commuter town next to a
/// bigger city (e.g. Lebrija, next to Bucaramanga) will naturally type their
/// own town as [Musician.city]. If they forget to also add the anchor city
/// to their `coverage_cities`, a contractor searching "cerca de mí" from
/// Bucaramanga never sees them — even though a 20-minute drive separates
/// them. Rather than reaching for a paid maps/geocoding API for an MVP, we
/// keep a small static table of known metro clusters and treat every city
/// in the same cluster as a match for each other. This is intentionally a
/// plain Dart constant — same pattern as [VallenatoInstruments]/
/// [MusicGenres]/[MusicianServices] — instead of a Supabase table, so
/// widening the search costs zero extra network round-trips and zero extra
/// infrastructure; it only needs updating when the directory expands into a
/// new region, which is rare and easy to review in a PR.
abstract final class CityZones {
  static const Map<String, List<String>> _zones = {
    'Área Metropolitana de Bucaramanga': [
      'Bucaramanga',
      'Floridablanca',
      'Girón',
      'Piedecuesta',
      'Lebrija',
      'Rionegro',
      'El Playón',
    ],
    // Add more clusters here as the directory grows into new
    // departments/cities (e.g. Valledupar y su área de influencia, Cúcuta,
    // Barranquilla). Each entry is a flat, symmetric group: every city in
    // the list is treated as a match for every other city in the same list.
  };

  /// Every city in the same zone as [city] (including [city] itself),
  /// case-insensitively matched against the curated table above. Cities not
  /// found in any zone fall back to a single-element list containing just
  /// the (trimmed) input — i.e. exactly today's behavior, so this is a
  /// strict widening, never a narrowing, of the existing search.
  static List<String> expand(String city) {
    final trimmed = city.trim();
    if (trimmed.isEmpty) return const [];

    for (final citiesInZone in _zones.values) {
      final belongsToZone = citiesInZone.any(
        (candidate) => candidate.toLowerCase() == trimmed.toLowerCase(),
      );
      if (belongsToZone) return citiesInZone;
    }
    return [trimmed];
  }
}
