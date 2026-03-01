import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kAccent    = Color(0xFFB06EF5);
const _kBg        = Color(0xFF0D0F14);
const _kCard      = Color(0xFF1A1D27);

/// Base URL for the local FastAPI backend.
///
/// Using 127.0.0.1 instead of `localhost` avoids IPv6 resolution issues
/// in Chrome/Flutter-web where `localhost` may resolve to `::1`.
/// ⚠️  On Android emulators use `10.0.2.2`; on a physical device use the
///     host machine's LAN IP.
const _kApiBase = 'http://127.0.0.1:8000';

// ── Screen ────────────────────────────────────────────────────────────────────

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  // ── Controllers ──────────────────────────────────────────────────────────

  final _promptCtrl        = TextEditingController();
  final _feedbackCtrl      = TextEditingController();
  final _recipeScrollCtrl  = ScrollController();

  // ── State ─────────────────────────────────────────────────────────────────

  int                      _guestCount     = 1;
  bool                     _isLoading      = false;
  String                   _loadingMessage = '';
  Map<String, dynamic>?    _currentRecipe;

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// The authenticated user's UUID. Empty string when no session exists (edge
  /// case: the backend should reject any call with an empty user_id).
  String get _userId =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _promptCtrl.dispose();
    _feedbackCtrl.dispose();
    _recipeScrollCtrl.dispose();
    super.dispose();
  }

  // ── JSON helpers ──────────────────────────────────────────────────────────

  /// Normalises the `recipe` value from an API response into a
  /// [Map<String, dynamic>] regardless of whether the backend returns a
  /// ready-made Map or an inner JSON string.
  ///
  /// • Map<String, dynamic> → returned as-is.
  /// • String               → decoded as JSON; if that fails the string is
  ///                          wrapped in `{'raw': value}` for safe display.
  /// • null / other         → wraps the raw body string in `{'raw': ...}`.
  Map<String, dynamic> _normaliseRecipe(dynamic value, String rawBody) {
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
      return {'raw': value};
    }
    return {'raw': rawBody};
  }

  // ── API calls ─────────────────────────────────────────────────────────────

  /// Sends the user's meal prompt and guest count to `/generate_recipe`.
  /// Stores the returned recipe text in [_currentRecipe].
  Future<void> _generateRecipe() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      _showSnackbar('Please describe what you\'d like to cook.', isError: true);
      return;
    }

    setState(() {
      _isLoading      = true;
      _loadingMessage = 'Generating your recipe…';
    });

    try {
      final res = await http.post(
        Uri.parse('$_kApiBase/generate_recipe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'prompt': prompt,
          'guests': _guestCount,
        }),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _currentRecipe = _normaliseRecipe(body['recipe'], res.body);
          _isLoading     = false;
        });
      } else {
        _handleHttpError(res);
      }
    } catch (e) {
      _onNetworkError(e);
    }
  }

  /// Sends the user's revision request to `/revise_recipe` and replaces the
  /// displayed recipe with the revised version.
  Future<void> _reviseRecipe() async {
    final feedback = _feedbackCtrl.text.trim();
    if (feedback.isEmpty) return;

    setState(() {
      _isLoading      = true;
      _loadingMessage = 'Revising recipe…';
    });

    try {
      final res = await http.post(
        Uri.parse('$_kApiBase/revise_recipe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'feedback': feedback,
        }),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        _feedbackCtrl.clear();
        setState(() {
          _currentRecipe = _normaliseRecipe(body['recipe'], res.body);
          _isLoading     = false;
        });
        // Scroll back to the top of the revised recipe.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_recipeScrollCtrl.hasClients) {
            _recipeScrollCtrl.animateTo(
              0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        _handleHttpError(res);
      }
    } catch (e) {
      _onNetworkError(e);
    }
  }

  /// Confirms the current recipe via `/confirm_recipe`, which triggers the
  /// backend to update the fridge inventory and shopping list.
  Future<void> _confirmRecipe() async {
    setState(() {
      _isLoading      = true;
      _loadingMessage = 'Updating your inventory…';
    });

    try {
      final res = await http.post(
        Uri.parse('$_kApiBase/confirm_recipe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId}),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text(
                'Inventory updated & shopping list synced!',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: _kAccent.withOpacity(0.9),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              duration: const Duration(seconds: 4),
            ),
          );
        Navigator.of(context).pop();
      } else {
        _handleHttpError(res);
      }
    } catch (e) {
      _onNetworkError(e);
    }
  }

  // ── Error helpers ─────────────────────────────────────────────────────────

  void _handleHttpError(http.Response res) {
    if (!mounted) return;
    String message;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      message = (body['detail'] ?? body['message'] ?? 'Error ${res.statusCode}')
          .toString();
    } catch (e) {
      // JSON parse failed — show raw body so the true format is visible.
      print('API ERROR DETAILS (parse failure): $e\nRaw body: ${res.body}');
      message = 'Error ${res.statusCode}: ${res.body}';
    }
    setState(() => _isLoading = false);
    _showSnackbar(message, isError: true);
  }

  /// Called from every `catch` block. Prints the full exception to the console
  /// and shows [e.toString()] in a SnackBar so the real error is never hidden.
  void _onNetworkError(Object e) {
    print('API ERROR DETAILS: $e');
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showSnackbar(e.toString(), isError: true);
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor:
          isError ? const Color(0xFF2A1A1A) : const Color(0xFF1A2A1A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    ));
  }

  void _startOver() => setState(() {
        _currentRecipe = null;
        _feedbackCtrl.clear();
        _isLoading = false;
      });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(),
      // Stack: content behind + loading overlay on top when in-flight.
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _currentRecipe == null
                ? _buildPromptView()
                : _buildRecipeView(),
          ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
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
            child: Icon(Icons.menu_book_rounded, color: _kAccent, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            _currentRecipe == null ? 'AI Recipe Generator' : 'Your Recipe',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      actions: [
        if (_currentRecipe != null)
          TextButton.icon(
            onPressed: _isLoading ? null : _startOver,
            icon: Icon(
              Icons.refresh_rounded,
              size: 15,
              color: _kAccent.withOpacity(0.75),
            ),
            label: Text(
              'Start Over',
              style: TextStyle(
                fontSize: 13,
                color: _kAccent.withOpacity(0.75),
              ),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Loading overlay ───────────────────────────────────────────────────────

  /// Semi-transparent overlay with a spinner. Sits on top of whatever view is
  /// currently rendered so the recipe stays visible while a revision is
  /// in-flight.
  Widget _buildLoadingOverlay() {
    return AbsorbPointer(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: _kAccent,
                strokeWidth: 3,
              ),
              const SizedBox(height: 18),
              Text(
                _loadingMessage,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Prompt view ───────────────────────────────────────────────────────────

  Widget _buildPromptView() {
    return SingleChildScrollView(
      key: const ValueKey('prompt'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero icon
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: _kAccent.withOpacity(0.2), width: 1.5),
              ),
              child: Icon(Icons.restaurant_menu_rounded,
                  color: _kAccent, size: 38),
            ),
          ),
          const SizedBox(height: 22),

          const Center(
            child: Text(
              'What would you like to cook?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'The AI will use your current fridge inventory.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),

          // Prompt field
          _SectionLabel('Meal description'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _promptCtrl,
            maxLines: 3,
            minLines: 3,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, height: 1.55),
            textInputAction: TextInputAction.newline,
            decoration: _inputDecoration(
              hint:
                  'e.g. ארוחת צהריים עתירת חלבון, low-carb dinner, '
                  'quick pasta for kids…',
              icon: Icons.edit_note_rounded,
            ),
          ),
          const SizedBox(height: 24),

          // Guest counter
          _SectionLabel('Number of guests'),
          const SizedBox(height: 8),
          _GuestCounter(
            count: _guestCount,
            onDecrement:
                _guestCount > 1 ? () => setState(() => _guestCount--) : null,
            onIncrement:
                _guestCount < 20 ? () => setState(() => _guestCount++) : null,
          ),
          const SizedBox(height: 36),

          // Generate button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _generateRecipe,
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: const Text(
                'Generate Recipe',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recipe view ───────────────────────────────────────────────────────────

  Widget _buildRecipeView() {
    final recipe = _currentRecipe!;

    return Column(
      key: const ValueKey('recipe'),
      children: [
        // ── Scrollable structured recipe ──────────────────────────────────
        Expanded(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              controller: _recipeScrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Fallback: raw text if the map only has a 'raw' key
                  if (recipe.containsKey('raw') &&
                      recipe.length == 1) ...[
                    _RawRecipeFallback(text: recipe['raw'].toString()),
                  ] else ...[
                    // Chef message banner
                    if (_str(recipe['chef_message']) case final msg
                        when msg.isNotEmpty)
                      _ChefMessageBanner(message: msg),

                    // Title + tagline
                    _RecipeHeader(
                      name: _str(recipe['recipe_name']),
                      tagline: _str(recipe['tagline']),
                      cookingTime: _str(recipe['cooking_time'] ??
                          recipe['prep_time']),
                      difficulty: _str(recipe['difficulty']),
                      servings: recipe['servings'],
                    ),

                    const SizedBox(height: 6),

                    // Ingredients
                    if (recipe['used_fridge_items'] != null)
                      _IngredientsSection(
                          items: recipe['used_fridge_items']),

                    // Missing items (need to buy)
                    if (recipe['missing_items'] != null &&
                        (recipe['missing_items'] as List).isNotEmpty)
                      _MissingItemsSection(
                          items: recipe['missing_items']),

                    // Instructions
                    if (recipe['instructions'] != null)
                      _InstructionsSection(
                          steps: recipe['instructions']),

                    // Notes / tips
                    if (_str(recipe['notes'] ?? recipe['tips']) case
                        final notes when notes.isNotEmpty)
                      _NotesSection(text: notes),
                  ],

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),

        // ── Bottom action bar (LTR — UI chrome stays left-to-right) ──────
        Container(
          decoration: BoxDecoration(
            color: _kBg,
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ask the chef row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _feedbackCtrl,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _reviseRecipe(),
                        decoration: _inputDecoration(
                          hint: 'Ask the chef to change something…',
                          icon: Icons.chat_bubble_outline_rounded,
                        ).copyWith(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: _kAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _reviseRecipe,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(Icons.send_rounded,
                              color: _kAccent, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Cook This! button
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _confirmRecipe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🍳', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 10),
                        Text(
                          'Cook This!',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Safely coerces a dynamic value to a non-null trimmed String.
  static String _str(dynamic v) => v?.toString().trim() ?? '';

  // ── Shared input decoration ────────────────────────────────────────────────

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.3), fontSize: 13),
      prefixIcon:
          Icon(icon, color: Colors.white.withOpacity(0.3), size: 18),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.09))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAccent, width: 1.5)),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.white.withOpacity(0.45),
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Guest counter ─────────────────────────────────────────────────────────────

class _GuestCounter extends StatelessWidget {
  const _GuestCounter({
    required this.count,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int count;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          _StepButton(icon: Icons.remove_rounded, onTap: onDecrement),
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'guest' : 'guests'}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: _kAccent.withOpacity(enabled ? 0.15 : 0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            icon,
            size: 18,
            color: _kAccent.withOpacity(enabled ? 1.0 : 0.3),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Recipe display widgets (RTL Hebrew)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Shared styling helpers ────────────────────────────────────────────────────

/// Bold section header with a coloured left (RTL: right) accent bar.
class _RecipeSectionHeader extends StatelessWidget {
  const _RecipeSectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 20,
            margin: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin full-width divider used between sections.
class _RecipeDivider extends StatelessWidget {
  const _RecipeDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Divider(
        color: Colors.white.withOpacity(0.08),
        thickness: 1,
        height: 1,
      ),
    );
  }
}

// ── Chef message banner ───────────────────────────────────────────────────────

class _ChefMessageBanner extends StatelessWidget {
  const _ChefMessageBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        // Warm amber tint — friendly chef personality
        color: const Color(0xFFFFB830).withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFFFB830).withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👨‍🍳', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.white.withOpacity(0.85),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recipe header (name + tagline + metadata chips) ───────────────────────────

class _RecipeHeader extends StatelessWidget {
  const _RecipeHeader({
    required this.name,
    required this.tagline,
    required this.cookingTime,
    required this.difficulty,
    required this.servings,
  });

  final String name;
  final String tagline;
  final String cookingTime;
  final String difficulty;
  final dynamic servings;

  @override
  Widget build(BuildContext context) {
    final chips = <({String label, IconData icon})>[
      if (cookingTime.isNotEmpty)
        (label: cookingTime, icon: Icons.timer_outlined),
      if (difficulty.isNotEmpty)
        (label: difficulty, icon: Icons.bar_chart_rounded),
      if (servings != null && servings.toString().isNotEmpty)
        (label: '${servings} מנות', icon: Icons.people_outline_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Recipe name
        if (name.isNotEmpty)
          Text(
            name,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),

        // Tagline
        if (tagline.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            tagline,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
              height: 1.45,
            ),
          ),
        ],

        // Metadata chips
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map((c) => _MetaChip(label: c.label, icon: c.icon))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withOpacity(0.5)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ingredients section ───────────────────────────────────────────────────────

class _IngredientsSection extends StatelessWidget {
  const _IngredientsSection({required this.items});
  final dynamic items;

  @override
  Widget build(BuildContext context) {
    final list = items is List ? items as List : [];
    if (list.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RecipeDivider(),
        const _RecipeSectionHeader(
          title: 'מצרכים',
          icon: Icons.kitchen_rounded,
          color: Color(0xFF81C784),
        ),
        Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < list.length; i++) ...[
                _IngredientRow(item: list[i], index: i),
                if (i < list.length - 1)
                  Divider(
                    height: 1,
                    color: Colors.white.withOpacity(0.06),
                    indent: 16,
                    endIndent: 16,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.item, required this.index});
  final dynamic item;
  final int index;

  @override
  Widget build(BuildContext context) {
    // Support both plain strings and {item_name, quantity} maps.
    final String name;
    final String quantity;

    if (item is Map) {
      name = (item['item_name'] ?? item['name'] ?? item['ingredient'] ?? '')
          .toString()
          .trim();
      // Accept `quantity_used` (backend field), `quantity`, or `amount`.
      quantity =
          (item['quantity_used'] ?? item['quantity'] ?? item['amount'] ?? '')
              .toString()
              .trim();
    } else {
      name = item.toString().trim();
      quantity = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Bullet dot
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF81C784),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Quantity pill badge — shown whenever the backend provides a value.
          if (quantity.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF81C784).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF81C784).withOpacity(0.3)),
              ),
              child: Text(
                quantity,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF81C784),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Missing items section (items needed from store) ───────────────────────────

class _MissingItemsSection extends StatelessWidget {
  const _MissingItemsSection({required this.items});
  final dynamic items;

  @override
  Widget build(BuildContext context) {
    final list = items is List ? items as List : [];
    if (list.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const _RecipeSectionHeader(
          title: 'לרכישה',
          icon: Icons.shopping_cart_outlined,
          color: Color(0xFFFFB830),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: list.map((e) {
            final label = e is Map
                ? (e['item_name'] ?? e['name'] ?? e).toString()
                : e.toString();
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB830).withOpacity(0.09),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFFFB830).withOpacity(0.25)),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFFFB830),
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Instructions section ──────────────────────────────────────────────────────

class _InstructionsSection extends StatelessWidget {
  const _InstructionsSection({required this.steps});
  final dynamic steps;

  @override
  Widget build(BuildContext context) {
    final list = steps is List ? steps as List : [];
    if (list.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RecipeDivider(),
        const _RecipeSectionHeader(
          title: 'הוראות הכנה',
          icon: Icons.menu_book_rounded,
          color: Color(0xFFB06EF5),
        ),
        Column(
          children: [
            for (int i = 0; i < list.length; i++)
              _StepRow(step: list[i], number: i + 1),
          ],
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.number});
  final dynamic step;
  final int number;

  @override
  Widget build(BuildContext context) {
    // Support strings, or {step, instruction, description} maps.
    final String text;
    if (step is Map) {
      text = (step['instruction'] ??
              step['description'] ??
              step['step'] ??
              step['text'] ??
              '')
          .toString()
          .trim();
    } else {
      text = step.toString().trim();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number badge
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(left: 12, top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFB06EF5).withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: const Color(0xFFB06EF5).withOpacity(0.35)),
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB06EF5),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14.5,
                color: Colors.white.withOpacity(0.88),
                height: 1.65,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notes / tips section ──────────────────────────────────────────────────────

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _RecipeDivider(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: const Color(0xFFFFB830).withOpacity(0.7)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.white.withOpacity(0.6),
                    height: 1.6,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Raw fallback (when API returns unstructured text) ─────────────────────────

class _RawRecipeFallback extends StatelessWidget {
  const _RawRecipeFallback({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontSize: 14.5,
          color: Colors.white,
          height: 1.7,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
