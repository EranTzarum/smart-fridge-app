import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/fridge_item.dart';
import '../services/fridge_service.dart';

// ── Realtime connection status ───────────────────────────────────────────────

enum _RealtimeStatus { connecting, live, degraded }

// ── Screen ───────────────────────────────────────────────────────────────────

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _fridgeService = FridgeService();

  List<FridgeItem> _items = [];
  bool _isInitialLoading = true;
  String? _fatalError;
  _RealtimeStatus _realtimeStatus = _RealtimeStatus.connecting;
  StreamSubscription<List<FridgeItem>>? _realtimeSub;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initialFetch();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  // ── Data fetching ─────────────────────────────────────────────────────────

  Future<void> _initialFetch() async {
    try {
      final items = await _fridgeService.fetchActiveItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fatalError = e.toString();
        _isInitialLoading = false;
      });
    }
  }

  void _subscribeRealtime() {
    _realtimeSub = _fridgeService.watchActiveItems().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _items = items;
          _realtimeStatus = _RealtimeStatus.live;
        });
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('[Realtime] Subscription error — degraded mode.\n  $error');
        if (kDebugMode) debugPrintStack(stackTrace: stack, maxFrames: 6);
        if (!mounted) return;
        setState(() => _realtimeStatus = _RealtimeStatus.degraded);
      },
      cancelOnError: false,
    );
  }

  Future<void> _refresh() async {
    try {
      final items = await _fridgeService.fetchActiveItems();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Refresh failed: $e', isError: true, retryAction: _refresh);
    }
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> _addItem(_ItemFormData data) async {
    try {
      final newItem = await _fridgeService.addItem(
        itemName: data.itemName,
        quantity: data.quantity,
        category: data.category,
        expiryDays: data.expiryDays,
      );
      // Optimistic insert — realtime will reconcile if connected.
      if (!mounted) return;
      setState(() {
        _items = [newItem, ..._items];
        _items.sort(_expirySort);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Could not add item: $e', isError: true);
    }
  }

  Future<void> _updateItem(FridgeItem original, _ItemFormData data) async {
    // Optimistic update — swap in the new values immediately.
    final optimistic = original.copyWith(
      itemName: data.itemName,
      quantity: data.quantity,
      category: data.category,
    );
    setState(() {
      final idx = _items.indexWhere((i) => i.id == original.id);
      if (idx != -1) _items[idx] = optimistic;
    });

    try {
      final confirmed = await _fridgeService.updateItem(
        id: original.id,
        itemName: data.itemName,
        quantity: data.quantity,
        category: data.category,
        expiryDays: data.expiryDays,
      );
      // Replace optimistic copy with the server-confirmed row.
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((i) => i.id == confirmed.id);
        if (idx != -1) _items[idx] = confirmed;
      });
    } catch (e) {
      // Revert to the original on failure.
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((i) => i.id == original.id);
        if (idx != -1) _items[idx] = original;
      });
      _showSnackbar('Could not update item: $e', isError: true);
    }
  }

  /// Optimistic delete: remove locally, call DB, restore on failure.
  /// On success shows a snackbar with an Undo action.
  Future<void> _deleteItem(FridgeItem item, int index) async {
    // Remove immediately so the UI feels instant.
    setState(() => _items.removeWhere((i) => i.id == item.id));

    try {
      await _fridgeService.deleteItem(item.id);
      if (!mounted) return;

      // Success — offer a one-tap undo within the snackbar duration.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('"${item.itemName}" deleted'),
            backgroundColor: const Color(0xFF1A1D27),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              textColor: const Color(0xFF00C896),
              onPressed: () => _undoDelete(item),
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      // Restore the item at its original position on failure.
      setState(() {
        final insertAt = index.clamp(0, _items.length);
        _items.insert(insertAt, item);
      });
      _showSnackbar('Could not delete "${item.itemName}": $e', isError: true);
    }
  }

  /// Re-inserts a previously deleted item (called by the Undo snackbar action).
  Future<void> _undoDelete(FridgeItem item) async {
    try {
      final restored = await _fridgeService.addItem(
        itemName: item.itemName,
        quantity: item.quantity,
        category: item.category,
        expiryDays: item.daysUntilExpiry,
      );
      if (!mounted) return;
      setState(() {
        _items = [restored, ..._items];
        _items.sort(_expirySort);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Could not undo: $e', isError: true);
    }
  }

  // ── Sheet helpers ─────────────────────────────────────────────────────────

  Future<void> _showAddSheet() async {
    final data = await showModalBottomSheet<_ItemFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ItemFormSheet(),
    );
    if (data != null) await _addItem(data);
  }

  Future<void> _showEditSheet(FridgeItem item) async {
    final data = await showModalBottomSheet<_ItemFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemFormSheet(item: item),
    );
    if (data != null) await _updateItem(item, data);
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  void _showSnackbar(
    String message, {
    bool isError = false,
    VoidCallback? retryAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFF2A1A1A) : const Color(0xFF1A2A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        action: retryAction != null
            ? SnackBarAction(
                label: 'Retry',
                textColor: const Color(0xFFFF4C4C),
                onPressed: retryAction,
              )
            : null,
      ),
    );
  }

  static int _expirySort(FridgeItem a, FridgeItem b) {
    if (a.expiryDate == null && b.expiryDate == null) return 0;
    if (a.expiryDate == null) return 1;
    if (b.expiryDate == null) return -1;
    return a.expiryDate!.compareTo(b.expiryDate!);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _isInitialLoading ? null : _buildFab(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
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
            child: const Icon(Icons.kitchen_rounded,
                color: Color(0xFF00C896), size: 18),
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
      actions: [
        _RealtimeStatusChip(status: _realtimeStatus),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _showAddSheet,
      backgroundColor: const Color(0xFF00C896),
      foregroundColor: Colors.black,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00C896)));
    }

    if (_fatalError != null && _items.isEmpty) {
      return _FatalErrorState(error: _fatalError!, onRetry: _initialFetch);
    }

    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF00C896),
      backgroundColor: const Color(0xFF1A1D27),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_realtimeStatus == _RealtimeStatus.degraded)
            const SliverToBoxAdapter(child: _DegradedBanner()),

          if (_items.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(onAdd: _showAddSheet),
            )
          else
            SliverPadding(
              // Extra bottom padding so FAB never obscures the last item.
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              sliver: SliverList.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final item = _items[i];
                  return Dismissible(
                    key: ValueKey(item.id),
                    direction: DismissDirection.endToStart,
                    // Empty primary background (we only allow left-swipe).
                    background: const SizedBox.shrink(),
                    secondaryBackground: const _DeleteSlideBackground(),
                    onDismissed: (_) => _deleteItem(item, i),
                    child: _FridgeItemTile(
                      item: item,
                      cs: cs,
                      onTap: () => _showEditSheet(item),
                      onDelete: () => _deleteItem(item, i),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Delete slide background ───────────────────────────────────────────────────

class _DeleteSlideBackground extends StatelessWidget {
  const _DeleteSlideBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4C4C).withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF4C4C).withOpacity(0.35)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded,
              color: Color(0xFFFF4C4C), size: 24),
          SizedBox(height: 4),
          Text(
            'Delete',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF4C4C),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Item tile ─────────────────────────────────────────────────────────────────

class _FridgeItemTile extends StatelessWidget {
  const _FridgeItemTile({
    required this.item,
    required this.cs,
    required this.onTap,
    required this.onDelete,
  });

  final FridgeItem item;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Maps Hebrew category names to icons for a small visual hint.
  static IconData _iconFor(String? category) => switch (category) {
        'מוצרי חלב'    => Icons.egg_alt_rounded,
        'בשר ודגים'    => Icons.set_meal_rounded,
        'ירקות ופירות' => Icons.eco_rounded,
        'ביצים'        => Icons.egg_alt_rounded,
        'לחם ומאפים'   => Icons.bakery_dining_rounded,
        'שאריות'       => Icons.lunch_dining_rounded,
        'קפואים'       => Icons.ac_unit_rounded,
        'משקאות'       => Icons.local_drink_rounded,
        'מזווה'        => Icons.inventory_2_rounded,
        _              => Icons.category_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            // Category icon avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF00C896).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconFor(item.category),
                color: const Color(0xFF00C896),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

            // Name, category label, quantity
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
                  Row(
                    children: [
                      Text(
                        'Qty: ${item.quantity}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.45),
                        ),
                      ),
                      if (item.category != null) ...[
                        Text(
                          '  ·  ',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.2),
                              fontSize: 12),
                        ),
                        Text(
                          item.category!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.35),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),
            _ExpiryBadge(item: item),

            // Explicit delete button — always visible, no need to discover swipe.
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              iconSize: 20,
              color: const Color(0xFFFF4C4C).withOpacity(0.6),
              tooltip: 'Delete item',
              splashRadius: 20,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Expiry badge ──────────────────────────────────────────────────────────────

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

// ── Add / Edit bottom sheet ───────────────────────────────────────────────────

/// Form data returned by [_ItemFormSheet] via `Navigator.pop`.
typedef _ItemFormData = ({
  String itemName,
  String quantity,
  String? category,
  int? expiryDays,
});

/// A modal bottom sheet used for both adding new items and editing existing
/// ones.  Pass [item] to pre-fill the form fields (edit mode).
class _ItemFormSheet extends StatefulWidget {
  const _ItemFormSheet({this.item});

  /// When non-null the sheet is in edit mode and its fields are pre-filled.
  final FridgeItem? item;

  @override
  State<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<_ItemFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _expiryCtrl;
  String? _selectedCategory;
  bool _isSaving = false;

  bool get _isEditMode => widget.item != null;

  /// Returns the recommended shelf-life in days for a given category.
  /// Used to auto-populate the expiry field when a category is selected.
  static int _defaultExpiryFor(String? category) => switch (category) {
        'בשר ודגים'                => 90,
        'מזווה' || 'משקאות'        => 365,
        'קפואים'                   => 90,
        'מוצרי חלב'                => 8,
        'ביצים'                    => 14,
        'לחם ומאפים'               => 5,
        'שאריות'                   => 3,
        _                          => 7,
      };

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?.itemName ?? '');
    _qtyCtrl = TextEditingController(text: item?.quantity ?? '');
    _expiryCtrl = TextEditingController(
      text: item?.daysUntilExpiry?.toString() ?? '',
    );
    _selectedCategory = item?.category;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final expiryText = _expiryCtrl.text.trim();
    // If the field is empty, use the category default so the DB never
    // receives a null expiry (which would violate the NOT NULL constraint).
    final expiryDays = expiryText.isNotEmpty
        ? int.tryParse(expiryText)
        : _defaultExpiryFor(_selectedCategory);

    Navigator.of(context).pop<_ItemFormData>((
      itemName: _nameCtrl.text.trim(),
      quantity: _qtyCtrl.text.trim(),
      category: _selectedCategory,
      expiryDays: expiryDays,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Account for the soft keyboard pushing the sheet up.
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D27),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomPadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              _isEditMode ? 'Edit Item' : 'Add Item',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 24),

            Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildField(
                    controller: _nameCtrl,
                    label: 'Item name',
                    icon: Icons.label_outline_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Item name is required.'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  // Category dropdown
                  _buildDropdown(),
                  const SizedBox(height: 14),

                  _buildField(
                    controller: _qtyCtrl,
                    label: 'Quantity (e.g. 2, 500 ml)',
                    icon: Icons.numbers_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Quantity is required.'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  _buildField(
                    controller: _expiryCtrl,
                    label: 'Expires in (days) — optional',
                    icon: Icons.event_rounded,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 0) {
                        return 'Enter a valid number of days.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      const Color(0xFF00C896).withOpacity(0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _isEditMode ? 'Save Changes' : 'Add to Fridge',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
        prefixIcon: Icon(icon,
            color: Colors.white.withOpacity(0.3), size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00C896), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF4C4C)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFFF4C4C), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      hint: Text('Category — optional',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
      dropdownColor: const Color(0xFF252833),
      icon: Icon(Icons.keyboard_arrow_down_rounded,
          color: Colors.white.withOpacity(0.3)),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.category_outlined,
            color: Colors.white.withOpacity(0.3), size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00C896), width: 1.5),
        ),
      ),
      items: kFridgeCategories
          .map((c) => DropdownMenuItem(
                value: c,
                child: Text(c),
              ))
          .toList(),
      onChanged: (v) {
        setState(() => _selectedCategory = v);
        // Auto-fill the expiry field in add mode so the user sees a
        // sensible default immediately. In edit mode we leave the existing
        // expiry untouched — the user can still change it manually.
        if (!_isEditMode && v != null) {
          _expiryCtrl.text = _defaultExpiryFor(v).toString();
        }
      },
    );
  }
}

// ── Supporting stateless widgets ──────────────────────────────────────────────

class _RealtimeStatusChip extends StatelessWidget {
  const _RealtimeStatusChip({required this.status});
  final _RealtimeStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      _RealtimeStatus.live => _chip(
          label: 'LIVE',
          color: const Color(0xFF00C896),
          icon: Icons.circle,
          iconSize: 6,
        ),
      _RealtimeStatus.degraded => _chip(
          label: 'OFFLINE',
          color: const Color(0xFFFFB830),
          icon: Icons.wifi_off_rounded,
          iconSize: 12,
        ),
      _RealtimeStatus.connecting => const SizedBox.shrink(),
    };
  }

  Widget _chip({
    required String label,
    required Color color,
    required IconData icon,
    required double iconSize,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _DegradedBanner extends StatelessWidget {
  const _DegradedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB830).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFFFB830).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 16, color: Color(0xFFFFB830)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live updates paused — showing last known data. Pull down to refresh.',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFFFFB830).withOpacity(0.9),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          'Tap the + button to add your first item.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add Item'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00C896),
            side: BorderSide(
                color: const Color(0xFF00C896).withOpacity(0.5)),
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _FatalErrorState extends StatelessWidget {
  const _FatalErrorState({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 56, color: Colors.red.withOpacity(0.55)),
          const SizedBox(height: 20),
          const Text(
            'Could not load items',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(
                fontSize: 12, color: Colors.white.withOpacity(0.4)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Try Again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00C896),
              side: BorderSide(
                  color: const Color(0xFF00C896).withOpacity(0.5)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
