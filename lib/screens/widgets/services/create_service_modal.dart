import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../repositories/provider_service_repository.dart';

/// Categories a musician can list their commercial profile under — kept
/// local to this form rather than in `MusicianServices` (that constant is
/// for the social/directory "services" chips, a different concept from a
/// Tarima listing's single category).
const List<String> _kServiceCategories = [
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
'Transporte' 
  'Otros',
];

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
  String _category = _kServiceCategories.first;
  final List<XFile> _coverPhotos = [];
  PlatformFile? _identityDoc;
  bool _habeasDataAccepted = false;

  // Surfaced only after a failed submit attempt, right below each of the
  // three non-`TextFormField` requirements (photo, document, checkbox) that
  // `Form.validate()` can't cover on its own.
  bool _showCoverPhotoError = false;
  bool _showIdentityDocError = false;
  bool _showHabeasDataError = false;

  bool _saving = false;
  String _savingLabel = '';

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
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

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    final hasCoverPhoto = _coverPhotos.isNotEmpty;
    final hasIdentityDoc = _identityDoc != null;

    setState(() {
      _showCoverPhotoError = !hasCoverPhoto;
      _showIdentityDocError = !hasIdentityDoc;
      _showHabeasDataError = !_habeasDataAccepted;
    });
    if (!formValid || !hasCoverPhoto || !hasIdentityDoc || !_habeasDataAccepted) {
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay una sesión activa.')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _savingLabel = 'Subiendo fotos...';
    });
    try {
      final coverPhotoUrls = await _repository.uploadCoverPhotos(
        images: _coverPhotos,
        userId: userId,
      );

      if (mounted) setState(() => _savingLabel = 'Subiendo documento de identidad...');
      final identityDocPath = await _repository.uploadIdentityDocument(
        file: _identityDoc!,
        userId: userId,
      );

      if (mounted) setState(() => _savingLabel = 'Guardando servicio...');
      await _repository.createService(
        category: _category,
        businessName: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        pricePerHour: double.tryParse(_priceController.text.trim()),
        coverPhotos: coverPhotoUrls,
        identityDocUrl: identityDocPath,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Servicio enviado a revisión. Te avisaremos cuando se apruebe.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el servicio: $e')),
      );
    } finally {
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
                    decoration: const InputDecoration(labelText: 'Nombre del servicio'),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Ingresa un nombre'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: _kServiceCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) => setState(() => _category = value!),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Precio por hora (opcional)',
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    minLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Cuéntale al cliente qué ofreces'
                        : null,
                  ),
                  const SizedBox(height: 14),
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
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Text(_savingLabel),
                            ],
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
