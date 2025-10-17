import 'dart:developer' as dev;

/// Simple structured logging helper for debugging data loading issues.
/// Usage:
///   final done = logAsyncStart('admin.users.load');
///   try { ... } catch(e,st){ logError('admin.users.load', e, st); } finally { done(); }
/// Or use convenience wrappers below.
class AppLog {
  static Stopwatch _sw() => Stopwatch()..start();

  static void info(String code, String message, {Map<String, Object?> data = const {}}) {
    dev.log(message, name: code, sequenceNumber: DateTime.now().millisecondsSinceEpoch, error: data.isEmpty ? null : data);
  }

  static void error(String code, Object error, StackTrace stack, {Map<String, Object?> data = const {}}) {
    dev.log('ERROR: $error', name: code, error: error, stackTrace: stack, sequenceNumber: DateTime.now().millisecondsSinceEpoch);
    if (data.isNotEmpty) {
      dev.log('context', name: code, error: data, sequenceNumber: DateTime.now().millisecondsSinceEpoch);
    }
  }

  static T wrap<T>(String code, T Function() fn) {
    final sw = _sw();
    try { final r = fn(); info(code, 'success', data: {'ms': sw.elapsedMilliseconds}); return r; }
    catch(e,st){ error(code, e, st, data: {'ms': sw.elapsedMilliseconds}); rethrow; }
  }

  static Future<T> wrapAsync<T>(String code, Future<T> Function() fn) async {
    final sw = _sw();
    try { final r = await fn(); info(code, 'success', data: {'ms': sw.elapsedMilliseconds}); return r; }
    catch(e,st){ error(code, e, st, data: {'ms': sw.elapsedMilliseconds}); rethrow; }
  }
}
