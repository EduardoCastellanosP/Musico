/// Services a profile can offer inside the directory. Kept in one place so
/// the "Mi Estado" services picker and the dynamic sections it toggles
/// ([MusicianServices.musician] -> instruments/genres,
/// [MusicianServices.technical] -> inventory field) never drift apart.
abstract final class MusicianServices {
  static const String musician = 'Músico';

  static const List<String> all = [
    musician,
    'Dj',
    'Sonido',
    'Ensayaderos',
    'Iluminación',
    'Ingeniero de sonido',
    'Roadie',
    'Presentador',
    'Animador',
    'Alquiler de equipos',
    'Alquiler de escenarios',
    'Alquiler de vehículos',
    'Catering',
    'Fotografia y video',
  ];

  /// Every service other than [musician] is treated as a technical service
  /// that shows the free-text inventory/description field instead of (or
  /// alongside) instruments and genres.
  static const List<String> technical = [
    'Sonido',
    'Ensayaderos',
    'Iluminación',
    'Transporte',
    // 'Alquiler de equipos',
  ];
}
