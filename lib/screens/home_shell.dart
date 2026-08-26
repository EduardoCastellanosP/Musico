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

  // `IndexedStack` only hides the inactive tab visually — it has no notion
  // of "this screen is no longer visible", so a playing video keeps its
  // audio running underneath the Directorio tab unless something outside
  // VideoFeedScreen tells it to pause. This key is that "something": it
  // reaches into VideoFeedScreenState directly the moment the destination
  // changes, instead of threading a `visible` flag through props.
  final _videoFeedKey = GlobalKey<VideoFeedScreenState>();

  void _onDestinationSelected(int index) {
    if (index == _index) return;
    if (_index == _videosTabIndex) {
      _videoFeedKey.currentState?.pauseCurrent();
    } else if (index == _videosTabIndex) {
      _videoFeedKey.currentState?.resumeCurrent();
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const DashboardScreen(),
          VideoFeedScreen(key: _videoFeedKey),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
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
          onDestinationSelected: _onDestinationSelected,
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
