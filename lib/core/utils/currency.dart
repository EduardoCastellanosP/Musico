import 'package:flutter/services.dart';

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

/// Same grouping, Tarima client-facing style, e.g. `1800000` ->
/// `COP 1.800.000` — matches the marketplace design's card price label,
/// which drops the `$`/`/h` shorthand the admin side uses.
String formatCopPrice(double value) => 'COP ${_groupThousands(value)}';

/// [formatCopPrice] with a suffix that matches how
/// `provider_services.pricing_type` says the number should be read —
/// `fixed` (a package/event rate) gets none, since "COP 800.000" already
/// reads as a flat price on its own.
String formatCopPriceForPricingType(double value, String pricingType) {
  final suffix = switch (pricingType) {
    'per_night' => '/noche',
    'fixed' => '',
    _ => '/h',
  };
  return '${formatCopPrice(value)}$suffix';
}

/// User-facing label for the price INPUT field in `CreateServiceModal`,
/// e.g. "Precio por hora" — kept next to [formatCopPriceForPricingType] so
/// both stay in sync with the same three `pricing_type` values.
String priceFieldLabel(String pricingType) => switch (pricingType) {
  'per_night' => 'Precio por noche',
  'fixed' => 'Precio del paquete',
  _ => 'Precio por hora',
};

/// Live thousands-separator mask for a COP price `TextFormField` — e.g.
/// typing `1000000` displays `1.000.000`. The `$` prefix stays a separate
/// `InputDecoration.prefixText` (never part of the editable text), so this
/// only ever rewrites the dot separators as digits change; the field's
/// `controller.text` itself keeps the grouped-with-dots string, which is
/// why submit call sites use [parseCopInput] rather than `double.tryParse`
/// directly.
class CopPriceInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();

    final formatted = _groupThousands(double.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Grouped digits with no `$`/suffix — what [CopPriceInputFormatter] shows
/// in the field itself, used to seed a price controller's initial text
/// (e.g. `_EditServiceForm` preloading an existing `price_per_hour`).
String formatCopInputValue(double value) => _groupThousands(value);

/// Inverse of what [CopPriceInputFormatter] displays in the field — strips
/// the dot separators back out so the raw number can be parsed and saved.
double? parseCopInput(String text) => double.tryParse(text.replaceAll('.', '').trim());

/// `price × advancePercentage / 100` — the deposit a client pays to
/// secure a booking (Sistema Anti-Fuga). Centralized here instead of
/// computed inline in each caller (`CreateServiceModal`'s live preview,
/// `ServiceDetailScreen`'s "Condiciones de reserva") so the real
/// advance-payment flow (not built yet) reuses this exact formula rather
/// than duplicating it — see `supabase/schema.sql` §27 for why the peso
/// amount is never itself stored.
double advanceAmountFor(double price, int advancePercentage) => price * advancePercentage / 100;
