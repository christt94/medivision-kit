import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app.dart';
import 'core/backend_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);
  await BackendLauncher.start();
  runApp(const MediVisionApp());
}
