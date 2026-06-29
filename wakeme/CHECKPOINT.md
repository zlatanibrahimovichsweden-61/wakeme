# WakeMe — Checkpoint v0.1.0

## Status
- [x] Project structure created
- [x] All 3 screens implemented
- [x] Location service
- [x] Alarm service
- [x] Storage service
- [x] Geocoding service (Nominatim)
- [x] Android permissions configured
- [x] iOS permissions configured
- [x] Dark theme applied
- [x] Map provider: OpenStreetMap via flutter_map (no API key required)
- [ ] Tested on physical device

## Known Limitations
- Background location on iOS requires "Always" permission
- Test on physical device only (GPS doesn't work on emulator)
- Nominatim public endpoint is rate-limited (~1 req/sec) — swap for a hosted
  geocoder before shipping to real users

## Next Steps
- Add unit tests for LocationService
- Add integration test for alarm trigger
- Configure CI/CD
