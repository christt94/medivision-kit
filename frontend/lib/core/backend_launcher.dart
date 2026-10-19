import 'backend_launcher_stub.dart'
    if (dart.library.io) 'backend_launcher_io.dart' as implementation;

class BackendLauncher {
  static Future<void> start() => implementation.startBackend();
}
