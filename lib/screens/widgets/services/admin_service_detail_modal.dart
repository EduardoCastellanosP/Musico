import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/currency.dart';
import '../../../models/provider_service.dart';
import '../../../repositories/provider_service_repository.dart';
import 'service_cover_image.dart';

const _kBackground = Color(0xFF0D0D12);
const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

const _kImageExtensions = ['jpg', 'jpeg', 'png'];

/// Opens the full moderation detail for a pending [ProviderService] — the
/// deep-review step before an admin approves/rejects from
/// `admin_dashboard_screen.dart`'s card. [onApprove]/[onReject] should run
/// the actual `updateServiceStatus` call (reusing
/// `_AdminDashboardScreenState._review`) and report back whether it
/// succeeded, so this modal knows whether to close itself.
Future<void> showAdminServiceDetailModal(
  BuildContext context, {
  required ProviderService service,
  required Future<bool> Function() onApprove,
  required Future<bool> Function() onReject,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AdminServiceDetailModal(
      service: service,
      onApprove: onApprove,
      onReject: onReject,
    ),
  );
}

class AdminServiceDetailModal extends StatefulWidget {
  const AdminServiceDetailModal({
    super.key,
    required this.service,
    required this.onApprove,
    required this.onReject,
  });

  final ProviderService service;
  final Future<bool> Function() onApprove;
  final Future<bool> Function() onReject;

  @override
  State<AdminServiceDetailModal> createState() => _AdminServiceDetailModalState();
}

class _AdminServiceDetailModalState extends State<AdminServiceDetailModal>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  late final TabController _tabController;
  final _repository = ProviderServiceRepository();
  Future<String>? _signedUrlFuture;

  int _photoIndex = 0;
  bool _busy = false;
  Future<String>? _selfieSignedUrlFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final docPath = widget.service.identityDocUrl;
    if (docPath != null) {
      _signedUrlFuture = _repository.getIdentityDocumentSignedUrl(docPath);
    }
    final selfiePath = widget.service.selfieUrl;
    if (selfiePath != null) {
      _selfieSignedUrlFuture = _repository.getIdentityDocumentSignedUrl(selfiePath);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handle({required bool approve}) async {
    setState(() => _busy = true);
    final success = await (approve ? widget.onApprove() : widget.onReject());
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _kBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: _kAccent,
                labelColor: _kAccent,
                unselectedLabelColor: _kTextSecondary,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Vista previa (cliente)'),
                  Tab(text: 'Verificación de identidad'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ClientPreviewTab(
                      service: service,
                      scrollController: scrollController,
                      pageController: _pageController,
                      photoIndex: _photoIndex,
                      onPhotoPageChanged: (i) => setState(() => _photoIndex = i),
                    ),
                    _IdentityVerificationTab(
                      service: service,
                      signedUrlFuture: _signedUrlFuture,
                      selfieSignedUrlFuture: _selfieSignedUrlFuture,
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _handle(approve: false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Rechazar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _busy ? null : () => _handle(approve: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.verified, size: 18),
                                    SizedBox(width: 6),
                                    Text('Aprobar y verificar'),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: _kTextSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// "How the client sees it" — exactly what `ClientHomeScreen`'s cards show
/// once approved: photos, name, category, price, description. No admin-only
/// data (contact info, cédula) belongs on this tab.
class _ClientPreviewTab extends StatelessWidget {
  const _ClientPreviewTab({
    required this.service,
    required this.scrollController,
    required this.pageController,
    required this.photoIndex,
    required this.onPhotoPageChanged,
  });

  final ProviderService service;
  final ScrollController scrollController;
  final PageController pageController;
  final int photoIndex;
  final ValueChanged<int> onPhotoPageChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.zero,
      children: [
        ServicePhotoGallery(
          photos: service.coverPhotos,
          pageController: pageController,
          currentIndex: photoIndex,
          onPageChanged: onPhotoPageChanged,
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      service.businessName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (service.pricePerHour != null)
                    Text(
                      formatCopPriceForPricingType(service.pricePerHour!, service.pricingType),
                      style: const TextStyle(
                        color: _kAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kAccent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  service.category.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Descripción'),
              const SizedBox(height: 6),
              Text(
                service.description.isEmpty ? 'Sin descripción.' : service.description,
                style: const TextStyle(color: Colors.white, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Admin-only: who's asking (contact info) and the KYC document itself —
/// never shown to clients, gated entirely by the private
/// `identity_documents` bucket's RLS (`supabase/schema.sql` §20), not by
/// this tab simply not being on the client's screen.
class _IdentityVerificationTab extends StatelessWidget {
  const _IdentityVerificationTab({
    required this.service,
    required this.signedUrlFuture,
    required this.selfieSignedUrlFuture,
  });

  final ProviderService service;
  final Future<String>? signedUrlFuture;
  final Future<String>? selfieSignedUrlFuture;

  @override
  Widget build(BuildContext context) {
    final acceptedAt = service.habeasDataAcceptedAt;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _SectionLabel('Solicitado por'),
        const SizedBox(height: 10),
        _OwnerRow(service: service),
        const SizedBox(height: 24),
        const _SectionLabel('Documento de identidad vs. selfie'),
        const SizedBox(height: 4),
        const Text(
          'Compara el rostro de la cédula contra la selfie para confirmar que es la misma persona.',
          style: TextStyle(color: _kTextSecondary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _IdentityDocumentViewer(
                signedUrlFuture: signedUrlFuture,
                emptyMessage: 'Sin documento de identidad registrado.',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _IdentityDocumentViewer(
                signedUrlFuture: selfieSignedUrlFuture,
                emptyMessage: 'Sin selfie registrada.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(
              service.isVerified ? Icons.verified : Icons.hourglass_empty_rounded,
              color: service.isVerified ? _kAccent : _kTextSecondary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              service.isVerified ? 'Verificado' : 'Pendiente de revisión',
              style: TextStyle(
                color: service.isVerified ? _kAccent : _kTextSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          acceptedAt == null
              ? 'Sin registro de autorización de Habeas Data.'
              : 'Autorizó el tratamiento de datos el '
                  '${acceptedAt.day}/${acceptedAt.month}/${acceptedAt.year}.',
          style: const TextStyle(color: _kTextSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

/// Resolves the private `identity_documents` path to a signed URL and
/// renders it: an inline preview for images, or an "Abrir documento"
/// button (via `url_launcher`, since Flutter has no built-in PDF viewer)
/// for anything else — a PDF cédula chiefly.
class _IdentityDocumentViewer extends StatelessWidget {
  const _IdentityDocumentViewer({
    required this.signedUrlFuture,
    required this.emptyMessage,
  });

  final Future<String>? signedUrlFuture;
  final String emptyMessage;

  static const double _height = 180;

  @override
  Widget build(BuildContext context) {
    final future = signedUrlFuture;
    if (future == null) {
      return _frame(
        child: Text(emptyMessage, style: const TextStyle(color: _kTextSecondary)),
      );
    }

    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _frame(
            child: const CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _frame(
            child: const Text(
              'No se pudo generar el enlace.',
              style: TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final signedUrl = snapshot.data!;
        final isImage = _kImageExtensions.any(
          (ext) => signedUrl.toLowerCase().contains('.$ext'),
        );

        if (isImage) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              signedUrl,
              height: _height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _frame(
                child: const Text(
                  'No se pudo cargar la imagen.',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          );
        }

        return _frame(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, color: _kAccent, size: 32),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(signedUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Abrir'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _frame({required Widget child}) {
    return Container(
      width: double.infinity,
      height: _height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// Owner identity + contact — sourced from the `profiles` embed in
/// `ProviderServiceRepository.fetchPendingServices`. Any field can be
/// missing (incomplete profile), so each line only renders when present.
class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.service});

  final ProviderService service;

  @override
  Widget build(BuildContext context) {
    final name = service.ownerFullName?.trim();
    final city = service.ownerCity?.trim();
    final phone = service.ownerPhone?.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            backgroundImage: service.ownerAvatarUrl != null
                ? NetworkImage(service.ownerAvatarUrl!)
                : null,
            child: service.ownerAvatarUrl == null
                ? const Icon(Icons.person, color: _kTextSecondary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (name == null || name.isEmpty) ? 'Perfil sin nombre' : name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                if (city != null && city.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 13, color: _kTextSecondary),
                      const SizedBox(width: 4),
                      Text(city, style: const TextStyle(color: _kTextSecondary, fontSize: 13)),
                    ],
                  ),
                ],
                if (phone != null && phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 13, color: _kTextSecondary),
                      const SizedBox(width: 4),
                      Text(phone, style: const TextStyle(color: _kTextSecondary, fontSize: 13)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
