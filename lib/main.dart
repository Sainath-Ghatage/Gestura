// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/home_screen.dart';
import 'screens/speech_to_text_screen.dart';
import 'screens/text_to_speech_screen.dart';
import 'screens/sign_to_text_screen.dart' as sign;
import 'screens/quick_signs_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation for consistency
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Request all needed permissions upfront so screens don't stall
  await _requestPermissions();

  runApp(const GesturaApp());
}

Future<void> _requestPermissions() async {
  final statuses = await [
    Permission.microphone,
    Permission.camera,
    Permission.storage,
    Permission.audio,        // Android 13+ READ_MEDIA_AUDIO
    Permission.videos,       // Android 13+ READ_MEDIA_VIDEO
    Permission.photos,       // Android 13+ READ_MEDIA_IMAGES
    Permission.manageExternalStorage, // gracefully denied on most devices – that's fine
  ].request();

  debugPrint('Permission results: $statuses');
}

// ─────────────────────────────────────────────
//  Root Application Widget
// ─────────────────────────────────────────────
class GesturaApp extends StatelessWidget {
  const GesturaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestura',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: _buildDarkTheme(),
      theme: _buildDarkTheme(), // always dark
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/stt': (_) => const SpeechToTextScreen(),
        '/tts': (_) => const TextToSpeechScreen(),
        '/sign': (_) => const sign.SignToTextScreen(),
        '/quick': (_) => const QuickSignsScreen(),
      },
    );
  }

  ThemeData _buildDarkTheme() {
    const Color primary = Color(0xFF00E5FF);   // bright cyan
    const Color secondary = Color(0xFFFFD600); // vivid amber
    const Color bg = Color(0xFF0A0A0A);         // near-black
    const Color surface = Color(0xFF1A1A1A);
    const Color onSurface = Color(0xFFF5F5F5);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: onSurface,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w900, color: onSurface),
        displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w800, color: onSurface),
        headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: onSurface),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: onSurface),
        titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: onSurface),
        bodyLarge: TextStyle(fontSize: 20, color: onSurface, height: 1.5),
        bodyMedium: TextStyle(fontSize: 17, color: onSurface, height: 1.4),
        labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 72),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          elevation: 4,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 2),
          minimumSize: const Size(double.infinity, 64),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary.withOpacity(0.5), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2.5),
        ),
        labelStyle: const TextStyle(color: primary, fontSize: 18),
        hintStyle: TextStyle(color: onSurface.withOpacity(0.4), fontSize: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: onSurface, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: const EdgeInsets.all(0),
      ),
    );
  }
}