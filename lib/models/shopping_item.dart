/// Default category used when an item has no category set.
const kDefaultShoppingCategory = 'כללי';

/// Represents a single row from the `smart_shopping_list` Supabase table.
class ShoppingItem {
  final String id;
  final String itemName;
  final String userId;

  /// `'pending'` or `'bought'`. Drives the check-off visual in the UI.
  final String status;

  /// The grouping category stored in the DB `category` column.
  /// Defaults to [kDefaultShoppingCategory] when the column is null.
  final String category;

  const ShoppingItem({
    required this.id,
    required this.itemName,
    required this.userId,
    required this.status,
    required this.category,
  });

  factory ShoppingItem.fromMap(Map<String, dynamic> map) {
    return ShoppingItem(
      id: map['id'].toString(),
      itemName: map['item_name'] as String? ?? 'Unknown item',
      userId: map['user_id'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      category:
          (map['category'] as String?)?.trim().isNotEmpty == true
              ? map['category'] as String
              : kDefaultShoppingCategory,
    );
  }

  /// Creates a copy with overridden fields.
  ShoppingItem copyWith({String? status, String? category}) {
    return ShoppingItem(
      id: id,
      itemName: itemName,
      userId: userId,
      status: status ?? this.status,
      category: category ?? this.category,
    );
  }

  /// Convenience getter used throughout the UI for rendering logic.
  bool get isBought => status == 'bought';
}
