import 'package:flutter/foundation.dart';

class AppLogger {
  static void log(String message, {String tag = 'INFO'}) {
    if (kDebugMode) {
      debugPrint('🔍 [$tag]: $message');
    }
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('🛑 [ERROR]: $message');
      if (error != null) debugPrint('Detalle: $error');
      if (stackTrace != null) debugPrint('Stack: $stackTrace');
    }
  }
}