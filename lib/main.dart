import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from the bundled .env asset.
  await dotenv.load(fileName: '.env');

  // Initialize Supabase using credentials from the .env file.
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_KEY']!,
  );

  runApp(const SmartFridgeApp());
}

class SmartFridgeApp extends StatelessWidget {
  const SmartFridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Determine the initial screen based on whether a session already exists.
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'Smart Fridge',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: session != null ? const HomeScreen() : const AuthScreen(),
    );
  }

  ThemeData _buildTheme() {
    const seedColor = Color(0xFF00C896); // Mint-green accent for a tech feel.
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      fontFamily: 'Roboto',
    );
  }
}
