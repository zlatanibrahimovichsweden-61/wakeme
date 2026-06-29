# WakeMe — Privacy Policy

**Effective date:** 2026-06-29

WakeMe ("the app", "we", "us") is a location-based alarm that wakes you before
you reach a chosen destination. This policy explains what information the app
uses and how it is handled.

## Summary

- WakeMe has **no user accounts**, shows **no ads**, and uses **no analytics**.
- We operate **no servers** and **never receive or store your data**.
- Your location is processed **on your device** to detect arrival, and is sent
  **only to Google Maps Platform** to show the map, search places, look up
  addresses, and compute routes.

## Information the app accesses

- **Location (precise and approximate).** While a trip is *armed*, WakeMe reads
  your device location to measure your distance to your destination and sound
  the alarm when you arrive. So this works even when you switch apps or lock the
  screen, tracking runs inside an Android **foreground service** (shown by an
  ongoing notification) only while a trip is armed. Tracking stops as soon as the
  alarm is dismissed or the trip is cancelled. Location is **not** accessed when
  no trip is armed. This is the app's core function.
- **An audio file you choose (optional).** If you set a custom alarm sound,
  WakeMe copies the file you pick into its own private storage so it can play it.
  No other files are accessed.

## How your location is used and shared

- **On your device:** distance and geofence calculations that trigger the alarm.
  These never leave your phone.
- **Google Maps Platform:** to display the map, search for places, look up
  addresses, and calculate routes, your location and search queries are sent to
  Google over an encrypted (HTTPS) connection. Google acts as our service
  provider for these features; its handling of that data is governed by the
  [Google Privacy Policy](https://policies.google.com/privacy).
- We do **not** sell your data, share it with advertisers, or send it to any
  server operated by the developer (there is none).

## Data storage and retention

- Saved places, recent destinations, and your alarm-sound choice are stored
  **only on your device**.
- The developer retains **none** of your data, because we run no servers.
- You can erase all app data at any time by clearing WakeMe's storage in your
  device settings, or by uninstalling the app.

## Permissions and why they are requested

| Permission | Why |
|---|---|
| Location — precise & approximate | Detect arrival and fire the alarm |
| Foreground service (location type) | Keep tracking reliably while a trip is armed, including when the app is backgrounded or the screen is locked |
| Notifications / full-screen intent | Show the ongoing tracking notification and the arrival alarm |
| Vibrate / wake lock | Alert you and keep the alarm responsive |
| Ignore battery optimizations (optional) | Improve alarm reliability on aggressive power-saving phones; you may decline |
| Internet | Load map tiles and place/route data from Google |

WakeMe does **not** request the "Allow all the time" background-location
permission. All location access happens while a trip is armed, via the
foreground service above.

## Children

WakeMe is not directed to children under 13 and does not knowingly collect data
from them.

## Changes to this policy

We may update this policy from time to time. Material changes will be reflected
by updating the effective date above and publishing the revised version at this
same location.

## Contact

Questions about this policy: **mohamed61fouad@gmail.com**
