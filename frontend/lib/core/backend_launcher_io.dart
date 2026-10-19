import 'dart:io';

Process? _backendProcess;

Future<void> startBackend() async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;

  final executableName = Platform.isWindows
      ? 'medivision_backend.exe'
      : 'medivision_backend';
  final executable = File(Platform.resolvedExecutable).parent.uri
      .resolve('backend/$executableName')
      .toFilePath();
  final executableFile = File(executable);
  if (!executableFile.existsSync()) return;

  try {
    _backendProcess = await Process.start(
      executableFile.path,
      const [],
      workingDirectory: executableFile.parent.path,
      runInShell: false,
    );
    // Keep backend output available to the desktop process for diagnostics.
    _backendProcess!.stdout.listen((_) {});
    _backendProcess!.stderr.listen((_) {});
    await _waitForBackend();
  } catch (_) {
    // The UI remains launchable so the user can see the backend connection error.
  }
}

Future<void> _waitForBackend() async {
  for (var attempt = 0; attempt < 30; attempt++) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:8000/health'));
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode == 200) return;
    } catch (_) {
      // The local service may still be starting.
    } finally {
      client.close(force: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
