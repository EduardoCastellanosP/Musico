import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color, WidgetsFlutterBinding;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules and reacts to the "¿Ya estás libre?" push that fires the
/// instant a musician's "ocupado hasta" window ends.
///
/// The two notification actions ("Sí, ya estoy libre" / "Sigo ocupado") run
/// without opening the app (`showsUserInterface: false`), so tapping either
/// one dispatches straight to [_handleNotificationResponse] on a background
/// isolate — see [_backgroundNotificationDispatcher] — with no UI to drive.
/// That handler talks to Supabase directly rather than through
/// [MusicianRepository] to avoid depending on any app state that only
/// exists in the foreground isolate.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Action id for "Sí, ya estoy libre".
  static const String markFreeActionId = 'MARK_FREE_ACTION';

  /// Action id for "Sigo ocupado".
  static const String stillBusyActionId = 'STILL_BUSY_ACTION';

  // "_v2" because Android freezes a channel's importance/sound/vibration the
  // first time it's created on a device — bumping the id is the only way to
  // roll out the alarm-grade vibration pattern below to installs that
  // already created the original "busy_status_channel" with defaults.
  static const String _busyChannelId = 'busy_status_channel_v2';
  static const String _busyChannelName = 'Disponibilidad';
  static const String _busyCategoryId = 'busy_status_category';

  /// Fixed id so scheduling a new "ocupado hasta" cutoff replaces (rather
  /// than stacks on top of) any notification scheduled for a previous one.
  static const int busyStatusNotificationId = 9001;

  /// Insistent on/off pulses (ms) so the check-out reminder reads as urgent
  /// as an incoming call rather than a routine notification. Pattern is
  /// [wait, vibrate, wait, vibrate, ...]; index 0 is the initial delay.
  static final Int64List _urgentVibrationPattern = Int64List.fromList([
    0,
    800,
    400,
    800,
    400,
    800,
    400,
    800,
  ]);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Sets up time zones, the Android notification channel/actions and the
  /// iOS notification category/actions. Call once, right after
  /// `Supabase.initialize` in `main()`.
  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone.identifier));
    } catch (_) {
      // Falls back to UTC (the `timezone` package default) if the platform
      // channel lookup fails — scheduling still works, just not aware of
      // the device's local offset.
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          _busyCategoryId,
          actions: [
            DarwinNotificationAction.plain(
              markFreeActionId,
              'Sí, ya estoy libre',
            ),
            DarwinNotificationAction.plain(stillBusyActionId, 'Sigo ocupado'),
          ],
          options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
        ),
      ],
    );

    await _plugin.initialize(
      settings: InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      ),
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse:
          _backgroundNotificationDispatcher,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _busyChannelId,
        _busyChannelName,
        description: 'Avisos sobre el fin de tu jornada como músico.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: _urgentVibrationPattern,
        enableLights: true,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
    // Android 14+ (API 34) gates `fullScreenIntent` behind this extra grant
    // for apps that aren't a default dialer/alarm app; older versions grant
    // it automatically from the manifest permission. Safe to call on every
    // version — it's a no-op where it doesn't apply.
    await androidPlugin?.requestFullScreenIntentPermission();

    _initialized = true;
  }

  /// Foreground taps land here (the plugin still routes non-UI actions
  /// through this callback while the app process is alive); the actual
  /// logic is shared with the background isolate via [_handleNotificationResponse].
  void _onForegroundResponse(NotificationResponse response) {
    unawaited(_handleNotificationResponse(response));
  }

  /// Schedules the premium "¿Ya estás libre?" notification for the exact
  /// moment [busyUntil] arrives. Replaces any previously scheduled one.
  /// No-op if [busyUntil] is already in the past.
  Future<void> scheduleBusyUntilNotification({
    required DateTime busyUntil,
    String? statusMessage,
  }) async {
    await cancelBusyUntilNotification();

    final scheduledDate = tz.TZDateTime.from(busyUntil, tz.local);
    if (!scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) return;

    final bigText = (statusMessage != null && statusMessage.trim().isNotEmpty)
        ? statusMessage.trim()
        : 'Tu jornada terminó. Actualiza tu estado para que los '
              'contratantes te vuelvan a ver disponible.';

    final androidDetails = AndroidNotificationDetails(
      _busyChannelId,
      _busyChannelName,
      channelDescription: 'Avisos sobre el fin de tu jornada como músico.',
      importance: Importance.max,
      priority: Priority.max,
      // Treats this like an incoming call/alarm: it heads-up over the lock
      // screen, wakes the display and plays through the alarm-grade
      // vibration pattern set on the channel above, instead of sitting
      // quietly in the shade like a routine reminder.
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _urgentVibrationPattern,
      styleInformation: BigTextStyleInformation(
        bigText,
        contentTitle: '<b>¡Es hora de actualizar tu estado! 🎶</b>',
        htmlFormatContentTitle: true,
        summaryText: 'VallenatoConnect',
      ),
      color: const Color(0xFFD4AF37),
      colorized: true,
      actions: const [
        AndroidNotificationAction(
          markFreeActionId,
          'Sí, ya estoy libre',
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          stillBusyActionId,
          'Sigo ocupado',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: _busyCategoryId,
      // `.critical` would bypass Silent/Focus mode like a phone call, but it
      // requires Apple's paid Critical Alerts entitlement per-app. Without
      // it, `.timeSensitive` is the strongest level any app gets by default
      // — it still breaks through Focus modes and shows on the lock screen.
      interruptionLevel: InterruptionLevel.timeSensitive,
      subtitle: 'VallenatoConnect',
    );

    await _plugin.zonedSchedule(
      id: busyStatusNotificationId,
      scheduledDate: scheduledDate,
      title: '¿Ya estás libre?',
      body: bigText,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Cancels the pending "¿Ya estás libre?" notification — called when the
  /// musician marks themself free before their scheduled cutoff arrives.
  Future<void> cancelBusyUntilNotification() =>
      _plugin.cancel(id: busyStatusNotificationId);
}

/// Runs on a background isolate spun up by the platform when a notification
/// action with `showsUserInterface: false` is tapped and the app isn't in
/// the foreground. Must stay a top-level function annotated with
/// `@pragma('vm:entry-point')` so the Dart compiler doesn't tree-shake it —
/// the native side invokes it by name, without going through `main()`.
@pragma('vm:entry-point')
void _backgroundNotificationDispatcher(NotificationResponse response) {
  unawaited(_handleNotificationResponse(response));
}

/// Shared by the foreground and background callbacks. Only
/// [NotificationService.markFreeActionId] does anything — "Sigo ocupado"
/// simply dismisses the notification (handled natively via
/// `cancelNotification: true`), so there's nothing to update here.
Future<void> _handleNotificationResponse(NotificationResponse response) async {
  if (response.actionId != NotificationService.markFreeActionId) return;

  WidgetsFlutterBinding.ensureInitialized();
  final client = await _ensureSupabaseClient();
  final uid = client.auth.currentUser?.id;
  if (uid == null) return;

  await client
      .from('profiles')
      .update({'is_free': true, 'busy_until': null})
      .eq('id', uid);
}

/// Returns the already-initialized Supabase client when running in the
/// app's main isolate, or boots a fresh one — restoring the musician's
/// persisted session from local storage — when running in the headless
/// background isolate spawned for the notification action.
Future<SupabaseClient> _ensureSupabaseClient() async {
  try {
    return Supabase.instance.client;
  } catch (_) {
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      anonKey: dotenv.get('SUPABASE_ANON_KEY'),
    );
    return Supabase.instance.client;
  }
}
