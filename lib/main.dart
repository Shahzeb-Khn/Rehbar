import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const VoiceRagApp());
}

class VoiceRagApp extends StatelessWidget {
  const VoiceRagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'World Bank | اردو سوال جواب',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.notoNastaliqUrduTextTheme(
          ThemeData.dark().textTheme,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0E1A),
      ),
      home: const HomeScreen(),
    );
  }
}
