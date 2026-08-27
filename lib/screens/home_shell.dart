import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'video_feed_screen.dart';

/// Bottom-nav shell for the authenticated app: "Directorio" (the musician
/// list, [DashboardScreen]) and "Videos" (the Reels-style feed,
/// [VideoFeedScreen]). `IndexedStack` keeps both tabs mounted and their
/// state alive across switches — DashboardScreen's loaded list/filters and
/// VideoFeedScreen's current playback position both survive tapping back
/// and forth, instead of rebuilding whichever tab isn't visible.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _videosTabIndex = 1;

  int _index = 0;

  void _goToTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final onVideosTab = _index == _videosTabIndex;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const DashboardScreen(),
          VideoFeedScreen(
            isActive: onVideosTab,
            onBack: () => _goToTab(0),
          ),
        ],
      ),
      // Hidden on the Videos tab so the feed renders truly full-screen
      // (TikTok/Reels-style) — VideoFeedScreen's own back arrow is what
      // brings the user (and this bar) back to Directorio.
      bottomNavigationBar: onVideosTab
          ? null
          : NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: const Color(0xFF0B1120),
                indicatorColor: const Color(0xFF8B5CF6).withValues(alpha: 0.28),
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? const Color(0xFFC4B5FD) : Colors.white60,
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    color: selected ? Colors.white : Colors.white60,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _goToTab,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.people_alt_outlined),
                    selectedIcon: Icon(Icons.people_alt_rounded),
                    label: 'Directorio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.video_collection_outlined),
                    selectedIcon: Icon(Icons.video_collection_rounded),
                    label: 'Videos',
                  ),
                ],
              ),
            ),
    );
  }
}
