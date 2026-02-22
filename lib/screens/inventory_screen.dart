import 'package:flutter/material.dart';

import '../models/fridge_item.dart';
import '../services/fridge_service.dart';

/// Displays the user's current fridge inventory in real time via a Supabase
/// stream. Pull-to-refresh triggers a one-shot server round-trip that confirms
/// the stream is up to date.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _fridgeService = FridgeService();

  late final Stream<List<FridgeItem>> _itemStream;

  @override
  void initState() {
    super.initState();
    _itemStream = _fridgeService.watchActiveItems();
  }

  Future<void> _refresh() => _fridgeService.fetchActiveItems();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: Colors.white70,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00C896).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.kitchen_rounded,
                color: Color(0xFF00C896),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'My Fridge',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<FridgeItem>>(
        stream: _itemStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00C896)),
            );
          }

          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error.toString());
          }

          final items = snapshot.data ?? [];

          return RefreshIndicator(
            onRefresh: _refresh,
            color: const Color(0xFF00C896),
            backgroundColor: const Color(0xFF1A1D27),
            child: items.isEmpty
                ? _EmptyState(cs: cs)
                : _ItemList(items: items, cs: cs),
          );
        },
      ),
    );
  }
}

// ── Subwidgets ───────────────────────────────────────────────────────────────

class _ItemList extends StatelessWidget {
  const _ItemList({required this.items, required this.cs});

  final List<FridgeItem> items;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _FridgeItemTile(item: items[i], cs: cs),
    );
  }
}

class _FridgeItemTile extends StatelessWidget {
  const _FridgeItemTile({required this.item, required this.cs});

  final FridgeItem item;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF00C896).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lunch_dining_rounded,
              color: Color(0xFF00C896),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Qty: ${item.quantity}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _ExpiryBadge(item: item),
        ],
      ),
    );
  }
}

class _ExpiryBadge extends StatelessWidget {
  const _ExpiryBadge({required this.item});

  final FridgeItem item;

  static const _red = Color(0xFFFF4C4C);
  static const _amber = Color(0xFFFFB830);
  static const _green = Color(0xFF00C896);
  static const _grey = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  (String, Color) _resolve() {
    final days = item.daysUntilExpiry;

    return switch (item.expiryStatus) {
      ExpiryStatus.expired  => ('Expired', _red),
      ExpiryStatus.critical => (
          days == 0 ? 'Today' : 'In $days day${days == 1 ? '' : 's'}',
          _red,
        ),
      ExpiryStatus.warning  => ('In $days days', _amber),
      ExpiryStatus.fresh    => ('In $days days', _green),
      ExpiryStatus.unknown  => ('No date', _grey),
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: const Color(0xFF00C896).withOpacity(0.3),
              ),
              const SizedBox(height: 18),
              const Text(
                'Your fridge is empty.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Add items to start tracking inventory.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 52,
            color: Colors.red.withOpacity(0.6),
          ),
          const SizedBox(height: 16),
          const Text(
            'Could not load items',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.45),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
