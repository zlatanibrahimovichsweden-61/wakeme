# WakeMe

A location-based alarm for commuters who want to sleep on transport and wake up
before reaching their destination. Pick a place, choose how far out you want to
be alerted, and WakeMe buzzes you awake when you cross into your radius.

## Features

- Dark, map-first home screen powered by OpenStreetMap (CartoDB Dark Matter
  tiles) — no API key, no billing
- Place search via Nominatim (OpenStreetMap geocoder, free)
- Saved places (Home, University, Work) and recent destinations
- Confirm screen with a draggable trigger radius (200 m – 2000 m) and a live
  geofence circle overlay
- Armed screen with a pulsing pin, live distance, and a full-screen alarm
- Wakelock keeps the screen awake while armed
- Vibration + full-screen notification when you arrive

## Stack

Flutter 3.x, Provider, **flutter_map** + **latlong2** (OpenStreetMap),
Geolocator, Flutter Local Notifications, Vibration, Wakelock Plus, Shared
Preferences, HTTP (for Nominatim).

## Getting started

```bash
flutter pub get
flutter run
```

No API keys, no `.env`, no billing setup. The map tiles and place search both
hit free public services.

### Run on Android

```bash
flutter run -d <android-device-id>
```

Minimum SDK 21, target 34. Use a physical device — the emulator does not give
useful GPS for the alarm flow.

### Run on iOS

```bash
cd ios && pod install && cd ..
flutter run -d <ios-device-id>
```

When prompted, allow location access (**Always**) and notifications.

## Folder structure

```
lib/
├── main.dart                 # Bootstraps WakeMeApp
├── app.dart                  # ThemeData + MultiProvider
├── core/
│   ├── constants/            # colors, text styles, app constants
│   ├── models/               # DestinationModel
│   └── services/             # location, alarm, storage, geocoding
└── features/
    ├── home/                 # map + search + saved/recent sheet
    ├── confirm/              # radius slider + map preview
    └── armed/                # pulsing pin + live distance + cancel
```

## Notes

- Tiles: **CartoDB Dark Matter** via `basemaps.cartocdn.com`. Free for low
  traffic; attribution to OpenStreetMap + CARTO is rendered on the map.
- Geocoder: **Nominatim** at `nominatim.openstreetmap.org`. Usage policy caps
  it at ~1 req/sec — the search bar debounces by 400 ms and is fine for
  personal/dev use. For production you'd swap to a hosted alternative
  (LocationIQ, Photon, or self-hosted Nominatim).
- Background location on iOS requires the "Always" permission.
- Test on a physical device for accurate GPS.
