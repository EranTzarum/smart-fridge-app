/// Represents a single row from the `fridge_items` Supabase table.
class FridgeItem {
  final String id;
  final String itemName;

  /// Quantity stored as a string to support values like "2 packs" or "500 ml".
  final String quantity;

  /// Nullable — not every item may have a tracked expiry date.
  final DateTime? expiryDate;

  const FridgeItem({
    required this.id,
    required this.itemName,
    required this.quantity,
    this.expiryDate,
  });

  factory FridgeItem.fromMap(Map<String, dynamic> map) {
    return FridgeItem(
      id: map['id'].toString(),
      itemName: map['item_name'] as String? ?? 'Unknown item',
      quantity: map['quantity']?.toString() ?? '—',
      expiryDate: map['expiry_date'] != null
          ? DateTime.tryParse(map['expiry_date'].toString())
          : null,
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
    if (days < 3) return ExpiryStatus.critical; // expiring in < 3 days → red
    if (days < 7) return ExpiryStatus.warning;  // expiring in < 7 days → amber
    return ExpiryStatus.fresh;
  }
}

enum ExpiryStatus { fresh, warning, critical, expired, unknown }
