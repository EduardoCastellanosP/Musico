import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../models/provider_service.dart';
import '../../../repositories/provider_service_repository.dart';
import '../blocking_progress_dialog.dart';
import 'service_cover_image.dart';

/// Categories a musician can list their commercial profile under — kept
/// local to this form rather than in `MusicianServices` (that constant is
/// for the social/directory "services" chips, a different concept from a
/// Tarima listing's single category). Public so [showEditServiceModal] can
/// reuse the same list instead of duplicating it.
const List<String> kServiceCategories = [
  'Agrupación',
  'Solista',
  'DJ',
  'Sonido',
  'Ensayadero',
  'Discoteca',
  'Catering',
  'Fotografía',
  'Estudio de grabación',
  'Decoracion y ambientación',
  'Transporte',
  'Otros',
];

const Color _kModalBackground = Color(0xFF0D0D12);
const Color _kModalAccent = Color(0xFFFFB703);
const Color _kModalTextSecondary = Color(0xFF9A9AA5);

/// The three ways `provider_services.price_per_hour` can be read — see
/// `supabase/schema.sql` §25's `pricing_type` column.
const String kPricingTypePerHour = 'per_hour';
const String kPricingTypeFixed = 'fixed';
const String kPricingTypePerNight = 'per_night';

/// Suggested `pricing_type` per category — the provider can still change
/// it via [_ChipSelector]. 'Agrupación' isn't in the task's per-type
/// lists; per-hour is the closest fit since it's the same kind of live-set
/// act as 'Solista'.
const Map<String, String> _kCategoryDefaultPricingType = {
  'Agrupación': kPricingTypePerHour,
  'Solista': kPricingTypePerHour,
  'Sonido': kPricingTypePerHour,
  'Fotografía': kPricingTypePerHour,
  'Transporte': kPricingTypePerHour,
  'Estudio de grabación': kPricingTypePerHour,
  'Catering': kPricingTypeFixed,
  'Decoracion y ambientación': kPricingTypeFixed,
  'Ensayadero': kPricingTypeFixed,
  'Otros': kPricingTypeFixed,
  'DJ': kPricingTypePerNight,
  'Discoteca': kPricingTypePerNight,
};

/// One optional extra attribute a category can collect — stored as
/// `values[key]` in `provider_services.details` (jsonb), a string for
/// plain text fields or a bool for [isBoolean] ones.
class DetailField {
  const DetailField(this.key, this.label, {this.isBoolean = false});

  final String key;
  final String label;
  final bool isBoolean;
}

/// Category → its extra optional fields, on top of [kUniversalDetailFields].
/// Categories not listed here (e.g. 'Agrupación', 'Ensayadero', 'Discoteca')
/// only get the universal ones.
const Map<String, List<DetailField>> kCategoryDetailFields = {
  'Solista': [
    DetailField('set_duration', 'Duración de sets/repertorio'),
  ],
  'DJ': [
    DetailField('set_duration', 'Duración de sets/repertorio'),
  ],
  'Sonido': [
    DetailField('capacity', 'Capacidad (aforo/m²)'),
    DetailField('includes_technician', 'Incluye técnico', isBoolean: true),
  ],
  'Fotografía': [
    DetailField('specialty', 'Estilo o especialidad'),
    DetailField('includes_editing', 'Incluye edición/entregables', isBoolean: true),
  ],
  'Estudio de grabación': [
    DetailField('specialty', 'Estilo o especialidad'),
    DetailField('includes_editing', 'Incluye edición/entregables', isBoolean: true),
  ],
  'Transporte': [
    DetailField('vehicle_type', 'Tipo de vehículo'),
    DetailField('passenger_capacity', 'Capacidad de pasajeros'),
  ],
  'Catering': [
    DetailField('menu_type', 'Tipo de menú'),
    DetailField('guest_count', 'Número de comensales'),
  ],
  'Decoracion y ambientación': [
    DetailField('event_type', 'Tipo de evento (boda, XV años, corporativo...)'),
    DetailField('includes_setup', 'Incluye montaje/desmontaje', isBoolean: true),
  ],
};

/// Shown for every category, after that category's own fields (if any).
/// Coverage area isn't here — it moved to its own `coverage_areas text[]`
/// column (see `supabase/schema.sql` §26 and [_CoverageAreasInput]) since
/// it needs to be filterable, unlike everything that stays in `details`.
const List<DetailField> kUniversalDetailFields = [
  DetailField('includes_own_equipment', 'Incluye equipo propio', isBoolean: true),
  DetailField('min_advance_notice', 'Anticipación mínima para reservar'),
];

/// `details` key for the follow-up "what equipment" field shown only
/// when `includes_own_equipment` is checked — not a normal [DetailField]
/// since it's conditional, not always-rendered, so it can't live in
/// [kCategoryDetailFields]/[kUniversalDetailFields] (which
/// [_DetailFieldsSection] renders unconditionally).
const String kOwnEquipmentDetailKey = 'equipo_propio_detalle';

/// Filters [values] down to the keys [category] actually asks for right
/// now — a leftover value from a category the provider picked earlier (or
/// from unchecking "equipo propio") shouldn't get saved. Blank text
/// fields are dropped too, since every one of these is optional. Shared
/// by both `_CreateServiceModalState` and `_EditServiceFormState` instead
/// of each keeping its own copy.
Map<String, dynamic> relevantServiceDetails(String category, Map<String, dynamic> values) {
  final relevantKeys = {
    ...(kCategoryDetailFields[category] ?? const []),
    ...kUniversalDetailFields,
  }.map((f) => f.key).toSet();
  if (values['includes_own_equipment'] == true) {
    relevantKeys.add(kOwnEquipmentDetailKey);
  }

  final details = <String, dynamic>{};
  for (final entry in values.entries) {
    if (!relevantKeys.contains(entry.key)) continue;
    if (entry.value is String && (entry.value as String).trim().isEmpty) continue;
    details[entry.key] = entry.value;
  }
  return details;
}

/// "Por hora" / "Tarifa fija" / "Por noche completa" options for
/// [_ChipSelector]&lt;String&gt;.
const List<(String, String)> kPricingTypeOptions = [
  (kPricingTypePerHour, 'Por hora'),
  (kPricingTypeFixed, 'Tarifa fija'),
  (kPricingTypePerNight, 'Por noche completa'),
];

/// 10/20/30/40/50% options for [_ChipSelector]&lt;int&gt; — the provider's
/// standard deposit rate for this service (Sistema Anti-Fuga). See
/// `supabase/schema.sql` §27.
const List<(int, String)> kAdvancePercentageOptions = [
  (10, '10%'),
  (20, '20%'),
  (30, '30%'),
  (40, '40%'),
  (50, '50%'),
];

/// Music genres a provider can tag their service with — its own list, not
/// `MusicGenres.all` (`core/constants/genres.dart`): that one is for a
/// musician's social profile self-tag ('Urbano', 'Fusión', 'Solista' as if
/// it were a genre...), a different concept from "what does this
/// commercial service actually play at events". 'Reggaeton' matches that
/// other list's spelling (no accent) so the same genre isn't stored two
/// different ways across the app. 'Otro' is never itself saved to
/// `music_genres` — see [finalMusicGenres].
const List<String> kServiceMusicGenres = [
  'Vallenato',
  'Popular',
  'Salsa',
  'Merengue',
  'Bachata',
  'Balada',
  'Bolero',
  'Reggaeton',
  'Champeta',
  'Ranchera',
  'Norteña',
  'Electrónica',
  'Otro',
];

/// The only categories where "what genres does this act play" makes
/// sense — a service like 'Sonido' or 'Catering' never fills this in.
const Set<String> kMusicGenreCategories = {'Solista', 'DJ', 'Agrupación'};

/// Turns the chip [selected]ion + the optional custom [otherText] into
/// what actually gets saved to `provider_services.music_genres` — 'Otro'
/// itself is never stored; if checked, [otherText] (trimmed) replaces it,
/// so a client filtering by genre later matches real genre names instead
/// of a meaningless "Otro" tag.
List<String> finalMusicGenres(Set<String> selected, String otherText) {
  final result = selected.where((g) => g != 'Otro').toList();
  if (selected.contains('Otro')) {
    final custom = otherText.trim();
    if (custom.isNotEmpty) result.add(custom);
  }
  return result;
}

/// Single-choice chip row — used for both the pricing-type and the
/// advance-percentage selectors, by both [CreateServiceModal]
/// (theme-driven colors, since that sheet follows the app's light/dark
/// setting) and [_EditServiceForm] (always-dark dialog), so colors come
/// in as params instead of being hardcoded here.
class _ChipSelector<T> extends StatelessWidget {
  const _ChipSelector({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.accentColor,
    required this.mutedColor,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color accentColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.$2),
            selected: value == option.$1,
            onSelected: (_) => onChanged(option.$1),
            showCheckmark: false,
            backgroundColor: Colors.transparent,
            selectedColor: accentColor,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: value == option.$1 ? Colors.black : mutedColor,
            ),
            side: BorderSide(color: value == option.$1 ? Colors.transparent : mutedColor),
          ),
      ],
    );
  }
}

/// Multi-choice chip row — same visual language as [_ChipSelector], but
/// several [options] can be selected at once (an act can play both
/// Vallenato and Popular). Used only for [kServiceMusicGenres]; kept
/// separate from [_ChipSelector] rather than generalizing it, since
/// single-choice (radio-like) and multi-choice (checkbox-like) selection
/// are different enough semantics to not share one API.
class _MultiChipSelector extends StatelessWidget {
  const _MultiChipSelector({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.accentColor,
    required this.mutedColor,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Color accentColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: (isSelected) {
              final next = Set<String>.of(selected);
              if (isSelected) {
                next.add(option);
              } else {
                next.remove(option);
              }
              onChanged(next);
            },
            showCheckmark: false,
            backgroundColor: Colors.transparent,
            selectedColor: accentColor,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected.contains(option) ? Colors.black : mutedColor,
            ),
            side: BorderSide(
              color: selected.contains(option) ? Colors.transparent : mutedColor,
            ),
          ),
      ],
    );
  }
}

/// Live "Anticipo para reservar: $40.000" preview, right under the
/// advance-percentage chips — recomputed on every rebuild from whatever
/// [price] the caller currently has parsed, via [advanceAmountFor]. Shows
/// a muted placeholder instead of a number until there's a price to
/// multiply.
class _AdvanceAmountPreview extends StatelessWidget {
  const _AdvanceAmountPreview({
    required this.price,
    required this.advancePercentage,
    required this.accentColor,
    required this.mutedColor,
  });

  final double? price;
  final int advancePercentage;
  final Color accentColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final currentPrice = price;
    if (currentPrice == null) {
      return Text(
        'Ingresa un precio primero para calcular el anticipo.',
        style: TextStyle(color: mutedColor, fontSize: 12),
      );
    }
    final amount = advanceAmountFor(currentPrice, advancePercentage);
    return Text(
      'Anticipo para reservar: ${formatCopPrice(amount)}',
      style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.w700),
    );
  }
}

/// Renders whichever [kCategoryDetailFields] apply to [category], plus
/// [kUniversalDetailFields] — same shared-widget-with-color-params
/// reasoning as [_ChipSelector]. Each field carries a `ValueKey` on
/// its own `key` so Flutter doesn't misattribute an existing controller to
/// a different field when [category] changes and the field list reshuffles.
class _DetailFieldsSection extends StatelessWidget {
  const _DetailFieldsSection({
    required this.category,
    required this.values,
    required this.onChanged,
    required this.fieldTextColor,
    required this.accentColor,
  });

  final String category;
  final Map<String, dynamic> values;
  final void Function(String key, dynamic value) onChanged;

  /// `null` lets each field inherit the ambient theme's text color
  /// (correct for [CreateServiceModal]'s light/dark-aware sheet); non-null
  /// forces a color (what [_EditServiceForm]'s always-dark dialog needs).
  final Color? fieldTextColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final fields = [
      ...(kCategoryDetailFields[category] ?? const []),
      ...kUniversalDetailFields,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final field in fields)
          ...(field.isBoolean
              ? [
                  CheckboxListTile(
                    key: ValueKey(field.key),
                    value: values[field.key] as bool? ?? false,
                    onChanged: (v) => onChanged(field.key, v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: accentColor,
                    title: Text(
                      field.label,
                      style: TextStyle(color: fieldTextColor, fontSize: 13),
                    ),
                  ),
                  // Only "equipo propio" has a required follow-up — see
                  // [kOwnEquipmentDetailKey].
                  if (field.key == 'includes_own_equipment' && values[field.key] == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14, left: 4),
                      child: TextFormField(
                        key: const ValueKey(kOwnEquipmentDetailKey),
                        initialValue: values[kOwnEquipmentDetailKey] as String? ?? '',
                        style: fieldTextColor == null ? null : TextStyle(color: fieldTextColor),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: '¿Qué equipo incluye?'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Describe brevemente el equipo que incluyes'
                            : null,
                        onChanged: (v) => onChanged(kOwnEquipmentDetailKey, v),
                      ),
                    ),
                ]
              : [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextFormField(
                      key: ValueKey(field.key),
                      initialValue: values[field.key] as String? ?? '',
                      style: fieldTextColor == null ? null : TextStyle(color: fieldTextColor),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(labelText: '${field.label} (opcional)'),
                      onChanged: (v) => onChanged(field.key, v),
                    ),
                  ),
                ]),
      ],
    );
  }
}

/// Tag/chip input for `provider_services.coverage_areas` — its own
/// `text[]` column (§26), not part of `details`, since the point is
/// letting a client search by city later. Typing a city and pressing
/// Enter/the add button turns it into a removable [Chip]; duplicates
/// (case/accent-insensitive) and blank entries are silently ignored
/// rather than surfaced as a form error, since this is an optional
/// multi-value field, not a single required one. Same
/// shared-widget-with-color-params approach as [_ChipSelector]/
/// [_DetailFieldsSection], since it's used by both the theme-driven
/// create sheet and the always-dark edit dialog.
class _CoverageAreasInput extends StatefulWidget {
  const _CoverageAreasInput({
    required this.values,
    required this.onChanged,
    required this.accentColor,
    required this.fieldTextColor,
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final Color accentColor;

  /// `null` lets the text field inherit the ambient theme's text color
  /// (correct for the light/dark-aware create sheet); non-null forces a
  /// color (what the always-dark edit dialog needs).
  final Color? fieldTextColor;

  @override
  State<_CoverageAreasInput> createState() => _CoverageAreasInputState();
}

class _CoverageAreasInputState extends State<_CoverageAreasInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u');

  void _addCity() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final normalized = _normalize(text);
    final isDuplicate = widget.values.any((v) => _normalize(v) == normalized);
    _controller.clear();
    if (isDuplicate) return;

    widget.onChanged([...widget.values, text]);
  }

  void _removeCity(String city) {
    widget.onChanged(widget.values.where((v) => v != city).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.values.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.values.map((city) {
                return Chip(
                  label: Text(city),
                  labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                  backgroundColor: widget.accentColor,
                  deleteIcon: const Icon(Icons.close, size: 16, color: Colors.black),
                  onDeleted: () => _removeCity(city),
                  side: BorderSide.none,
                );
              }).toList(),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: widget.fieldTextColor == null
                    ? null
                    : TextStyle(color: widget.fieldTextColor),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Zona de cobertura (opcional)',
                  hintText: 'Ej: Bucaramanga',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCity(),
              ),
            ),
            IconButton(
              onPressed: _addCity,
              icon: Icon(Icons.add_circle, color: widget.accentColor),
              tooltip: 'Agregar ciudad',
            ),
          ],
        ),
      ],
    );
  }
}

const String _kHabeasDataText =
    'Autorizo de manera previa e informada a Mussy para recolectar y '
    'almacenar mi documento de identidad con el fin exclusivo de validar '
    'mi seguridad e identidad en la plataforma, conforme a la ley de '
    'protección de datos.';

/// Opens [CreateServiceModal] as a bottom sheet — call this from the "+"
/// entry point in the app's navigation.
Future<void> showCreateServiceModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const CreateServiceModal(),
  );
}

/// Form a musician fills out to create their commercial "Perfil de
/// Servicio" (agrupación, solista, sonido...), inserted into
/// `provider_services` with status `pending_review` — see
/// `supabase/schema.sql` §17. Also runs the KYC/Habeas Data step (§20):
/// a mandatory cover photo, a mandatory cédula upload to the private
/// `identity_documents` bucket, and the legal consent checkbox — none of
/// which the form lets through without.
class CreateServiceModal extends StatefulWidget {
  const CreateServiceModal({super.key});

  @override
  State<CreateServiceModal> createState() => _CreateServiceModalState();
}

class _CreateServiceModalState extends State<CreateServiceModal> {
  final _formKey = GlobalKey<FormState>();
  final _repository = ProviderServiceRepository();

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _otherGenreController = TextEditingController();
  String _category = kServiceCategories.first;
  late String _pricingType = _kCategoryDefaultPricingType[_category] ?? kPricingTypePerHour;
  final Map<String, dynamic> _detailValues = {};
  final List<String> _coverageAreas = [];
  final Set<String> _selectedGenres = {};
  int _advancePercentage = 20;
  bool _priceVisible = true;
  final List<XFile> _coverPhotos = [];
  PlatformFile? _identityDoc;
  XFile? _selfie;
  bool _habeasDataAccepted = false;

  // Surfaced only after a failed submit attempt, right below each of the
  // four non-`TextFormField` requirements (photo, document, selfie,
  // checkbox) that `Form.validate()` can't cover on its own.
  bool _showCoverPhotoError = false;
  bool _showIdentityDocError = false;
  bool _showSelfieError = false;
  bool _showHabeasDataError = false;

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _otherGenreController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverPhoto() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (photo == null) return;
    setState(() {
      _coverPhotos.add(photo);
      _showCoverPhotoError = false;
    });
  }

  Future<void> _pickIdentityDoc() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final files = result?.files ?? const [];
    if (files.isEmpty) return;
    final file = files.first;
    setState(() {
      _identityDoc = file;
      _showIdentityDocError = false;
    });
  }

  Future<void> _pickSelfie() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (photo == null) return;
    setState(() {
      _selfie = photo;
      _showSelfieError = false;
    });
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    final hasCoverPhoto = _coverPhotos.isNotEmpty;
    final hasIdentityDoc = _identityDoc != null;
    final hasSelfie = _selfie != null;

    setState(() {
      _showCoverPhotoError = !hasCoverPhoto;
      _showIdentityDocError = !hasIdentityDoc;
      _showSelfieError = !hasSelfie;
      _showHabeasDataError = !_habeasDataAccepted;
    });
    if (!formValid || !hasCoverPhoto || !hasIdentityDoc || !hasSelfie || !_habeasDataAccepted) {
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay una sesión activa.')),
      );
      return;
    }

    setState(() => _saving = true);
    final progressState = ValueNotifier<BlockingProgressState>(
      const BlockingProgressState(title: 'Subiendo fotos...'),
    );
    final closeDialog = showBlockingProgressDialog(context, state: progressState);
    try {
      final coverPhotoUrls = await _repository.uploadCoverPhotos(
        images: _coverPhotos,
        userId: userId,
      );

      progressState.value = const BlockingProgressState(title: 'Subiendo documento de identidad...');
      final identityDocPath = await _repository.uploadIdentityDocument(
        file: _identityDoc!,
        userId: userId,
      );

      progressState.value = const BlockingProgressState(title: 'Subiendo selfie...');
      final selfiePath = await _repository.uploadIdentitySelfie(
        photo: _selfie!,
        userId: userId,
      );

      progressState.value = const BlockingProgressState(title: 'Guardando servicio...');
      await _repository.createService(
        category: _category,
        businessName: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        pricePerHour: parseCopInput(_priceController.text),
        pricingType: _pricingType,
        details: relevantServiceDetails(_category, _detailValues),
        coverageAreas: _coverageAreas,
        advancePercentage: _advancePercentage,
        priceVisible: _priceVisible,
        musicGenres: kMusicGenreCategories.contains(_category)
            ? finalMusicGenres(_selectedGenres, _otherGenreController.text)
            : const [],
        coverPhotos: coverPhotoUrls,
        identityDocUrl: identityDocPath,
        selfieUrl: selfiePath,
      );

      if (mounted) closeDialog();
      if (!mounted) return;
      Navigator.of(context).pop();
      showServiceSubmittedModal(context);
    } catch (e) {
      if (mounted) closeDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el servicio: $e')),
      );
    } finally {
      progressState.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: extension?.cardColor ?? theme.cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: extension?.textSecondary ?? theme.disabledColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Crear perfil de servicio',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Se publica en la Tarima luego de revisión.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: extension?.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('Evidencia artística', extension: extension),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nombre del servicio'),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Ingresa un nombre'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: kServiceCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) => setState(() {
                      _category = value!;
                      _pricingType = _kCategoryDefaultPricingType[_category] ?? kPricingTypePerHour;
                    }),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('Tipo de tarifa', extension: extension),
                  const SizedBox(height: 10),
                  _ChipSelector<String>(
                    options: kPricingTypeOptions,
                    value: _pricingType,
                    onChanged: (value) => setState(() => _pricingType = value),
                    accentColor: theme.colorScheme.primary,
                    mutedColor: extension?.textSecondary ?? theme.disabledColor,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CopPriceInputFormatter()],
                    validator: (value) =>
                        parseCopInput(value ?? '') == null ? 'Ingresa un precio' : null,
                    decoration: InputDecoration(
                      labelText: priceFieldLabel(_pricingType),
                      prefixText: '\$ ',
                    ),
                  ),
                  SwitchListTile(
                    value: _priceVisible,
                    onChanged: (value) => setState(() => _priceVisible = value),
                    activeThumbColor: theme.colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar precio a los clientes'),
                    subtitle: Text(
                      'Si lo desactivas, verán "Precio a convenir" — tú sigues '
                      'cotizando por contrapropuesta.',
                      style: theme.textTheme.bodySmall?.copyWith(color: extension?.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('Porcentaje de anticipo económico', extension: extension),
                  const SizedBox(height: 4),
                  Text(
                    'Lo que el cliente debe pagar para asegurar la reserva.',
                    style: theme.textTheme.bodySmall?.copyWith(color: extension?.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  _ChipSelector<int>(
                    options: kAdvancePercentageOptions,
                    value: _advancePercentage,
                    onChanged: (value) => setState(() => _advancePercentage = value),
                    accentColor: theme.colorScheme.primary,
                    mutedColor: extension?.textSecondary ?? theme.disabledColor,
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _priceController,
                    builder: (context, value, _) => _AdvanceAmountPreview(
                      price: parseCopInput(value.text),
                      advancePercentage: _advancePercentage,
                      accentColor: theme.colorScheme.primary,
                      mutedColor: extension?.textSecondary ?? theme.disabledColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    minLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Cuéntale al cliente qué ofreces'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('Zona de cobertura', extension: extension),
                  const SizedBox(height: 10),
                  _CoverageAreasInput(
                    values: _coverageAreas,
                    onChanged: (cities) => setState(() {
                      _coverageAreas
                        ..clear()
                        ..addAll(cities);
                    }),
                    accentColor: theme.colorScheme.primary,
                    fieldTextColor: null,
                  ),
                  if (kMusicGenreCategories.contains(_category)) ...[
                    const SizedBox(height: 20),
                    _SectionLabel('Género musical', extension: extension),
                    const SizedBox(height: 10),
                    _MultiChipSelector(
                      options: kServiceMusicGenres,
                      selected: _selectedGenres,
                      onChanged: (value) => setState(() {
                        _selectedGenres
                          ..clear()
                          ..addAll(value);
                      }),
                      accentColor: theme.colorScheme.primary,
                      mutedColor: extension?.textSecondary ?? theme.disabledColor,
                    ),
                    if (_selectedGenres.contains('Otro')) ...[
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _otherGenreController,
                        decoration: const InputDecoration(labelText: 'Especifica el género'),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Especifica el género o quita la opción "Otro"'
                            : null,
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  _SectionLabel('Detalles adicionales (opcionales)', extension: extension),
                  const SizedBox(height: 10),
                  _DetailFieldsSection(
                    category: _category,
                    values: _detailValues,
                    onChanged: (key, value) => setState(() => _detailValues[key] = value),
                    fieldTextColor: null,
                    accentColor: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _pickCoverPhoto,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _coverPhotos.isEmpty
                          ? 'Foto principal de la agrupación (obligatoria)'
                          : '${_coverPhotos.length} foto(s) seleccionada(s)',
                    ),
                  ),
                  if (_showCoverPhotoError) ...[
                    const SizedBox(height: 6),
                    _FieldError('Agrega al menos una foto antes de continuar.'),
                  ],
                  const SizedBox(height: 24),
                  _SectionLabel('Verificación de identidad', extension: extension),
                  const SizedBox(height: 4),
                  Text(
                    'Documento privado — solo tú y el equipo de moderación de Mussy pueden verlo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: extension?.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _pickIdentityDoc,
                    icon: const Icon(Icons.badge_outlined),
                    label: Text(
                      _identityDoc == null
                          ? 'Subir cédula (imagen o PDF)'
                          : _identityDoc!.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_showIdentityDocError) ...[
                    const SizedBox(height: 6),
                    _FieldError('Sube tu documento de identidad antes de continuar.'),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Selfie en vivo — para comparar tu rostro contra la cédula. '
                    'Se abre la cámara, no puedes elegir una foto de la galería.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: extension?.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_selfie != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_selfie!.path),
                          height: 140,
                          width: 140,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _pickSelfie,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(_selfie == null ? 'Tomar selfie' : 'Tomar otra selfie'),
                  ),
                  if (_showSelfieError) ...[
                    const SizedBox(height: 6),
                    _FieldError('Toma una selfie antes de continuar.'),
                  ],
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _habeasDataAccepted,
                    onChanged: (value) => setState(() {
                      _habeasDataAccepted = value ?? false;
                      if (_habeasDataAccepted) _showHabeasDataError = false;
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      _kHabeasDataText,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                  if (_showHabeasDataError) ...[
                    const SizedBox(height: 4),
                    _FieldError('Debes autorizar el tratamiento de tus datos para continuar.'),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Enviar a revisión'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.extension});

  final String text;
  final AppThemeExtension? extension;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: extension?.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
    );
  }
}

/// Centered "success" modal shown right after a service is submitted for
/// review — same dark/gold styling as [showEditServiceModal] so both
/// share one visual language instead of this being a one-off design.
/// Dismissing it just reveals whatever is underneath (`MyServicesScreen`,
/// already back on screen since the create sheet closed first).
void showServiceSubmittedModal(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: _kModalBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kModalAccent.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kModalAccent.withValues(alpha: 0.15),
                border: Border.all(color: _kModalAccent, width: 1.5),
              ),
              child: const Icon(Icons.check_rounded, color: _kModalAccent, size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Servicio enviado!',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tu servicio quedó en revisión. Te avisaremos apenas se apruebe, '
              'o si necesita algún ajuste.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kModalTextSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kModalAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens [_EditServiceForm] as a centered modal (dark scrim, `#0D0D12`
/// card, `#FFB703` accents) — unlike [showCreateServiceModal]'s full-height
/// bottom sheet, edits only touch the four plain fields below, so a compact
/// dialog is enough. Returns `true` when the update was saved, so the
/// caller knows to refresh its list.
Future<bool?> showEditServiceModal(BuildContext context, ProviderService service) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _EditServiceForm(service: service),
  );
}

class _EditServiceForm extends StatefulWidget {
  const _EditServiceForm({required this.service});

  final ProviderService service;

  @override
  State<_EditServiceForm> createState() => _EditServiceFormState();
}

class _EditServiceFormState extends State<_EditServiceForm> {
  final _formKey = GlobalKey<FormState>();
  final _repository = ProviderServiceRepository();

  late final _nameController = TextEditingController(text: widget.service.businessName);
  late final _priceController = TextEditingController(
    text: widget.service.pricePerHour != null
        ? formatCopInputValue(widget.service.pricePerHour!)
        : '',
  );
  late final _descriptionController = TextEditingController(text: widget.service.description);
  late String _category = widget.service.category;
  late String _pricingType = widget.service.pricingType;
  late final Map<String, dynamic> _detailValues = Map.of(widget.service.details);
  late final List<String> _coverageAreas = List.of(widget.service.coverageAreas);
  late int _advancePercentage = widget.service.advancePercentage;
  late bool _priceVisible = widget.service.priceVisible;
  // Any saved genre that isn't one of the canonical chips is the custom
  // text the provider typed for "Otro" — reconstruct both from the flat
  // `music_genres` list the same way [finalMusicGenres] flattened them.
  late final Set<String> _selectedGenres = {
    for (final g in widget.service.musicGenres)
      if (kServiceMusicGenres.contains(g)) g,
    if (widget.service.musicGenres.any((g) => !kServiceMusicGenres.contains(g))) 'Otro',
  };
  late final _otherGenreController = TextEditingController(
    text: widget.service.musicGenres.firstWhere(
      (g) => !kServiceMusicGenres.contains(g),
      orElse: () => '',
    ),
  );
  XFile? _newCoverPhoto;

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _otherGenreController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverPhoto() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (photo == null) return;
    setState(() => _newCoverPhoto = photo);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay una sesión activa.')),
      );
      return;
    }

    setState(() => _saving = true);
    final progressState = ValueNotifier<BlockingProgressState>(
      BlockingProgressState(
        title: _newCoverPhoto == null ? 'Guardando cambios...' : 'Subiendo foto...',
      ),
    );
    final closeDialog = showBlockingProgressDialog(context, state: progressState);
    try {
      List<String>? coverPhotos;
      if (_newCoverPhoto != null) {
        coverPhotos = await _repository.uploadCoverPhotos(
          images: [_newCoverPhoto!],
          userId: userId,
        );
        progressState.value = const BlockingProgressState(title: 'Guardando cambios...');
      }

      await _repository.updateService(
        serviceId: widget.service.id,
        category: _category,
        businessName: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        pricePerHour: parseCopInput(_priceController.text),
        pricingType: _pricingType,
        details: relevantServiceDetails(_category, _detailValues),
        coverageAreas: _coverageAreas,
        advancePercentage: _advancePercentage,
        priceVisible: _priceVisible,
        musicGenres: kMusicGenreCategories.contains(_category)
            ? finalMusicGenres(_selectedGenres, _otherGenreController.text)
            : const [],
        coverPhotos: coverPhotos,
      );
      if (mounted) closeDialog();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) closeDialog();
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    } finally {
      progressState.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: _kModalBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kModalAccent.withValues(alpha: 0.25)),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Editar servicio',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre del servicio'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Ingresa un nombre' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                dropdownColor: _kModalBackground,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: kServiceCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) => setState(() {
                  _category = value!;
                  _pricingType = _kCategoryDefaultPricingType[_category] ?? kPricingTypePerHour;
                }),
              ),
              const SizedBox(height: 16),
              const Text(
                'TIPO DE TARIFA',
                style: TextStyle(
                  color: _kModalTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              _ChipSelector<String>(
                options: kPricingTypeOptions,
                value: _pricingType,
                onChanged: (value) => setState(() => _pricingType = value),
                accentColor: _kModalAccent,
                mutedColor: _kModalTextSecondary,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _priceController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                inputFormatters: [CopPriceInputFormatter()],
                validator: (value) =>
                    parseCopInput(value ?? '') == null ? 'Ingresa un precio' : null,
                decoration: InputDecoration(
                  labelText: priceFieldLabel(_pricingType),
                  prefixText: '\$ ',
                ),
              ),
              SwitchListTile(
                value: _priceVisible,
                onChanged: (value) => setState(() => _priceVisible = value),
                activeThumbColor: _kModalAccent,
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar precio a los clientes', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Si lo desactivas, verán "Precio a convenir" — tú sigues '
                  'cotizando por contrapropuesta.',
                  style: TextStyle(color: _kModalTextSecondary, fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PORCENTAJE DE ANTICIPO ECONÓMICO',
                style: TextStyle(
                  color: _kModalTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Lo que el cliente debe pagar para asegurar la reserva.',
                style: TextStyle(color: _kModalTextSecondary, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _ChipSelector<int>(
                options: kAdvancePercentageOptions,
                value: _advancePercentage,
                onChanged: (value) => setState(() => _advancePercentage = value),
                accentColor: _kModalAccent,
                mutedColor: _kModalTextSecondary,
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _priceController,
                builder: (context, value, _) => _AdvanceAmountPreview(
                  price: parseCopInput(value.text),
                  advancePercentage: _advancePercentage,
                  accentColor: _kModalAccent,
                  mutedColor: _kModalTextSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                minLines: 3,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  alignLabelWithHint: true,
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Cuéntale al cliente qué ofreces' : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'ZONA DE COBERTURA',
                style: TextStyle(
                  color: _kModalTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              _CoverageAreasInput(
                values: _coverageAreas,
                onChanged: (cities) => setState(() {
                  _coverageAreas
                    ..clear()
                    ..addAll(cities);
                }),
                accentColor: _kModalAccent,
                fieldTextColor: Colors.white,
              ),
              if (kMusicGenreCategories.contains(_category)) ...[
                const SizedBox(height: 16),
                const Text(
                  'GÉNERO MUSICAL',
                  style: TextStyle(
                    color: _kModalTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                _MultiChipSelector(
                  options: kServiceMusicGenres,
                  selected: _selectedGenres,
                  onChanged: (value) => setState(() {
                    _selectedGenres
                      ..clear()
                      ..addAll(value);
                  }),
                  accentColor: _kModalAccent,
                  mutedColor: _kModalTextSecondary,
                ),
                if (_selectedGenres.contains('Otro')) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _otherGenreController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Especifica el género'),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Especifica el género o quita la opción "Otro"'
                        : null,
                  ),
                ],
              ],
              const SizedBox(height: 16),
              const Text(
                'DETALLES ADICIONALES (OPCIONALES)',
                style: TextStyle(
                  color: _kModalTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              _DetailFieldsSection(
                category: _category,
                values: _detailValues,
                onChanged: (key, value) => setState(() => _detailValues[key] = value),
                fieldTextColor: Colors.white,
                accentColor: _kModalAccent,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _newCoverPhoto != null
                        ? Image.file(
                            File(_newCoverPhoto!.path),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          )
                        : ServiceCoverImage(
                            url: widget.service.coverPhotoUrl,
                            width: 56,
                            height: 56,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickCoverPhoto,
                      icon: const Icon(Icons.add_photo_alternate_outlined, color: _kModalAccent),
                      label: const Text('Cambiar foto', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar', style: TextStyle(color: _kModalTextSecondary)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kModalAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text('Guardar', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
