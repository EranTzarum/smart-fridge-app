import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'auth_screen.dart';

/// Placeholder home screen shown after a successful authentication.
/// Replace the body with real inventory content as the app grows.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await AuthService().signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.kitchen_rounded, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Smart Fridge',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: Icon(Icons.logout_rounded, color: cs.onSurface.withOpacity(0.7)),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 72, color: cs.primary.withOpacity(0.4)),
            const SizedBox(height: 20),
            Text(
              'Your fridge is empty.',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Inventory features coming soon.',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
