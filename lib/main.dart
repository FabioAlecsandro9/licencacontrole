import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'date_screen.dart';

void main() {
  runApp(
    const MaterialApp(
      locale: Locale('pt', 'BR'),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [const Locale('pt', 'BR')],
      home: DateScreen(),
    ),
  );
}
