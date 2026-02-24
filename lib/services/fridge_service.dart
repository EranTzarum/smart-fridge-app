import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fridge_item.dart';

/// Handles all data access for the `fridge_items` Supabase table.
///
/// Every read and write is scoped to the currently authenticated user via
/// the `user_id` column.  If no session exists the service returns empty
/// results rather than throwing, letting the UI fail gracefully.
class FridgeService {
  final SupabaseClient _client = Supabase.instance.client;

  /// The authenticated user's UUID, or `null` when not signed in.
  String? get _userId => _client.auth.currentUser?.id;

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Real-time [Stream] of this user's active fridge items, sorted by the
  /// nearest expiry date first (no-date items last).
  ///
  /// Returns an empty stream when there is no authenticated user rather than
  /// throwing, so the UI receives an empty list and shows the empty state.
  ///
  /// Note: `.stream()` in this SDK version does not support chained `.eq()`
  /// calls, so filtering is applied client-side inside `.map()`. Row-Level
  /// Security on the Supabase table is the authoritative access boundary;
  /// the client-side filter is a belt-and-suspenders guard.
  Stream<List<FridgeItem>> watchActiveItems() {
    final userId = _userId;
    if (userId == null) return Stream.value([]);

    return _client
        .from('fridge_items')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final active = rows.where((row) =>
              row['user_id'] == userId && row['status'] == 'active');
          return _toSortedItems(active.toList());
        });
  }

  /// One-shot REST fetch. Used by the initial load and pull-to-refresh so
  /// the screen has data even when the Realtime WebSocket is unhealthy.
  Future<List<FridgeItem>> fetchActiveItems() async {
    final userId = _userId;
    if (userId == null) return [];

    final rows = await _client
        .from('fridge_items')
        .select()
        .eq('user_id', userId)
        .eq('status', 'active');

    return _toSortedItems(rows);
  }

  // ── Create ────────────────────────────────────────────────────────────────

  /// Inserts a new item for the current user and returns the created row.
  ///
  /// [expiryDays] is converted to an absolute date relative to today.
  /// Throws if there is no authenticated user.
  Future<FridgeItem> addItem({
    required String itemName,
    required String quantity,
    String? category,
    int? expiryDays,
  }) async {
    final userId = _userId;
    if (userId == null) throw StateError('No authenticated user.');

    final today = DateTime.now();
    final purchaseDate = _toDateString(today);
    final expiryDate = (expiryDays != null && expiryDays > 0)
        ? _toDateString(today.add(Duration(days: expiryDays)))
        : purchaseDate; // fall back to today so the NOT NULL constraint is met

    final row = await _client
        .from('fridge_items')
        .insert({
          'item_name': itemName.trim(),
          'quantity': quantity.trim(),
          'category': category,
          'purchase_date': purchaseDate,
          'expiry_date': expiryDate,
          'status': 'active',
          'user_id': userId,
        })
        .select()
        .single();

    return FridgeItem.fromMap(row);
  }

  // ── Update ────────────────────────────────────────────────────────────────

  /// Updates mutable fields of an existing item and returns the updated row.
  ///
  /// Only non-null arguments are written.  The `user_id` filter ensures a
  /// user can never modify another user's rows.
  Future<FridgeItem> updateItem({
    required String id,
    String? itemName,
    String? quantity,
    String? category,
    int? expiryDays,
  }) async {
    final userId = _userId;
    if (userId == null) throw StateError('No authenticated user.');

    final updates = <String, dynamic>{};
    if (itemName != null) updates['item_name'] = itemName.trim();
    if (quantity != null) updates['quantity'] = quantity.trim();
    if (category != null) updates['category'] = category;
    if (expiryDays != null) {
      updates['expiry_date'] = expiryDays > 0
          ? _toDateString(DateTime.now().add(Duration(days: expiryDays)))
          : null;
    }

    final row = await _client
        .from('fridge_items')
        .update(updates)
        .eq('id', id)
        .eq('user_id', userId)
        .select()
        .single();

    return FridgeItem.fromMap(row);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  /// Permanently removes an item.  The `user_id` guard prevents cross-user
  /// deletion even if the client sends an arbitrary id.
  Future<void> deleteItem(String id) async {
    final userId = _userId;
    if (userId == null) throw StateError('No authenticated user.');

    await _client
        .from('fridge_items')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// `YYYY-MM-DD` string suitable for a Supabase `date` column.
  String _toDateString(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  /// Converts raw Supabase rows into [FridgeItem] objects, sorted so items
  /// expiring soonest appear at the top and items without a date appear last.
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
