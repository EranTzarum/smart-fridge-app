import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fridge_item.dart';

/// Handles all data access for the `fridge_items` Supabase table.
class FridgeService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Returns a real-time [Stream] of active fridge items, ordered by the
  /// nearest expiry date first (nulls last, handled client-side).
  ///
  /// Supabase real-time will push a new list whenever the underlying table
  /// row(s) change, so the UI stays in sync without manual polling.
  Stream<List<FridgeItem>> watchActiveItems() {
    return _client
        .from('fridge_items')
        .stream(primaryKey: ['id'])
        .eq('status', 'active')
        .map(_toSortedItems);
  }

  /// One-shot fetch used by the pull-to-refresh gesture to force a server
  /// round-trip and confirm the stream is up to date.
  Future<List<FridgeItem>> fetchActiveItems() async {
    final rows = await _client
        .from('fridge_items')
        .select()
        .eq('status', 'active');

    return _toSortedItems(rows);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Converts raw Supabase rows into [FridgeItem] objects and sorts them so
  /// items expiring soonest appear at the top, with no-expiry items last.
  List<FridgeItem> _toSortedItems(List<Map<String, dynamic>> rows) {
    final items = rows.map(FridgeItem.fromMap).toList();
    items.sort((a, b) {
      if (a.expiryDate == null && b.expiryDate == null) return 0;
      if (a.expiryDate == null) return 1;
      if (b.expiryDate == null) return -1;
      return a.expiryDate!.compareTo(b.expiryDate!);
    });
    return items;
  }
}
