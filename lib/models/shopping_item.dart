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

  /// How many units of this item are needed.
  /// Defaults to `1.0` when the DB column is null.
  final double quantity;

  const ShoppingItem({
    required this.id,
    required this.itemName,
    required this.userId,
    required this.status,
    required this.category,
    this.quantity = 1.0,
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
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// Creates a copy with overridden fields.
  ShoppingItem copyWith({
    String? status,
    String? category,
    double? quantity,
  }) {
    return ShoppingItem(
      id: id,
      itemName: itemName,
      userId: userId,
      status: status ?? this.status,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
    );
  }

  /// Convenience getter used throughout the UI for rendering logic.
  bool get isBought => status == 'bought';
}
