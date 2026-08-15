/// Musical genres a musician can be tagged with. Kept in one place so the
/// dashboard's filter chips and the "Mi Estado" genre dropdown never drift
/// apart.
abstract final class MusicGenres {
  static const List<String> all = ['Vallenato', 'Tropical', 'Popular'];

  static const String fallback = 'Vallenato';
}
