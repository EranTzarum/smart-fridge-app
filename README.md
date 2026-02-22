# Smart Fridge App

A Flutter mobile application for managing your fridge inventory in real time. Track what's in your fridge, monitor expiry dates, and plan grocery runs — all backed by a Supabase backend.

---

## Features

### Implemented
- **Authentication** — Email/password sign-up and sign-in via Supabase Auth, with email confirmation flow and inline validation
- **Session persistence** — App checks for an active session on launch and routes directly to the dashboard when already logged in
- **Dashboard** — Home screen with animated navigation cards for Fridge, Shopping List, and Recipes
- **Fridge Inventory** — Real-time inventory screen powered by a Supabase stream; items are sorted by nearest expiry date first
- **Expiry badges** — Color-coded status indicators: fresh (green), warning within 7 days (amber), critical within 3 days (red), expired (red), and no date (grey)
- **Pull-to-refresh** — Forces a one-shot server round-trip to confirm the real-time stream is current
- **Sign out** — Clears the local Supabase session and returns to the auth screen

### Coming Soon
- Shopping List
- Recipe suggestions from current inventory

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) — Material 3 |
| Backend / Auth | [Supabase](https://supabase.com) |
| Environment vars | `flutter_dotenv` |
| State | `StreamBuilder` + Supabase real-time streams |
| Platforms | Android, iOS, Web, macOS, Linux, Windows |

---

## Project Structure

```
lib/
├── main.dart                  # App entry point, Supabase init, theme, session routing
├── models/
│   └── fridge_item.dart       # FridgeItem data model + ExpiryStatus enum
├── screens/
│   ├── auth_screen.dart       # Login / sign-up screen with fade animation
│   ├── home_screen.dart       # Dashboard with gradient nav cards
│   └── inventory_screen.dart  # Real-time fridge inventory list
└── services/
    ├── auth_service.dart      # Thin wrapper around Supabase Auth
    └── fridge_service.dart    # Real-time stream + one-shot fetch from `fridge_items` table
```

---

## Supabase Setup

1. Create a project at [supabase.com](https://supabase.com).
2. Create the `fridge_items` table with the following columns:

   | Column | Type | Notes |
   |---|---|---|
   | `id` | `uuid` | Primary key, default `gen_random_uuid()` |
   | `user_id` | `uuid` | References `auth.users` |
   | `item_name` | `text` | |
   | `quantity` | `text` | e.g. `"2 packs"`, `"500 ml"` |
   | `expiry_date` | `date` | Nullable |
   | `status` | `text` | `"active"` or `"removed"` |

3. Enable **Row Level Security** and add a policy so users can only read/write their own rows.
4. Enable **Realtime** for the `fridge_items` table.

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
                  ├── Sign In ──▶ HomeScreen
                  └── Sign Up ──▶ Email confirmation ──▶ Sign In

HomeScreen
  ├── MY FRIDGE ──▶ InventoryScreen (Supabase real-time stream)
  ├── MY SHOPPING LIST ──▶ Coming soon
  ├── RECIPES ──▶ Coming soon
  └── Sign Out ──▶ AuthScreen
```

---

## Dependencies

```yaml
supabase_flutter: ^2.12.0   # Supabase client + real-time + auth
flutter_dotenv:   ^6.0.0    # .env file loader
```
