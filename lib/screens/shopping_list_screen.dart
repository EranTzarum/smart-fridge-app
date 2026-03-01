import 'dart:async';

import 'package:flutter/material.dart';

import '../models/shopping_item.dart';
import '../services/shopping_list_service.dart';

// ── Theme constants ───────────────────────────────────────────────────────────

const _kAccent    = Color(0xFFFFB830);
const _kBg        = Color(0xFF0D0F14);
const _kCard      = Color(0xFF1A1D27);
const _kInnerCard = Color(0xFF141620);

/// All available categories the user can assign to an item.
const kShoppingCategories = <String>[
  'כללי',
  'מוצרי חלב',
  'בשר ודגים',
  'ירקות ופירות',
  'מזון יבש',
  'ניקיון',
  'קפואים',
  'משקאות',
];

/// Visual metadata per category: accent colour + icon.
const _kCategoryMeta = <String, ({Color color, IconData icon})>{
  'כללי':          (color: Color(0xFFFFB830), icon: Icons.shopping_bag_outlined),
  'מוצרי חלב':    (color: Color(0xFF64B5F6), icon: Icons.egg_alt_rounded),
  'בשר ודגים':    (color: Color(0xFFEF9A9A), icon: Icons.set_meal_rounded),
  'ירקות ופירות': (color: Color(0xFF81C784), icon: Icons.eco_rounded),
  'מזון יבש':     (color: Color(0xFFFFCC80), icon: Icons.inventory_2_rounded),
  'ניקיון':       (color: Color(0xFF80DEEA), icon: Icons.cleaning_services_rounded),
  'קפואים':       (color: Color(0xFF90CAF9), icon: Icons.ac_unit_rounded),
  'משקאות':       (color: Color(0xFFCE93D8), icon: Icons.local_drink_rounded),
};

({Color color, IconData icon}) _metaFor(String category) =>
    _kCategoryMeta[category] ??
    (color: _kAccent, icon: Icons.shopping_bag_outlined);

// ── Screen ────────────────────────────────────────────────────────────────────

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final _service = ShoppingListService();

  // ── Grouped state ──────────────────────────────────────────────────────────
  // _grouped[category] → ordered list of items in that bucket.
  // _categoryOrder drives the render sequence.
  final Map<String, List<ShoppingItem>> _grouped = {};
  List<String> _categoryOrder = [];
  final Set<String> _collapsed = {};

  // IDs whose status/category DB write is in-flight.
  // _mergeItems skips these items so an optimistic local state is never
  // overwritten by a stale stream event arriving before the write completes.
  final Set<String> _pendingMutation = {};

  bool _isInitialLoading = true;
  String? _fatalError;
  StreamSubscription<List<ShoppingItem>>? _sub;

  // ── Computed ───────────────────────────────────────────────────────────────

  int get _totalItems =>
      _grouped.values.fold(0, (sum, list) => sum + list.length);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initialFetch();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _initialFetch() async {
    try {
      final items = await _service.fetchAllItems();
      if (!mounted) return;
      setState(() {
        _mergeItems(items);
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
    _sub = _service.watchAllItems().listen(
      (items) {
        if (!mounted) return;
        // Skip items whose local mutation is still in-flight to prevent flicker.
        setState(() => _mergeItems(
            items.where((i) => !_pendingMutation.contains(i.id)).toList()));
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> _refresh() async {
    try {
      final items = await _service.fetchAllItems();
      if (!mounted) return;
      setState(() => _mergeItems(items));
    } catch (e) {
      _showSnackbar('Refresh failed', isError: true);
    }
  }

  /// Merges a flat incoming list into [_grouped], preserving manual order and
  /// handling cross-category moves (an item appearing in a different bucket
  /// than where it currently sits).
  void _mergeItems(List<ShoppingItem> incoming) {
    final incomingIds = {for (final i in incoming) i.id};

    // Remove items that are no longer in the incoming set.
    for (final list in _grouped.values) {
      list.removeWhere((i) => !incomingIds.contains(i.id));
    }

    for (final item in incoming) {
      final cat = item.category;

      // If the item has moved to a different category (e.g. after a PATCH),
      // evict it from any other bucket first.
      for (final key in _grouped.keys.where((k) => k != cat)) {
        _grouped[key]?.removeWhere((i) => i.id == item.id);
      }

      final list = _grouped.putIfAbsent(cat, () => []);
      final idx = list.indexWhere((i) => i.id == item.id);
      if (idx == -1) {
        list.add(item);
      } else {
        list[idx] = item; // update in-place (status, name, etc.)
      }
      if (!_categoryOrder.contains(cat)) _categoryOrder.add(cat);
    }

    _pruneEmpty();
  }

  void _pruneEmpty() {
    _grouped.removeWhere((_, list) => list.isEmpty);
    _categoryOrder.removeWhere((cat) => !_grouped.containsKey(cat));
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Google Keep-style check-off: keeps the item visible in its category
  /// with a strikethrough, and offers an Undo snackbar that reverts to pending.
  Future<void> _checkOff(ShoppingItem item) async {
    final boughtItem = item.copyWith(status: 'bought');
    _pendingMutation.add(item.id);

    // Optimistic: flip to 'bought' in local state immediately.
    setState(() => _replaceInGroup(item.id, item.category, boughtItem));

    try {
      await _service.markAsBought(item.id);
      _pendingMutation.remove(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(_buildUndoSnackbar(
          '"${item.itemName}" checked off',
          onUndo: () => _uncheckItem(boughtItem),
        ));
    } catch (e) {
      _pendingMutation.remove(item.id);
      if (!mounted) return;
      // Revert to pending on failure.
      setState(() => _replaceInGroup(item.id, item.category, item));
      _showSnackbar('Could not check off "${item.itemName}"', isError: true);
    }
  }

  /// Reverts a bought item back to pending (called by the Undo action or by
  /// tapping the filled checkbox again).
  Future<void> _uncheckItem(ShoppingItem boughtItem) async {
    final pendingItem = boughtItem.copyWith(status: 'pending');
    _pendingMutation.add(boughtItem.id);

    // Optimistic: flip back to 'pending'.
    setState(
        () => _replaceInGroup(boughtItem.id, boughtItem.category, pendingItem));

    try {
      await _service.markAsPending(boughtItem.id);
      _pendingMutation.remove(boughtItem.id);
    } catch (e) {
      _pendingMutation.remove(boughtItem.id);
      if (!mounted) return;
      // Revert to bought on failure.
      setState(
          () => _replaceInGroup(boughtItem.id, boughtItem.category, boughtItem));
      _showSnackbar('Could not uncheck "${boughtItem.itemName}"', isError: true);
    }
  }

  /// Moves an item to [newCategory]: optimistic local move + DB PATCH.
  Future<void> _moveToCategory(ShoppingItem item, String newCategory) async {
    if (item.category == newCategory) return;

    final oldCat    = item.category;
    final movedItem = item.copyWith(category: newCategory);
    _pendingMutation.add(item.id);

    // Optimistic: remove from old bucket, insert into new bucket.
    setState(() {
      _grouped[oldCat]?.removeWhere((i) => i.id == item.id);
      _pruneEmpty();
      _grouped.putIfAbsent(newCategory, () => []).add(movedItem);
      if (!_categoryOrder.contains(newCategory)) {
        _categoryOrder.add(newCategory);
      }
    });

    try {
      await _service.updateCategory(item.id, newCategory);
      _pendingMutation.remove(item.id);
    } catch (e) {
      _pendingMutation.remove(item.id);
      if (!mounted) return;
      // Revert: move back to the original bucket.
      setState(() {
        _grouped[newCategory]?.removeWhere((i) => i.id == item.id);
        _pruneEmpty();
        _grouped.putIfAbsent(oldCat, () => []).add(item);
        if (!_categoryOrder.contains(oldCat)) _categoryOrder.add(oldCat);
      });
      _showSnackbar('Could not move "${item.itemName}"', isError: true);
    }
  }

  /// Optimistic delete with undo.
  Future<void> _deleteItem(ShoppingItem item) async {
    final cat     = item.category;
    final origIdx = _grouped[cat]?.indexWhere((i) => i.id == item.id) ?? -1;

    setState(() {
      _grouped[cat]?.removeWhere((i) => i.id == item.id);
      _pruneEmpty();
    });

    try {
      await _service.deleteItem(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(_buildUndoSnackbar(
          '"${item.itemName}" removed',
          onUndo: () => _undoDelete(item, cat, origIdx),
        ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final list = _grouped.putIfAbsent(cat, () => []);
        list.insert(origIdx.clamp(0, list.length), item);
        if (!_categoryOrder.contains(cat)) _categoryOrder.add(cat);
      });
      _showSnackbar('Could not delete "${item.itemName}"', isError: true);
    }
  }

  Future<void> _undoDelete(
      ShoppingItem item, String cat, int origIdx) async {
    try {
      final restored = await _service.addItem(item.itemName, cat);
      if (!mounted) return;
      setState(() {
        final list = _grouped.putIfAbsent(cat, () => []);
        list.insert(origIdx.clamp(0, list.length), restored);
        if (!_categoryOrder.contains(cat)) _categoryOrder.add(cat);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Could not undo', isError: true);
    }
  }

  Future<void> _addItem(String name, String category) async {
    try {
      final item = await _service.addItem(name, category);
      if (!mounted) return;
      setState(() {
        _grouped.putIfAbsent(category, () => []).insert(0, item);
        if (!_categoryOrder.contains(category)) _categoryOrder.add(category);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Could not add item', isError: true);
    }
  }

  // ── Local state helpers ────────────────────────────────────────────────────

  /// Replaces the item with [id] inside [category]'s bucket with [replacement].
  /// No-op when the item is not found.
  void _replaceInGroup(String id, String category, ShoppingItem replacement) {
    final idx = _grouped[category]?.indexWhere((i) => i.id == id) ?? -1;
    if (idx != -1) _grouped[category]![idx] = replacement;
  }

  // ── Reorder callbacks ──────────────────────────────────────────────────────

  void _onCategoryReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final cat = _categoryOrder.removeAt(oldIndex);
      _categoryOrder.insert(newIndex, cat);
    });
  }

  void _onItemReorder(String category, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final list = _grouped[category]!;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
    });
  }

  void _toggleCategory(String cat) => setState(() {
        if (_collapsed.contains(cat)) {
          _collapsed.remove(cat);
        } else {
          _collapsed.add(cat);
        }
      });

  // ── Dialog ────────────────────────────────────────────────────────────────

  Future<void> _showAddDialog() async {
    final result = await showDialog<({String name, String category})>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => const _AddItemDialog(),
    );
    if (result != null) await _addItem(result.name, result.category);
  }

  // ── Snackbar helpers ───────────────────────────────────────────────────────

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? const Color(0xFF2A1A1A) : _kCard,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    ));
  }

  SnackBar _buildUndoSnackbar(String message,
      {required VoidCallback onUndo}) {
    return SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: _kCard,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      duration: const Duration(seconds: 5),
      action:
          SnackBarAction(label: 'Undo', textColor: _kAccent, onPressed: onUndo),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
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
              color: _kAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shopping_cart_rounded,
                color: _kAccent, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            'My Shopping List',
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
        if (!_isInitialLoading && _totalItems > 0)
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kAccent.withOpacity(0.35)),
            ),
            child: Text(
              '$_totalItems',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kAccent,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _showAddDialog,
      backgroundColor: _kAccent,
      foregroundColor: Colors.black,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }

    if (_fatalError != null && _grouped.isEmpty) {
      return _FatalErrorState(error: _fatalError!, onRetry: _initialFetch);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: _kAccent,
      backgroundColor: _kCard,
      child: _grouped.isEmpty
          ? _EmptyState(onAdd: _showAddDialog)
          : _buildCategoryList(),
    );
  }

  Widget _buildCategoryList() {
    return ReorderableListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      buildDefaultDragHandles: false,
      onReorder: _onCategoryReorder,
      proxyDecorator: (child, _, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (_, __) => Material(
            elevation: 12,
            shadowColor: Colors.black54,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: child,
          ),
        );
      },
      children: [
        for (int i = 0; i < _categoryOrder.length; i++)
          _CategorySection(
            key: ValueKey(_categoryOrder[i]),
            index: i,
            category: _categoryOrder[i],
            items: _grouped[_categoryOrder[i]]!,
            isCollapsed: _collapsed.contains(_categoryOrder[i]),
            onToggle: () => _toggleCategory(_categoryOrder[i]),
            // Toggle: check pending items off, uncheck bought items.
            onItemToggleCheck: (item) =>
                item.isBought ? _uncheckItem(item) : _checkOff(item),
            onItemDelete: _deleteItem,
            onItemsReorder: (o, n) => _onItemReorder(_categoryOrder[i], o, n),
            onItemMoveCategory: (item, newCat) =>
                _moveToCategory(item, newCat),
          ),
      ],
    );
  }
}

// ── Category section ──────────────────────────────────────────────────────────

/// One collapsible / reorderable block for a single category.
///
/// The outer [ReorderableListView] owns the category-level drag handles
/// (forwarded via [index]). The inner [ReorderableListView] owns item-level
/// drag handles. The two contexts never conflict because each
/// [ReorderableDragStartListener] climbs to its nearest
/// [SliverReorderableList] ancestor.
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required super.key,
    required this.index,
    required this.category,
    required this.items,
    required this.isCollapsed,
    required this.onToggle,
    required this.onItemToggleCheck,
    required this.onItemDelete,
    required this.onItemsReorder,
    required this.onItemMoveCategory,
  });

  final int index;
  final String category;
  final List<ShoppingItem> items;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final void Function(ShoppingItem) onItemToggleCheck;
  final void Function(ShoppingItem) onItemDelete;
  final void Function(int oldIndex, int newIndex) onItemsReorder;
  final void Function(ShoppingItem item, String newCategory) onItemMoveCategory;

  @override
  Widget build(BuildContext context) {
    final meta = _metaFor(category);
    return Column(
      key: ValueKey('col_$category'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(meta),
        _buildItemsSection(meta),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildHeader(({Color color, IconData icon}) meta) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: isCollapsed
            ? BorderRadius.circular(14)
            : const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          // Coloured accent bar
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(
              color: meta.color,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                bottomLeft:
                    isCollapsed ? const Radius.circular(14) : Radius.zero,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(meta.icon, color: meta.color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              category,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
                letterSpacing: 0.1,
              ),
            ),
          ),
          // Item count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: meta.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${items.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: meta.color,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Collapse / expand chevron
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              child: AnimatedRotation(
                turns: isCollapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.white.withOpacity(0.45),
                ),
              ),
            ),
          ),
          // Category drag handle — targets the OUTER ReorderableListView.
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 14, 14),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 20,
                color: Colors.white.withOpacity(0.22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection(({Color color, IconData icon}) meta) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      child: isCollapsed
          ? const SizedBox.shrink()
          : Container(
              decoration: BoxDecoration(
                color: _kInnerCard,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border(
                  left: BorderSide(color: Colors.white.withOpacity(0.07)),
                  right: BorderSide(color: Colors.white.withOpacity(0.07)),
                  bottom: BorderSide(color: Colors.white.withOpacity(0.07)),
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: onItemsReorder,
                proxyDecorator: (child, _, animation) => Material(
                  color: Colors.transparent,
                  elevation: 6,
                  shadowColor: Colors.black38,
                  child: child,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => _ItemTile(
                  key: ValueKey(items[i].id),
                  item: items[i],
                  index: i,
                  isLast: i == items.length - 1,
                  accentColor: meta.color,
                  onToggleCheck: () => onItemToggleCheck(items[i]),
                  onDelete: () => onItemDelete(items[i]),
                  onMoveCategory: (newCat) =>
                      onItemMoveCategory(items[i], newCat),
                ),
              ),
            ),
    );
  }
}

// ── Item tile ─────────────────────────────────────────────────────────────────

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required super.key,
    required this.item,
    required this.index,
    required this.isLast,
    required this.accentColor,
    required this.onToggleCheck,
    required this.onDelete,
    required this.onMoveCategory,
  });

  final ShoppingItem item;
  final int index;
  final bool isLast;
  final Color accentColor;
  final VoidCallback onToggleCheck;
  final VoidCallback onDelete;

  /// Called with the newly selected category string after the user picks one.
  final void Function(String newCategory) onMoveCategory;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('tile_${item.id}'),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          // Item drag handle — targets the INNER ReorderableListView.
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 4, 18),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 18,
                color: Colors.white.withOpacity(0.18),
              ),
            ),
          ),

          // ── Circular check indicator ────────────────────────────────────
          GestureDetector(
            onTap: onToggleCheck,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
              child: item.isBought
                  // Filled circle with checkmark when bought.
                  ? Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor,
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 14, color: Colors.black),
                    )
                  // Empty circle when pending.
                  : Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accentColor.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                    ),
            ),
          ),

          // ── Item name — strikethrough + faded when bought ───────────────
          Expanded(
            child: Text(
              item.itemName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: item.isBought
                    ? Colors.white.withOpacity(0.38)
                    : Colors.white,
                letterSpacing: -0.1,
                decoration: item.isBought
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: Colors.white.withOpacity(0.38),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ── Quantity badge ──────────────────────────────────────────────
          _QtyBadge(
            quantity: item.quantity,
            color: item.isBought
                ? Colors.white.withOpacity(0.3)
                : accentColor,
          ),

          // ── Move-to-category icon ───────────────────────────────────────
          // Tapping opens a bottom sheet so the user can re-assign the item.
          // The PATCH fires immediately on selection.
          IconButton(
            onPressed: () async {
              final newCat = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) =>
                    _CategoryPickerSheet(current: item.category),
              );
              if (newCat != null && newCat != item.category) {
                onMoveCategory(newCat);
              }
            },
            icon: const Icon(Icons.label_outline_rounded),
            iconSize: 16,
            color: Colors.white.withOpacity(0.28),
            tooltip: 'Move to category',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            splashRadius: 18,
          ),

          // ── Prominent delete button ────────────────────────────────────
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            iconSize: 18,
            color: const Color(0xFFFF4C4C).withOpacity(0.55),
            tooltip: 'Delete item',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            splashRadius: 18,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Category picker sheet ─────────────────────────────────────────────────────

/// A bottom sheet listing all available categories so the user can move an
/// item. Returns the selected category string via [Navigator.pop].
class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D27),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.label_outline_rounded,
                    color: _kAccent, size: 18),
                const SizedBox(width: 10),
                const Text(
                  'Move to category',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2A2D3A)),
          ...kShoppingCategories.map((cat) {
            final meta     = _metaFor(cat);
            final isCurrent = cat == current;
            return InkWell(
              onTap: () => Navigator.of(context).pop(cat),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                decoration: isCurrent
                    ? BoxDecoration(
                        color: meta.color.withOpacity(0.08),
                      )
                    : null,
                child: Row(
                  children: [
                    Icon(meta.icon, color: meta.color, size: 18),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(
                              isCurrent ? 1.0 : 0.8),
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      const Icon(Icons.check_rounded,
                          size: 16, color: _kAccent),
                  ],
                ),
              ),
            );
          }),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ── Add item dialog ───────────────────────────────────────────────────────────

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog();

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  String _selectedCategory = kDefaultShoppingCategory;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((
      name: _nameCtrl.text.trim(),
      category: _selectedCategory,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final meta = _metaFor(_selectedCategory);
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2029),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Add to List',
        style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: _kAccent,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Item name is required.'
                  : null,
              decoration: _fieldDecoration(
                hint: 'e.g. Milk, Eggs, Bread…',
                icon: Icons.add_shopping_cart_rounded,
                iconColor: _kAccent.withOpacity(0.7),
                accentColor: _kAccent,
              ),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              dropdownColor: const Color(0xFF252833),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withOpacity(0.35)),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _fieldDecoration(
                hint: 'Category',
                icon: meta.icon,
                iconColor: meta.color.withOpacity(0.7),
                accentColor: meta.color,
              ),
              items: kShoppingCategories
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style: const TextStyle(color: Colors.white)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedCategory = v);
              },
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white54,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kAccent,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text('Add',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    required Color iconColor,
    required Color accentColor,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
      prefixIcon: Icon(icon, color: iconColor, size: 18),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.09))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentColor, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF4C4C))),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFFF4C4C), width: 1.5)),
    );
  }
}

// ── Quantity badge ────────────────────────────────────────────────────────────

/// Small pill that displays the item quantity.
/// Renders as an integer when the value is a whole number (e.g. `2.0` → `"2"`),
/// and with one decimal place otherwise (e.g. `1.5` → `"1.5"`).
/// Always visible so the user can tell at a glance how much to buy.
class _QtyBadge extends StatelessWidget {
  const _QtyBadge({required this.quantity, required this.color});

  final double quantity;
  final Color color;

  String get _label {
    final isWhole = quantity == quantity.truncateToDouble();
    return isWhole ? quantity.toInt().toString() : quantity.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color.withOpacity(0.85),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shopping_cart_outlined,
                  size: 68, color: _kAccent.withOpacity(0.28)),
              const SizedBox(height: 20),
              const Text(
                'Your shopping list is empty.',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap + to add items by category.',
                style: TextStyle(
                    fontSize: 13, color: Colors.white.withOpacity(0.4)),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Item'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kAccent,
                  side: BorderSide(color: _kAccent.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Fatal error state ─────────────────────────────────────────────────────────

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
          const Text('Could not load your list',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text(error,
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withOpacity(0.4)),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Try Again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAccent,
              side: BorderSide(color: _kAccent.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
