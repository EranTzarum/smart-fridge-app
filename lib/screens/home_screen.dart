import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'inventory_screen.dart';

// ── Card data model ───────────────────────────────────────────────────────────

class _CardData {
  const _CardData({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onTap;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Unsplash photos — high-res, freely usable placeholders.
  static const _fridgeImg =
      'https://images.unsplash.com/photo-1584568694244-14fbdf83bd30'
      '?w=800&auto=format&fit=crop&q=80';
  static const _shoppingImg =
      'https://images.unsplash.com/photo-1542838132-92c53300491e'
      '?w=800&auto=format&fit=crop&q=80';
  static const _recipesImg =
      'https://images.unsplash.com/photo-1490645935967-10de6ba17061'
      '?w=800&auto=format&fit=crop&q=80';
  static const _cookingImg =
      'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136'
      '?w=800&auto=format&fit=crop&q=80';

  Future<void> _signOut(BuildContext context) async {
    await AuthService().signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$feature — coming soon!',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2C2C2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ),
    );
  }

  PageRouteBuilder<T> _smoothRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, animation, __) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _CardData(
        title: 'MY FRIDGE',
        subtitle: 'Track & manage your inventory',
        imageUrl: _fridgeImg,
        onTap: () => Navigator.of(context).push(
          _smoothRoute(const InventoryScreen()),
        ),
      ),
      _CardData(
        title: 'MY SHOPPING LIST',
        subtitle: 'Plan your next grocery run',
        imageUrl: _shoppingImg,
        onTap: () => _showComingSoon(context, 'Shopping List'),
      ),
      _CardData(
        title: 'RECIPES',
        subtitle: 'Discover meals from what you have',
        imageUrl: _recipesImg,
        onTap: () => _showComingSoon(context, 'Recipes'),
      ),
      _CardData(
        title: 'COOKING',
        subtitle: 'Step-by-step guided cooking',
        imageUrl: _cookingImg,
        onTap: () => _showComingSoon(context, 'Cooking'),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF212121),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Header(onSignOut: () => _signOut(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              child: Column(
                children: [
                  for (final card in cards) ...[
                    _DashboardCard(data: card),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 16, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WELCOME BACK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.45),
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Smart Fridge',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Profile / settings icon
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'signout') onSignOut();
            },
            color: const Color(0xFF2C2C2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            offset: const Offset(0, 52),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              child: Icon(
                Icons.person_rounded,
                color: Colors.white.withOpacity(0.7),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dashboard card ────────────────────────────────────────────────────────────

class _DashboardCard extends StatefulWidget {
  const _DashboardCard({required this.data});

  final _CardData data;

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.965).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.data.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: _buildCard(),
      ),
    );
  }

  Widget _buildCard() {
    return SizedBox(
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background photo ──────────────────────────────────────────
            Image.network(
              widget.data.imageUrl,
              fit: BoxFit.cover,
              // Skeleton while loading
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(color: const Color(0xFF2C2C2E));
              },
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF2C2C2E)),
            ),

            // ── Dark gradient overlay for legibility ──────────────────────
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.20),
                    Colors.black.withOpacity(0.72),
                  ],
                ),
              ),
            ),

            // ── Solid tint so even bright images stay readable ────────────
            ColoredBox(color: Colors.black.withOpacity(0.18)),

            // ── Text content (bottom-left) ────────────────────────────────
            Positioned(
              left: 20,
              right: 56,
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.data.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.4,
                      height: 1.1,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.data.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withOpacity(0.72),
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),

            // ── Arrow indicator (bottom-right) ────────────────────────────
            Positioned(
              right: 18,
              bottom: 18,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.25),
                  ),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
