/// Portfolio media caps, enforced both here (so the UI can block the action
/// and show a `SnackBar` before ever touching the network) and as a CHECK
/// constraint on `profiles.photos`/`profiles.videos` in `supabase/schema.sql`
/// (so the limit holds even if a client skips this check).
abstract final class MediaLimits {
  static const int maxPhotos = 10;
  static const int maxVideos = 3;
}
