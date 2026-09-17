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
