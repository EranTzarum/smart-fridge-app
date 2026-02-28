# Smart Fridge App

A Flutter mobile application for managing your fridge inventory, shopping list, and AI-generated recipes. Track what's inside, monitor expiry dates, manage grocery runs, check off purchases, and generate personalised meals from your current inventory — backed by a multi-tenant Supabase database and a local Python FastAPI backend.

---

## What's New

### AI Recipes Screen
A fully functional recipes screen (`recipes_screen.dart`) has been built and wired into the main dashboard. The screen communicates with a local Python FastAPI backend via three `POST` endpoints. Users describe a meal, choose a guest count, and receive an AI-generated recipe built from their current fridge inventory. They can iterate on the result through an inline revision chat, then confirm with a single tap — which triggers the backend to deduct used ingredients from `fridge_items` and sync any missing items into `smart_shopping_list`.

### Smart Shopping List
A fully functional shopping list screen (`shopping_list_screen.dart`) has been built and wired into the main dashboard. Items are fetched from the `smart_shopping_list` Supabase table, filtered by `user_id`, and displayed grouped by category. The screen supports manual item entry via a FAB, a Google Keep-style check-off system with undo, and permanent deletion via a trash icon.

### Multi-Tenant Infrastructure
All database queries against `fridge_items` and `smart_shopping_list` are filtered by the authenticated `user_id`. Each user sees only their own data — enforced both at the query level in the service layer and at the database level via Supabase Row Level Security (RLS) policies.

### Dashboard UI
The main dashboard is a dark-themed, prototype-accurate screen with animated gradient navigation cards, a profile button, and smooth fade+slide page transitions to all child routes.

### Manual CRUD Controls (Inventory)
The inventory screen supports full item lifecycle management:
- **Add items** via a bottom sheet form with name, quantity, and category fields.
- **Category-aware expiry calculation** — selecting a category automatically computes the default expiry date:

  | Category | Default shelf life |
  |---|---|
  | Meat | 90 days |
  | Dairy | 14 days |
  | Produce | 7 days |
  | Beverages | 30 days |
  | Other | 30 days |

- **Swipe-to-delete** via Flutter's `Dismissible` widget — items are removed instantly from local state, then deleted from Supabase in the background.

### Graceful Degradation
Fixed a crash caused by Supabase Realtime timeout exceptions on slow or dropped connections. The fix decouples the initial data load (a one-shot `Future` fetch) from the live `Stream`. The list is populated immediately from the fetch; the stream overlays updates only when the socket is healthy. The UI stays populated even if the live connection never establishes.

---

## Features

### Implemented

#### Authentication & Session
- **Authentication** — Email/password sign-up and sign-in via Supabase Auth, with email confirmation flow and inline form validation
- **Session persistence** — Active session is checked at launch; authenticated users are routed directly to the dashboard
- **Sign out** — Clears the Supabase session and returns to the auth screen

#### Infrastructure
- **Multi-tenant data isolation** — All queries are scoped to the authenticated `user_id`; enforced by both service-layer filters and database RLS policies
- **Graceful Realtime degradation** — Decoupled `Future` seed fetch ensures the UI is never blank due to a dropped WebSocket connection

#### Dashboard
- **Dashboard** — Dark-themed home screen with animated gradient navigation cards, a profile button, and smooth fade+slide page transitions

#### Fridge Inventory
- **Real-time inventory** — Backed by a decoupled fetch + Supabase stream; items sorted by nearest expiry date first
- **Add items** — Bottom sheet form with category selection and automatic expiry date calculation
- **Swipe-to-delete** — `Dismissible`-based deletion with instant local state update and async Supabase sync
- **Pull-to-refresh** — Forces a one-shot server round-trip to confirm data is current
- **Expiry badges** — Color-coded freshness indicators per item:
  - `Fresh` (green) — more than 7 days remaining
  - `Warning` (amber) — within 7 days
  - `Critical` (red) — within 3 days
  - `Expired` (red) — past expiry date
  - `No date` (grey) — no expiry tracked

#### Smart Shopping List
- **Category-grouped list** — Items fetched from Supabase and displayed in collapsible sections by category
- **Keep-style check-off** — Tapping an item applies a strikethrough and updates its `status` to `"bought"` in the database; the item stays visible rather than disappearing immediately
- **5-second Undo** — A floating `SnackBar` action lets the user reverse a check-off before it is committed, restoring the item to `"pending"` both locally and in the database
- **Permanent delete** — A trash icon button triggers hard deletion from the database; separate from the check-off flow to prevent accidental data loss
- **Add items via FAB** — Floating Action Button opens an entry form with name, quantity, and category selection
- **User-scoped data** — All queries include `.eq('user_id', currentUserId)` in addition to RLS enforcement

#### AI Recipes
- **Prompt view** — Free-text meal description field plus an adjustable guest counter (1–20); the AI uses the user's live fridge inventory as context
- **Recipe generation** — `POST /generate_recipe` with `{ user_id, prompt, guests }`; response is rendered in a selectable, scrollable card
- **Inline revision** — A chat-style text field sends `POST /revise_recipe` with `{ user_id, feedback }`; the card is replaced in-place and scrolled back to the top
- **Cook This! confirmation** — `POST /confirm_recipe` with `{ user_id }` triggers the backend to deduct used ingredients from `fridge_items` and add any missing items to `smart_shopping_list`
- **Non-blocking loading overlay** — A semi-transparent spinner sits over the current view during in-flight requests; the recipe card remains visible while a revision is processing
- **Robust error handling** — HTTP errors are parsed for `detail` / `message` fields; network exceptions are caught and surfaced verbatim in a `SnackBar`, never silently swallowed
- **Flexible JSON parsing** — Response `recipe` field is handled as either a plain `String` or a structured `Map`/`List`, with automatic pretty-printing for structured payloads
- **Start Over** — Resets all local state without a network call, returning to the prompt view

### Coming Soon
- Recipe history / saved recipes

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) — Material 3 |
| Backend / Auth / Realtime | [Supabase](https://supabase.com) |
| AI Backend | Python FastAPI (local) |
| HTTP client | `package:http` |
| Data isolation | Supabase RLS + `user_id` query filters |
| Environment vars | `flutter_dotenv` |
| State | `StreamBuilder` + decoupled `Future` seed fetch |
| Platforms | Android, iOS, Web, macOS, Linux, Windows |

---

## Project Structure

```
lib/
├── main.dart                        # App entry point, Supabase init, theme, session routing
├── models/
│   ├── fridge_item.dart             # FridgeItem data model, ExpiryStatus enum, daysUntilExpiry
│   └── shopping_item.dart           # ShoppingItem model, isBought getter, copyWith
├── screens/
│   ├── auth_screen.dart             # Login / sign-up with fade animation and form validation
│   ├── home_screen.dart             # Dashboard: animated gradient cards, profile button
│   ├── inventory_screen.dart        # Fridge CRUD: add form, swipe-delete, expiry badges
│   ├── shopping_list_screen.dart    # Shopping list: category groups, check-off, undo, FAB add
│   └── recipes_screen.dart          # AI recipes: prompt, generate, revise, confirm
└── services/
    ├── auth_service.dart            # Thin wrapper around Supabase Auth
    ├── fridge_service.dart          # user_id-scoped queries, decoupled fetch + stream
    └── shopping_list_service.dart   # Full CRUD for smart_shopping_list, user_id-scoped
```

---

## Architecture Notes

### Data Isolation Pattern
Every service method that reads or writes to `fridge_items` or `smart_shopping_list` includes an explicit `.eq('user_id', currentUserId)` filter. This is a defence-in-depth approach: even if an RLS policy were misconfigured, the client query would still only return the current user's rows.

### Decoupled Fetch + Stream
The `InventoryScreen` uses a two-phase data strategy to handle unreliable Realtime connections:

1. **Seed phase** — `FridgeService.fetchActiveItems()` runs a one-shot `Future` query on mount and populates the list immediately.
2. **Live phase** — `FridgeService.watchActiveItems()` opens a Supabase Realtime stream. If the socket connects, it takes over and pushes incremental updates. If it times out, the seed data remains visible and no exception surfaces to the user.

### Category-Based Expiry
When a user adds an item and selects a category, `FridgeService.defaultExpiryForCategory()` returns a `DateTime` offset from today. This value pre-fills the expiry date field and can be overridden manually.

### Swipe-to-Delete Flow (Inventory)
1. `Dismissible.onDismissed` fires — item is removed from local `List<FridgeItem>` state immediately via `setState`.
2. `FridgeService.deleteItem(id)` runs asynchronously in the background.
3. If the Supabase call fails, an error snackbar is shown and the item is re-inserted at its original index.

### Shopping List Check-Off & Undo Flow
The shopping list intentionally avoids instant deletion to prevent accidental data loss. The flow follows a non-destructive, Google Keep-style pattern:

1. **Check off** — User taps an item; the local model flips `isChecked = true` and the row is rendered with a strikethrough. A `PATCH` sets `status = 'bought'` in Supabase.
2. **Undo window** — A floating `SnackBar` with a 5-second timer and an **Undo** action is shown. If tapped, `isChecked` is reverted locally and `status` is patched back to `'pending'`.
3. **Permanent delete** — Tapping the trash icon on any item (checked or not) triggers a hard `DELETE` in Supabase and removes the item from local state. This action has no undo.

### Category Grouping (Shopping List)
Items returned from Supabase are grouped client-side by their `category` field using a `Map<String, List<ShoppingItem>>`. Each group is rendered as a labelled section header followed by its items. This requires no additional database queries — grouping is a pure in-memory transform on the fetched list.

### AI Recipe Flow
The `RecipesScreen` manages a two-state UI (prompt view → recipe view) via `AnimatedSwitcher`. All three API calls share the same error-handling pattern:

1. **Generate** — User submits a meal description and guest count. `POST /generate_recipe` returns `{ "recipe": ... }`. The response is stored in `_currentRecipe` and the screen transitions to the recipe view.
2. **Revise** — User types feedback in the inline chat field. `POST /revise_recipe` returns an updated `{ "recipe": ... }`. The card is replaced in-place; the scroll controller resets to the top via `addPostFrameCallback`.
3. **Confirm** — `POST /confirm_recipe` is sent with only `{ "user_id" }`. The backend handles all inventory deductions and shopping list writes server-side. On `200 OK`, a success `SnackBar` is shown and the screen pops.

**Error handling strategy:**
- HTTP `4xx`/`5xx` responses are parsed for a `detail` or `message` field. If JSON parsing of the error body fails, the raw body and status code are shown and printed to the console.
- Network-level exceptions (e.g. connection refused, timeout) are caught in every `try/catch` block, printed in full, and shown in a `SnackBar` without crashing the screen.
- `_recipeToString` normalises the `recipe` value to a display string regardless of whether the backend returns a plain `String`, a `Map`, or a `List` — future-proofing the client against structured response changes.

**Base URL note:** The API base is `http://127.0.0.1:8000`. On Android emulators, replace with `10.0.2.2:8000`; on a physical device, use the host machine's LAN IP.

---

## Local Backend (FastAPI)

The AI recipe feature requires a Python FastAPI server running locally. The Flutter app targets `http://127.0.0.1:8000` by default.

### Endpoints

| Method | Path | Request body | Response |
|---|---|---|---|
| `POST` | `/generate_recipe` | `{ user_id, prompt, guests }` | `{ "recipe": "..." }` |
| `POST` | `/revise_recipe` | `{ user_id, feedback }` | `{ "recipe": "..." }` |
| `POST` | `/confirm_recipe` | `{ user_id }` | `{ "status": "ok" }` |

- **`/generate_recipe`** — Reads the user's `fridge_items` from Supabase using `user_id`, passes inventory context + the user's prompt to the AI model, and returns a structured recipe.
- **`/revise_recipe`** — Applies the user's free-text feedback to the previously generated recipe and returns the revised version. The backend maintains per-user session state between calls.
- **`/confirm_recipe`** — Commits the confirmed recipe: deducts used ingredients from `fridge_items` and inserts any missing items into `smart_shopping_list` in Supabase.

> Error responses must use the format `{ "detail": "..." }` or `{ "message": "..." }` for the Flutter client to display them cleanly.

### Running the backend

```bash
# From the backend project directory
pip install -r requirements.txt
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

---

## Supabase Setup

### Tables

#### `fridge_items`

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` | Primary key, default `gen_random_uuid()` |
| `user_id` | `uuid` | References `auth.users(id)` — required for RLS |
| `item_name` | `text` | |
| `quantity` | `text` | e.g. `"2 packs"`, `"500 ml"` |
| `category` | `text` | e.g. `"Meat"`, `"Dairy"`, `"Produce"` |
| `expiry_date` | `date` | Nullable |
| `status` | `text` | `"active"` or `"removed"` |

#### `smart_shopping_list`

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` | Primary key, default `gen_random_uuid()` |
| `user_id` | `uuid` | References `auth.users(id)` — required for RLS |
| `item_name` | `text` | |
| `quantity` | `text` | e.g. `"1 litre"`, `"x3"` |
| `category` | `text` | Used for client-side grouping, e.g. `"Dairy"`, `"Produce"` |
| `status` | `text` | `"pending"` (default) or `"bought"` |
| `is_checked` | `bool` | Default `false` — mirrors `status` for UI toggle state |

### Row Level Security

Enable RLS on both tables and apply the following policy pattern:

```sql
-- Example for fridge_items (repeat for smart_shopping_list)
CREATE POLICY "Users can manage their own items"
ON fridge_items
FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
```

### Realtime

Enable Realtime on `fridge_items` in the Supabase dashboard under **Database → Replication**. The app handles connection failures gracefully, so this is optional for development.

---

## Environment Variables

Create a `.env` file in the project root (already listed in `.gitignore`):

```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_KEY=your-anon-public-key
```

The file is bundled as a Flutter asset via `pubspec.yaml` and loaded at startup using `flutter_dotenv`.

---

## Getting Started

```bash
# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run

# Build for Android
flutter build apk

# Build for iOS
flutter build ios
```

---

## App Workflow

```
Launch
  └── Session exists? ──Yes──▶ HomeScreen (Dashboard)
           │
          No
           └──▶ AuthScreen
                  ├── Sign In  ──▶ HomeScreen
                  └── Sign Up  ──▶ Email confirmation ──▶ Sign In

HomeScreen
  ├── MY FRIDGE        ──▶ InventoryScreen
  │                          ├── Seed fetch (Future) ──▶ populate list
  │                          ├── Live stream (Socket) ──▶ overlay updates
  │                          ├── FAB / bottom sheet  ──▶ add item (category + auto-expiry)
  │                          └── Swipe left          ──▶ delete (local + Supabase)
  │
  ├── MY SHOPPING LIST ──▶ ShoppingListScreen
  │                          ├── Fetch (user_id filter) ──▶ group by category
  │                          ├── Tap item    ──▶ strikethrough + status = 'bought'
  │                          │                    └── 5s SnackBar ──▶ Undo (status = 'pending')
  │                          ├── Trash icon  ──▶ hard DELETE (no undo)
  │                          └── FAB         ──▶ add item (name, quantity, category)
  │
  ├── RECIPES          ──▶ RecipesScreen
  │                          ├── Enter prompt + guest count
  │                          ├── POST /generate_recipe ──▶ recipe card
  │                          ├── Inline feedback field
  │                          │     └── POST /revise_recipe ──▶ updated card
  │                          └── Cook This! ──▶ POST /confirm_recipe
  │                                               ├── backend deducts fridge_items
  │                                               ├── backend syncs shopping_list
  │                                               └── SnackBar + pop
  │
  └── Sign Out         ──▶ AuthScreen
```

---

## Dependencies

```yaml
supabase_flutter: ^2.12.0   # Supabase client, Realtime, and Auth
flutter_dotenv:   ^6.0.0    # .env file loader
http:             ^1.0.0    # HTTP client for FastAPI requests
```
