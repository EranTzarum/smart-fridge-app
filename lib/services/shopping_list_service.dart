import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shopping_item.dart';

/// Handles all data access for the `smart_shopping_list` Supabase table.
///
/// Every read and write is scoped to the currently authenticated user via
/// the `user_id` column. RLS on the table is the authoritative access guard.
class ShoppingListService {
  final SupabaseClient _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Real-time [Stream] of ALL of this user's shopping items (pending + bought).
  ///
  /// The screen is responsible for rendering each status differently.
  /// The SDK `.stream()` does not support chained `.eq()`, so the user_id
  /// filter is applied client-side inside `.map()`.
  Stream<List<ShoppingItem>> watchAllItems() {
    final userId = _userId;
    if (userId == null) return Stream.value([]);

    return _client
        .from('smart_shopping_list')
        .stream(primaryKey: ['id'])
        .map((rows) => rows
            .where((r) => r['user_id'] == userId)
            .map(ShoppingItem.fromMap)
            .toList());
  }

  /// One-shot REST fetch of ALL items (pending + bought).
  Future<List<ShoppingItem>> fetchAllItems() async {
    final userId = _userId;
    if (userId == null) return [];

    final rows = await _client
        .from('smart_shopping_list')
        .select()
        .eq('user_id', userId);

    return rows.map(ShoppingItem.fromMap).toList();
  }

  // ── Create ─────────────────────────────────────────────────────────────────

  /// Inserts a new pending item with [category] and returns the created row.
  Future<ShoppingItem> addItem(String itemName, String category) async {
    final userId = _userId;
    if (userId == null) throw StateError('No authenticated user.');

    final row = await _client
        .from('smart_shopping_list')
        .insert({
          'item_name': itemName.trim(),
          'user_id': userId,
          'status': 'pending',
          'category': category,
        })
        .select()
        .single();

    return ShoppingItem.fromMap(row);
  }

  // ── Update ─────────────────────────────────────────────────────────────────

  /// Marks an item as `'bought'`.
  Future<void> markAsBought(String id) async {
    final userId = _userId;
    if (userId == null) throw StateError('No authenticated user.');

    await _client
        .from('smart_shopping_list')
        .update({'status': 'bought'})
        .eq('id', id)
        .eq('user_id', userId);
  }

  /// Reverts an item from `'bought'` back to `'pending'`.
  Future<void> markAsPending(String id) async {
    final userId = _userId;
    if (userId == null) throw StateError('No authenticated user.');

    await _client
        .from('smart_shopping_list')
        .update({'status': 'pending'})
        .eq('id', id)
        .eq('user_id', userId);
  }

  /// PATCHes the item's `category` column immediately when the user
  /// moves an item to a different category.
  Future<void> updateCategory(String id, String category) async {
    final userId = _userId;
    if (userId == null) throw StateError('No authenticated user.');

    await _client
        .from('smart_shopping_list')
        .update({'category': category})
        .eq('id', id)
        .eq('user_id', userId);
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// Permanently removes an item from the database.
  Future<void> deleteItem(String id) async {
    final userId = _userId;
    if (userId == null) throw StateError('No authenticated user.');

    await _client
        .from('smart_shopping_list')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }
}
