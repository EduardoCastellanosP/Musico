import 'package:flutter/material.dart';

/// Cover image for a `provider_services` row — shared by the Tarima client
/// list (`client_home_screen.dart`) and the admin moderation cards
/// (`admin_dashboard_screen.dart`). Falls back to a placeholder when the
/// listing has no `cover_photos` yet, or if the URL fails to load, instead
/// of letting `Image.network` throw on an empty string.
class ServiceCoverImage extends StatelessWidget {
  const ServiceCoverImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.backgroundColor = const Color(0xFF17171D),
    this.iconColor = const Color(0xFF9A9AA5),
    this.accentColor = const Color(0xFFFFB703),
  });

  final String? url;
  final double width;
  final double height;
  final Color backgroundColor;
  final Color iconColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (url == null) return _placeholder();

    return Image.network(
      url!,
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(
          child: CircularProgressIndicator(color: accentColor, strokeWidth: 2),
        );
      },
      errorBuilder: (context, error, stackTrace) => _placeholder(),
    );
  }

  Widget _placeholder({Widget? child}) {
    return Container(
      width: width,
      height: height,
      color: backgroundColor,
      alignment: Alignment.center,
      child: child ?? Icon(Icons.music_note, color: iconColor),
    );
  }
}

/// Full-width cover-photo carousel with a page-dot indicator — falls back
/// to a single placeholder frame (via [ServiceCoverImage]'s own null
/// handling) when the listing has no photos yet. Shared by
/// `ServiceDetailScreen` and `AdminServiceDetailModal`'s client-preview
/// tab so both read as the same carousel instead of two hand-maintained
/// copies drifting apart.
class ServicePhotoGallery extends StatelessWidget {
  const ServicePhotoGallery({
    super.key,
    required this.photos,
    required this.pageController,
    required this.currentIndex,
    required this.onPageChanged,
    this.height = 240,
    this.accentColor = const Color(0xFFFFB703),
  });

  final List<String> photos;
  final PageController pageController;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final double height;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final pageCount = photos.isEmpty ? 1 : photos.length;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: PageView.builder(
            controller: pageController,
            onPageChanged: onPageChanged,
            itemCount: pageCount,
            itemBuilder: (context, index) {
              final url = photos.isEmpty ? null : photos[index];
              return ServiceCoverImage(url: url, width: double.infinity, height: height);
            },
          ),
        ),
        if (pageCount > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(pageCount, (i) {
                final active = i == currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 8 : 6,
                  height: active ? 8 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? accentColor : Colors.white.withValues(alpha: 0.5),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
