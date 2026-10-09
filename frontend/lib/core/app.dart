import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../router/app_router.dart';

class MediVisionApp extends StatelessWidget {
  const MediVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MediVision Kit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
    );
  }
}
