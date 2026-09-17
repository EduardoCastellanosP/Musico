String _groupThousands(double value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formats a COP amount with dot thousand-separators, e.g. `350000` ->
/// `$350.000/h` — used by the admin moderation cards/detail modal, where
/// `provider_services.price_per_hour` is shown next to per-hour context.
String formatCopPerHour(double value) => '\$${_groupThousands(value)}/h';

/// Same grouping, Tarima client-facing style, e.g. `1800000` ->
/// `COP 1.800.000` — matches the marketplace design's card price label,
/// which drops the `$`/`/h` shorthand the admin side uses.
String formatCopPrice(double value) => 'COP ${_groupThousands(value)}';
