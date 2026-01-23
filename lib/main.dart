import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

import 'date_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _requestStoragePermissionOnStart();

  runApp(const MyApp());
}

Future<void> _requestStoragePermissionOnStart() async {
  if (!Platform.isAndroid) return;

  // Android 11+ → precisa de MANAGE_EXTERNAL_STORAGE
  if (await Permission.manageExternalStorage.isDenied) {
    final status = await Permission.manageExternalStorage.request();

    if (status.isPermanentlyDenied) {
      // Abre configurações do app
      await openAppSettings();
    }
  }

  // Fallback (Android 9 / 10)
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      locale: Locale('pt', 'BR'),
      supportedLocales: [Locale('pt', 'BR')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      home: DateScreen(),
    );
  }
}
