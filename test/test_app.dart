import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/app/theme.dart';

Widget testApp(
  Widget child, {
  ThemeData? data,
  ThemeData? materialTheme,
  Locale locale = const Locale('en'),
}) {
  final theme = materialTheme ?? data ?? AppTheme.darkTheme;
  return MaterialApp(
    locale: locale,
    supportedLocales: CreativeStudioLocalizations.supportedLocales,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
      CreativeStudioLocalizations.delegate,
    ],
    theme: theme,
    builder: (context, routeChild) => AppThemeScope(
      data: theme,
      child: routeChild ?? const SizedBox.shrink(),
    ),
    home: Material(child: child),
  );
}
