import 'package:flutter/material.dart';

import '../models/musician.dart';
import 'widgets/dashboard/musician_card.dart';

/// Read-only render of the logged-in musician's own [MusicianCard], reached
/// from "Mi Estado" — lets them see exactly how their profile looks in the
/// public directory now that [MusicianRepository.fetchMusicians] excludes it.
class ProfilePreviewScreen extends StatelessWidget {
  const ProfilePreviewScreen({super.key, required this.musician});

  final Musician musician;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vista previa de tu perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            MusicianCard(
              musician: musician,
              onWhatsAppTap: () {},
              onCallTap: () {},
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
