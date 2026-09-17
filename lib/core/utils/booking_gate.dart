import '../../models/musician.dart';

/// Auto-provisioned `full_name` values from `handle_new_user`/[Musician]'s
/// own fallback — a client whose name is still one of these hasn't
/// actually told us who they are yet, even though the column isn't empty.
const _kPlaceholderNames = {'Nuevo Músico', 'Músico sin nombre'};

/// "The Booking Gate": whether [profile] has the 3 things Mussy requires
/// from a CLIENT before they can request a booking/quote — full name,
/// profile photo, and a WhatsApp-reachable phone. Reuses [Musician] (the
/// same `profiles` row shape used for musicians) since a client's contact
/// info lives in the exact same table/columns; this just checks a
/// different, smaller subset of them than [Musician.hasCompleteProfile]
/// (which also requires a service, photos and video — irrelevant to a
/// client). Call this right before starting a booking/quote flow; show
/// [showBookingGatePrompt] when it returns `false`.
bool isProfileCompleteForBooking(Musician profile) {
  final hasRealName =
      profile.fullName.trim().isNotEmpty && !_kPlaceholderNames.contains(profile.fullName.trim());
  final hasPhoto = profile.avatarUrl?.trim().isNotEmpty ?? false;
  return hasRealName && hasPhoto && profile.hasPhone;
}
