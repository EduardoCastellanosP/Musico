import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/profile_summary.dart';

/// Draggable, scrollable "N seguidores"/"N me gusta" list — shared by the
/// dashboard header (own profile) and [MusicianDetailScreen] (another
/// musician's profile) so both taps open the exact same sheet, just fed by
/// a different query.
Future<void> showPeopleListSheet(
  BuildContext context, {
  required String title,
  required Future<List<ProfileSummary>> Function() fetchPeople,
}) {
  final theme = Theme.of(context);
  final extension = theme.extension<AppThemeExtension>();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: extension?.cardColor ?? theme.cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => _PeopleListSheetBody(
        title: title,
        fetchPeople: fetchPeople,
        scrollController: scrollController,
      ),
    ),
  );
}

class _PeopleListSheetBody extends StatefulWidget {
  const _PeopleListSheetBody({
    required this.title,
    required this.fetchPeople,
    required this.scrollController,
  });

  final String title;
  final Future<List<ProfileSummary>> Function() fetchPeople;
  final ScrollController scrollController;

  @override
  State<_PeopleListSheetBody> createState() => _PeopleListSheetBodyState();
}

class _PeopleListSheetBodyState extends State<_PeopleListSheetBody> {
  late final Future<List<ProfileSummary>> _future = widget.fetchPeople();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: extension?.textSecondary.withValues(alpha: 0.15),
          ),
          Expanded(
            child: FutureBuilder<List<ProfileSummary>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'No pudimos cargar la lista.',
                      style: TextStyle(color: extension?.textSecondary),
                    ),
                  );
                }
                final people = snapshot.data ?? const [];
                if (people.isEmpty) {
                  return Center(
                    child: Text(
                      'Todavía no hay nadie aquí.',
                      style: TextStyle(color: extension?.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: people.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 76,
                    color: extension?.textSecondary.withValues(alpha: 0.1),
                  ),
                  itemBuilder: (context, index) {
                    final person = people[index];
                    final hasAvatar =
                        person.avatarUrl != null && person.avatarUrl!.isNotEmpty;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                        backgroundImage:
                            hasAvatar ? NetworkImage(person.avatarUrl!) : null,
                        child: hasAvatar
                            ? null
                            : Text(
                                person.initials,
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      title: Text(
                        person.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
