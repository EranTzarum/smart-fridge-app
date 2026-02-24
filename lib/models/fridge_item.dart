/// All supported item categories shown in the add/edit form.
///
/// Each category has a matching default expiry in [kCategoryDefaultExpiry] and
/// an icon in [_FridgeItemTile._iconFor] (inventory_screen.dart).
const kFridgeCategories = [
  'מוצרי חלב',    // Dairy          → 8 days
  'בשר ודגים',    // Meat & Fish    → 90 days
  'ירקות ופירות', // Veg & Fruit    → 7 days
  'ביצים',        // Eggs           → 14 days
  'לחם ומאפים',   // Bread          → 5 days
  'שאריות',       // Leftovers      → 3 days
  'קפואים',       // Frozen         → 90 days
  'משקאות',       // Beverages      → 365 days
  'מזווה',        // Pantry         → 365 days
  'אחר',          // Other          → 7 days
];

/// Represents a single row from the `fridge_items` Supabase table.
class FridgeItem {
  final String id;
  final String itemName;

  /// Quantity stored as a string to support values like "2 packs" or "500 ml".
  final String quantity;

  /// Optional grouping label (e.g. "Dairy", "Vegetables").
  final String? category;

  /// Nullable — not every item may have a tracked expiry date.
  final DateTime? expiryDate;

  const FridgeItem({
    required this.id,
    required this.itemName,
    required this.quantity,
    this.category,
    this.expiryDate,
  });

  factory FridgeItem.fromMap(Map<String, dynamic> map) {
    return FridgeItem(
      id: map['id'].toString(),
      itemName: map['item_name'] as String? ?? 'Unknown item',
      quantity: map['quantity']?.toString() ?? '—',
      category: map['category'] as String?,
      expiryDate: map['expiry_date'] != null
          ? DateTime.tryParse(map['expiry_date'].toString())
          : null,
    );
  }

  /// Returns a copy with overridden fields.
  /// Passing `null` keeps the original value (cannot clear a nullable field).
  FridgeItem copyWith({
    String? itemName,
    String? quantity,
    String? category,
    DateTime? expiryDate,
  }) {
    return FridgeItem(
      id: id,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      category: category ?? this.category,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }

  /// Returns how many whole days remain until [expiryDate], relative to today.
  /// Returns `null` when [expiryDate] is not set.
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final expiry = DateTime(
      expiryDate!.year,
      expiryDate!.month,
      expiryDate!.day,
    );
    return expiry.difference(today).inDays;
  }

  /// Classifies the item's freshness for UI colouring.
  ExpiryStatus get expiryStatus {
    final days = daysUntilExpiry;
    if (days == null) return ExpiryStatus.unknown;
    if (days < 0) return ExpiryStatus.expired;
    if (days < 3) return ExpiryStatus.critical; // < 3 days → red
    if (days < 7) return ExpiryStatus.warning;  // < 7 days → amber
    return ExpiryStatus.fresh;
  }
}

enum ExpiryStatus { fresh, warning, critical, expired, unknown }
