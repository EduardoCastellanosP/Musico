/// Bare profile info for followers/likes lists — just enough to render an
/// avatar + name row, unlike the full [Musician] model those screens don't
/// need here.
class ProfileSummary {
  const ProfileSummary({
    required this.id,
    required this.fullName,
    required this.avatarUrl,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    return ProfileSummary(
      id: json['id'] as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? json['full_name'] as String
          : 'Músico sin nombre',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String id;
  final String fullName;
  final String? avatarUrl;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}
