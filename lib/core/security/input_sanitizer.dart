class InputSanitizer {
  /// Limpia texto general removiendo etiquetas HTML/Script
  static String sanitizeText(String input) {
    final trimmed = input.trim();
    // Elimina tags HTML para prevenir XSS en renderizados
    return trimmed.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// Limpia las consultas del buscador de músicos
  static String sanitizeSearchQuery(String input) {
    final clean = sanitizeText(input);
    // Elimina caracteres comodín que distorsionen ILIKE o LIKE en PostgreSQL
    return clean.replaceAll(RegExp(r'[%_]'), '');
  }

  /// Valida y limpia números telefónicos
  static String? sanitizePhoneNumber(String phone) {
    // Deja únicamente dígitos y el símbolo '+'
    final cleanDigits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    
    // Validación básica de longitud internacional
    if (cleanDigits.length < 7 || cleanDigits.length > 15) {
      return null;
    }
    return cleanDigits;
  }
}