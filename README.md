# Smart Fridge App

A Flutter mobile application for managing your fridge inventory in real time. Track what's inside, monitor expiry dates, manage your shopping list, and plan grocery runs — all backed by a multi-tenant Supabase backend with per-user data isolation.

---

## What's New

### Multi-Tenant Infrastructure
All database queries against `fridge_items` and `smart_shopping_list` are now filtered by the authenticated `user_id`. Each user sees only their own data — enforced both at the query level in the service layer and at the database level via Supabase Row Level Security (RLS) policies.

### Dashboard UI
The main dashboard has been rebuilt as a dark-themed, prototype-accurate screen with animated gradient navigation cards, a profile button, and smooth fade+slide page transitions to all child routes.

### Manual CRUD Controls
The inventory screen now supports full item lifecycle management:
- **Add items** via a bottom sheet form with name, quantity, and category fields.
- **Category-aware expiry calculation** — selecting a category (e.g. Meat, Dairy, Produce) automatically computes the default expiry date:

  | Category | Default shelf life |
  |---|---|
  | Meat | 90 days |
  | Dairy | 14 days |
  | Produce | 7 days |
  | Beverages | 30 days |
  | Other | 30 days |

- **Swipe-to-delete** via Flutter's `Dismissible` widget — items are removed instantly from local state for a snappy UI, then deleted from Supabase in the background.

### Graceful Degradation
Fixed a crash caused by Supabase Realtime timeout exceptions on slow or dropped connections. The fix decouples the initial data load (a one-shot `Future` fetch) from the live `Stream`. The inventory list is populated immediately from the fetch result; the stream overlays updates only when the socket is healthy. The UI stays populated even if the live connection never establishes.

---

## Features

### Implemented
- **Authentication** — Email/password sign-up and sign-in via Supabase Auth, with email confirmation flow and inline form validation
- **Session persistence** — Active session is checked at launch; authenticated users are routed directly to the dashboard
- **Multi-tenant data isolation** — All queries are scoped to the authenticated `user_id`; enforced by both service-layer filters and database RLS policies
- **Dashboard** — Dark-themed home screen with animated, gradient navigation cards and smooth page transitions
- **Fridge Inventory** — Real-time inventory screen backed by a decoupled fetch + Supabase stream; items sorted by nearest expiry date first
- **Add items** — Bottom sheet form with category selection and automatic expiry date calculation
- **Swipe-to-delete** — `Dismissible`-based deletion with instant local state update and async Supabase sync
- **Expiry badges** — Color-coded freshness indicators per item:
  - `Fresh` (green) — more than 7 days remaining
  - `Warning` (amber) — within 7 days
  - `Critical` (red) — within 3 days
  - `Expired` (red) — past expiry date
  - `No date` (grey) — no expiry tracked
- **Pull-to-refresh** — Forces a one-shot server round-trip to confirm data is current
- **Sign out** — Clears the Supabase session and returns to the auth screen

### Coming Soon
- Shopping List (table + service scaffolded)
- Recipe suggestions from current inventory

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) — Material 3 |
| Backend / Auth / Realtime | [Supabase](https://supabase.com) |
| Data isolation | Supabase RLS + `user_id` query filters |
| Environment vars | `flutter_dotenv` |
| State | `StreamBuilder` + decoupled `Future` seed fetch |
| Platforms | Android, iOS, Web, macOS, Linux, Windows |

---

## Project Structure

```
lib/
├── main.dart                    # App entry point, Supabase init, theme, session routing
├── models/
│   └── fridge_item.dart         # FridgeItem data model, ExpiryStatus enum, daysUntilExpiry
├── screens/
│   ├── auth_screen.dart         # Login / sign-up with fade animation and form validation
│   ├── home_screen.dart         # Dashboard: animated gradient cards, profile button
│   └── inventory_screen.dart    # CRUD inventory: add form, swipe-delete, expiry badges
└── services/
    ├── auth_service.dart        # Thin wrapper around Supabase Auth
    └── fridge_service.dart      # user_id-scoped queries, decoupled fetch + stream
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

### Swipe-to-Delete Flow
1. `Dismissible.onDismissed` fires — item is removed from local `List<FridgeItem>` state immediately via `setState`.
2. `FridgeService.deleteItem(id)` runs asynchronously in the background.
3. If the Supabase call fails, an error snackbar is shown and the item is re-inserted at its original index.

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
| `quantity` | `text` | |
| `is_checked` | `bool` | Default `false` |

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
  │                          ├── Add item (bottom sheet + category expiry)
  │                          └── Swipe left to delete (local + Supabase)
  ├── MY SHOPPING LIST ──▶ Coming soon
  ├── RECIPES          ──▶ Coming soon
  └── Sign Out         ──▶ AuthScreen
```

---

## Dependencies

```yaml
supabase_flutter: ^2.12.0   # Supabase client, Realtime, and Auth
flutter_dotenv:   ^6.0.0    # .env file loader
```
