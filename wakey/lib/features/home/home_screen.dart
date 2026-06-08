import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/destination_model.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/widgets/map_controls.dart';
import '../confirm/confirm_screen.dart';
import 'saved_place_editor_screen.dart';
import 'widgets/recent_place_card.dart';
import 'widgets/saved_place_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _sheetInitialSize = 0.35;
  static const double _sheetMinSize = 0.15;
  static const double _sheetMaxSize = 0.6;

  GoogleMapController? _mapController;
  LatLng _camera = AppConstants.fallbackLocation;
  LatLng? _userPosition;

  // Current sheet extent as a fraction of screen height. Updated by the
  // NotificationListener wrapping the DraggableScrollableSheet, then used
  // to anchor the map-control buttons just above the sheet's top edge.
  double _sheetExtent = _sheetInitialSize;

  // Search-bar focus flag, set by the _SearchBar via callback. Used to hide
  // the map-control buttons while the user is searching so the favorites /
  // recent dropdown is unobstructed.
  bool _searchFocused = false;

  // GlobalKey + cached height so the map controls can hover just above the
  // tap-to-pin confirm card the same way they hover above the sheet. We
  // measure post-frame because the card's content (address vs. spinner) and
  // SafeArea inset both affect its height.
  final GlobalKey _tapCardKey = GlobalKey();
  double _tapCardHeight = 200;

  // Tap-to-pin state: a pending destination the user selected by tapping
  // the map, awaiting confirmation in the bottom card.
  LatLng? _tappedPoint;
  PlaceResult? _tappedPlace;
  bool _resolvingTap = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Capture both providers before any await so we don't reach across an
    // async gap for context later.
    final LocationService location = context.read<LocationService>();
    final StorageService storage = context.read<StorageService>();
    // Foreground location is REQUIRED. init() triggers the system prompt the
    // first time; on later launches it just reports the (remembered) status.
    final LocationPermissionState perm = await location.init();
    if (perm != LocationPermissionState.granted) {
      if (mounted) await _showBlockingPermissionDialog(perm);
      return;
    }

    // Background ("Allow all the time") + battery exemption are OPTIONAL and
    // only asked ONCE ever, the first time the user reaches home with
    // foreground permission granted. After that we never nag — they can
    // enable both from Settings if they want reliable background alarms.
    if (!storage.askedBackgroundPermission) {
      await _ensureBackgroundPermissionWithRationale(location);
      // Battery-optimization exemption — the key to surviving Samsung's
      // aggressive background killing. Only meaningful if they granted the
      // always-permission, so gate on that to avoid an extra pointless prompt.
      if (location.backgroundPermissionGranted) {
        await _ensureBatteryExemptionWithRationale(location);
      }
      await storage.markAskedBackgroundPermission();
    }

    final Position? pos = await _safeGetPosition(location);
    if (pos != null && mounted) {
      final LatLng latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _camera = latLng;
        _userPosition = latLng;
      });
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 15),
      );
    }
  }

  // Foreground location is mandatory. If the user denied it, explain why we
  // can't continue and close the app — there's nothing useful Wakey can do
  // without knowing where the phone is.
  Future<void> _showBlockingPermissionDialog(
      LocationPermissionState state) async {
    final String message;
    switch (state) {
      case LocationPermissionState.serviceDisabled:
        message =
            'Location services are turned off. Wakey can\'t wake you without '
            'them. Please enable location and reopen Wakey.';
        break;
      case LocationPermissionState.deniedForever:
        message =
            'Location permission is permanently denied. Wakey needs it to '
            'work. Enable it from Settings, then reopen Wakey.';
        break;
      default:
        message =
            'Wakey needs location access to trigger your arrival alarm. '
            'Without it the app can\'t function.';
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Location required', style: AppTextStyles.title),
          content: Text(message, style: AppTextStyles.bodyMuted),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // Close the app — Wakey is non-functional without location.
                SystemNavigator.pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // One-time background-permission walk-through. On Android 11+ the "Allow all
  // the time" choice lives on a system Settings page, so we show a rationale
  // first so the user knows to tap it and press back.
  Future<void> _ensureBackgroundPermissionWithRationale(
    LocationService location,
  ) async {
    final bool alreadyGranted =
        await location.ensureBackgroundPermission(allowPrompt: false);
    if (alreadyGranted || !mounted) return;

    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Wake you even when the phone is locked?',
            style: AppTextStyles.title,
          ),
          content: const Text(
            'For Wakey to alarm after you lock the phone or switch apps, '
            'Android needs the "Allow all the time" location permission.\n\n'
            'On the next screen, tap "Allow all the time", then press back. '
            'You can skip this and still use Wakey with the app open.',
            style: AppTextStyles.bodyMuted,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Skip'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    if (proceed != true || !mounted) return;
    await location.ensureBackgroundPermission(allowPrompt: true);
  }

  // One-time battery-optimization exemption walk-through. Android shows a
  // simple one-tap "Allow / Deny" system dialog for this, so the rationale is
  // brief — just enough that the user knows to tap Allow.
  Future<void> _ensureBatteryExemptionWithRationale(
    LocationService location,
  ) async {
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'One more step for reliable alarms',
            style: AppTextStyles.title,
          ),
          content: const Text(
            'Some phones (especially Samsung) put apps to sleep to save '
            'battery, which can stop Wakey from waking you. Allowing Wakey to '
            'ignore battery optimization keeps it running while you travel.\n\n'
            'Tap "Continue", then choose "Allow" on the next dialog.',
            style: AppTextStyles.bodyMuted,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Skip'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    if (proceed != true || !mounted) return;
    await location.ensureBatteryExemption();
  }

  Future<Position?> _safeGetPosition(LocationService service) async {
    try {
      return await service.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  void _centerOnUser() {
    final LatLng? user = _userPosition;
    if (user == null) return;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(user, 17));
  }

  // Home has no destination locked in — the "fit view" button zooms out to a
  // city-level overview centered on the user (or fallback location).
  void _fitOverview() {
    final LatLng center = _userPosition ?? _camera;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(center, 11));
  }

  void _openDestination(DestinationModel destination) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConfirmScreen(destination: destination),
      ),
    );
  }

  // Long-press on a saved place re-points it at the user's current location.
  // Useful for the seeded Home/Work/University, which start as placeholders.
  Future<void> _setSavedToCurrentLocation(DestinationModel place) async {
    final LocationService location = context.read<LocationService>();
    final StorageService storage = context.read<StorageService>();
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Set "${place.name}" to your current location?',
            style: AppTextStyles.title,
          ),
          content: Text(
            'Wakey will replace the saved coordinates of "${place.name}" with where you are right now.',
            style: AppTextStyles.bodyMuted,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Set'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    final Position? pos = await _safeGetPosition(location);
    if (pos == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read your location yet.')),
      );
      return;
    }
    final DestinationModel updated = place.copyWith(
      lat: pos.latitude,
      lng: pos.longitude,
      address:
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
    );
    await storage.updateSaved(updated);
    if (!navigator.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('"${place.name}" updated to current location.')),
    );
  }

  // Pen icon on a saved card opens the full map editor so the user can
  // re-point or rename the place from anywhere, not just while standing there.
  void _editSavedPlace(DestinationModel place) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedPlaceEditorScreen(initial: place),
      ),
    );
  }

  // Plus tile at the end of the saved row creates a brand-new favorite.
  void _addSavedPlace() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SavedPlaceEditorScreen(),
      ),
    );
  }

  // Delete badge only appears on removable favorites (i.e. anything the user
  // added). Confirm first so a misfire doesn't nuke a frequently-used place.
  Future<void> _deleteSavedPlace(DestinationModel place) async {
    final StorageService storage = context.read<StorageService>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Remove "${place.name}"?',
            style: AppTextStyles.title,
          ),
          content: const Text(
            'This favorite will be removed from your saved places.',
            style: AppTextStyles.bodyMuted,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Remove',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    await storage.removeSaved(place.id);
    messenger.showSnackBar(
      SnackBar(content: Text('"${place.name}" removed.')),
    );
  }

  Future<void> _useDefaultAlarmSound() async {
    await context.read<StorageService>().clearAlarmSound();
  }

  // Opens the system audio picker, copies the chosen file into the app's
  // documents dir (the picker's path is in a volatile cache on Android),
  // and saves the stable copy as the active alarm sound.
  Future<void> _pickAlarmSound() async {
    final StorageService storage = context.read<StorageService>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final PlatformFile picked = result.files.first;
      final String? srcPath = picked.path;
      if (srcPath == null) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Could not read the chosen file.'),
        ));
        return;
      }
      final Directory docs = await getApplicationDocumentsDirectory();
      final String safeName =
          picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final String destPath = '${docs.path}/wakey_alarm_$safeName';
      await File(srcPath).copy(destPath);
      await storage.setAlarmSound(path: destPath, label: picked.name);
      messenger.showSnackBar(SnackBar(
        content: Text('Alarm sound set to "${picked.name}".'),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Could not set that file as alarm sound.'),
      ));
    }
  }

  void _onPlaceSelected(PlaceResult place) {
    FocusScope.of(context).unfocus();
    final DestinationModel destination = DestinationModel.create(
      name: place.shortName,
      address: place.displayName,
      lat: place.lat,
      lng: place.lng,
      iconName: 'place',
    );
    _openDestination(destination);
  }

  Future<void> _onMapTap(LatLng point) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _tappedPoint = point;
      _tappedPlace = null;
      _resolvingTap = true;
    });
    final PlaceResult? resolved =
        await GeocodingService.reverseLookup(point.latitude, point.longitude);
    if (!mounted) return;
    if (_tappedPoint != point) return; // user tapped again before we returned
    setState(() {
      _tappedPlace = resolved;
      _resolvingTap = false;
    });
  }

  void _clearTap() {
    setState(() {
      _tappedPoint = null;
      _tappedPlace = null;
      _resolvingTap = false;
    });
  }

  // Returns the bottom offset for the map controls so they always hover just
  // above whichever bottom panel is currently active.
  //   • no panel pinned   → above the draggable sheet (extent-driven)
  //   • pin dropped       → above the measured _TapConfirmCard
  double _mapControlsBottomOffset(BuildContext context) {
    if (_tappedPoint != null) {
      return _tapCardHeight + 12;
    }
    return MediaQuery.of(context).size.height * _sheetExtent + 12;
  }

  // Schedule a post-frame measurement of the tap-confirm card so we can
  // update `_tapCardHeight`. Called from build() while the card is shown;
  // converges in a frame or two and stops as soon as the height is stable.
  void _scheduleTapCardMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tappedPoint == null) return;
      final RenderObject? ro =
          _tapCardKey.currentContext?.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final double h = ro.size.height;
        if ((h - _tapCardHeight).abs() > 1.0) {
          setState(() => _tapCardHeight = h);
        }
      }
    });
  }

  void _confirmTap() {
    final LatLng? point = _tappedPoint;
    if (point == null) return;
    final PlaceResult? place = _tappedPlace;
    final DestinationModel destination = DestinationModel.create(
      name: place?.shortName ?? 'Dropped pin',
      address: place?.displayName ??
          '${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)}',
      lat: point.latitude,
      lng: point.longitude,
      iconName: 'place',
    );
    _clearTap();
    _openDestination(destination);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-measure the tap-confirm card after this frame whenever it's mounted.
    // Cheap; the inner setState only fires if the height actually drifted.
    if (_tappedPoint != null) _scheduleTapCardMeasure();
    // PopScope: while the search bar is focused, swallow the back press and
    // unfocus instead of letting Flutter pop HomeScreen (which exits the app).
    // Tapping the map already unfocuses, so this only triggers when the user
    // is in the dropdown state with no other dismiss action.
    return PopScope(
      canPop: !_searchFocused,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _camera, zoom: 13),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            onTap: _onMapTap,
            markers: <Marker>{
              if (_tappedPoint != null)
                Marker(
                  markerId: const MarkerId('tapped'),
                  position: _tappedPoint!,
                ),
            },
          ),
          // Map controls track whichever bottom panel is currently visible —
          // the draggable sheet (extent-driven) when no pin is dropped, or
          // the tap-confirm card (measured height) when one is.
          // Hidden entirely while the search bar is focused.
          if (!_searchFocused)
            Positioned(
              right: 16,
              bottom: _mapControlsBottomOffset(context),
              child: MapControls(
                onMyLocation: _centerOnUser,
                onFitView: _fitOverview,
              ),
            ),
          if (_tappedPoint == null)
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (DraggableScrollableNotification notification) {
                if (notification.extent != _sheetExtent) {
                  setState(() => _sheetExtent = notification.extent);
                }
                return false;
              },
              child: DraggableScrollableSheet(
                initialChildSize: _sheetInitialSize,
                minChildSize: _sheetMinSize,
                maxChildSize: _sheetMaxSize,
                builder: (BuildContext context, ScrollController controller) {
                  return _BottomSheetContent(
                    scrollController: controller,
                    onSelect: _openDestination,
                    onSavedLongPress: _setSavedToCurrentLocation,
                    onSavedEdit: _editSavedPlace,
                    onSavedDelete: _deleteSavedPlace,
                    onAddSaved: _addSavedPlace,
                    onChooseSound: _pickAlarmSound,
                    onUseDefaultSound: _useDefaultAlarmSound,
                  );
                },
              ),
            )
          else
            Align(
              alignment: Alignment.bottomCenter,
              child: _TapConfirmCard(
                key: _tapCardKey,
                place: _tappedPlace,
                resolving: _resolvingTap,
                point: _tappedPoint!,
                onCancel: _clearTap,
                onConfirm: _confirmTap,
              ),
            ),
          // Search bar painted LAST so its focus dropdown floats above the
          // sheet and map controls instead of being clipped behind them.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _SearchBar(
                onSelected: _onPlaceSelected,
                onDestinationTap: _openDestination,
                onFocusChanged: (bool focused) {
                  if (_searchFocused != focused) {
                    setState(() => _searchFocused = focused);
                  }
                },
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _TapConfirmCard extends StatelessWidget {
  const _TapConfirmCard({
    super.key,
    required this.place,
    required this.resolving,
    required this.point,
    required this.onCancel,
    required this.onConfirm,
  });

  final PlaceResult? place;
  final bool resolving;
  final LatLng point;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final String title = place?.shortName ?? 'Dropped pin';
    final String subtitle = place?.displayName ??
        '${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 10),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primaryLight,
                    size: 22,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppTextStyles.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (resolving)
                        const Row(
                          children: <Widget>[
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryLight,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Looking up address…',
                              style: AppTextStyles.bodyMuted,
                            ),
                          ],
                        )
                      else
                        Text(
                          subtitle,
                          style: AppTextStyles.bodyMuted,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: onCancel,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Use this destination',
                  style: AppTextStyles.buttonMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.onSelected,
    required this.onDestinationTap,
    required this.onFocusChanged,
  });

  final ValueChanged<PlaceResult> onSelected;
  final ValueChanged<DestinationModel> onDestinationTap;
  final ValueChanged<bool> onFocusChanged;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  List<PlacePrediction> _results = const <PlacePrediction>[];
  bool _loading = false;
  String _lastQuery = '';
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
      widget.onFocusChanged(_focused);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final String trimmed = value.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = const <PlacePrediction>[];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _lastQuery = query;
    });
    final List<PlacePrediction> results =
        await GeocodingService.searchPlaces(query);
    if (!mounted || query != _lastQuery) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _select(PlacePrediction prediction) async {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    _controller.clear();
    setState(() {
      _results = const <PlacePrediction>[];
      _lastQuery = '';
      _loading = true;
    });
    final PlaceResult? place =
        await GeocodingService.getPlaceDetails(prediction.placeId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (place != null) widget.onSelected(place);
  }

  void _onShortcutTap(DestinationModel destination) {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    _controller.clear();
    setState(() {
      _results = const <PlacePrediction>[];
      _lastQuery = '';
    });
    widget.onDestinationTap(destination);
  }

  @override
  Widget build(BuildContext context) {
    final StorageService storage = context.watch<StorageService>();
    final List<DestinationModel> saved = storage.saved;
    final List<DestinationModel> recent = storage.recent;
    final bool showShortcuts = _focused && _results.isEmpty && _lastQuery.isEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              const Icon(Icons.search_rounded, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _onChanged,
                  style: AppTextStyles.bodyLarge,
                  textInputAction: TextInputAction.search,
                  // filled:false here overrides the global theme so we don't
                  // double-stack a TextField fill on top of the Container's
                  // purple — that's what made the bar look two-toned.
                  decoration: const InputDecoration(
                    hintText: 'Where are you going?',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryLight,
                  ),
                ),
            ],
          ),
        ),
        if (showShortcuts)
          _ShortcutsPanel(
            saved: saved,
            recent: recent,
            onShortcutTap: _onShortcutTap,
          )
        else if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(
                color: AppColors.surfaceLight,
                height: 1,
                indent: 12,
                endIndent: 12,
              ),
              itemBuilder: (BuildContext context, int i) {
                final PlacePrediction p = _results[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _select(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.place_outlined,
                            color: AppColors.primaryLight,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                p.mainText.isNotEmpty
                                    ? p.mainText
                                    : p.description,
                                style: AppTextStyles.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (p.secondaryText.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(
                                  p.secondaryText,
                                  style: AppTextStyles.bodyMuted,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// Dropdown shown right under the focused search bar when the field is empty.
// Two stacked sections:
//   FAVORITES — horizontal scroll of compact pill chips.
//   RECENT    — vertical list of last few destinations.
class _ShortcutsPanel extends StatelessWidget {
  const _ShortcutsPanel({
    required this.saved,
    required this.recent,
    required this.onShortcutTap,
  });

  final List<DestinationModel> saved;
  final List<DestinationModel> recent;
  final ValueChanged<DestinationModel> onShortcutTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.45,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (saved.isNotEmpty) ...<Widget>[
              const Text('FAVORITES', style: AppTextStyles.sectionLabel),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: saved.length,
                  itemBuilder: (BuildContext context, int i) {
                    final DestinationModel d = saved[i];
                    return _FavoriteChip(
                      destination: d,
                      onTap: () => onShortcutTap(d),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
            ],
            const Text('RECENT', style: AppTextStyles.sectionLabel),
            const SizedBox(height: 6),
            if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'No recent searches yet.',
                  style: AppTextStyles.bodyMuted,
                ),
              )
            else
              for (final DestinationModel d in recent)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onShortcutTap(d),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 2, right: 10),
                          child: Icon(
                            Icons.history_rounded,
                            color: AppColors.primaryLight,
                            size: 18,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                d.name,
                                style: AppTextStyles.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                d.address,
                                style: AppTextStyles.bodyMuted
                                    .copyWith(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// Small pill rendered inside the search dropdown's FAVORITES row. Kept
// deliberately smaller than the main saved-place card so it reads as a
// secondary shortcut, not a full action.
class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({required this.destination, required this.onTap});

  final DestinationModel destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  DestinationModel.iconFor(destination.iconName),
                  color: AppColors.primaryLight,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  destination.name,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomSheetContent extends StatelessWidget {
  const _BottomSheetContent({
    required this.scrollController,
    required this.onSelect,
    required this.onSavedLongPress,
    required this.onSavedEdit,
    required this.onSavedDelete,
    required this.onAddSaved,
    required this.onChooseSound,
    required this.onUseDefaultSound,
  });

  final ScrollController scrollController;
  final ValueChanged<DestinationModel> onSelect;
  final ValueChanged<DestinationModel> onSavedLongPress;
  final ValueChanged<DestinationModel> onSavedEdit;
  final ValueChanged<DestinationModel> onSavedDelete;
  final VoidCallback onAddSaved;
  final VoidCallback onChooseSound;
  final VoidCallback onUseDefaultSound;

  @override
  Widget build(BuildContext context) {
    final StorageService storage = context.watch<StorageService>();
    final List<DestinationModel> saved = storage.saved;
    final List<DestinationModel> recent = storage.recent;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: <Widget>[
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text('SAVED PLACES', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 12),
          SizedBox(
            // Matches the new 78-px card height with a hair of headroom.
            height: 84,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              // +1 for the trailing "Add" tile.
              itemCount: saved.length + 1,
              itemBuilder: (BuildContext context, int index) {
                if (index == saved.length) {
                  return AddSavedPlaceCard(onTap: onAddSaved);
                }
                final DestinationModel place = saved[index];
                return SavedPlaceCard(
                  destination: place,
                  onTap: () => onSelect(place),
                  onLongPress: () => onSavedLongPress(place),
                  onEdit: () => onSavedEdit(place),
                  onDelete: place.removable
                      ? () => onSavedDelete(place)
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          const Text('ALARM SOUND', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 10),
          SizedBox(
            // Matches the new compact 56-px alarm card.
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _AlarmSoundCard(
                  label: 'Default beep',
                  icon: Icons.notifications_active_rounded,
                  isActive: storage.alarmSoundPath == null,
                  onTap: onUseDefaultSound,
                ),
                _AlarmSoundCard(
                  label: storage.alarmSoundLabel ?? 'Choose audio',
                  icon: storage.alarmSoundPath == null
                      ? Icons.add_rounded
                      : Icons.music_note_rounded,
                  isActive: storage.alarmSoundPath != null,
                  onTap: onChooseSound,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('RECENT', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No recent destinations yet. Search a place to get started.',
                style: AppTextStyles.bodyMuted,
                textAlign: TextAlign.center,
              ),
            )
          else
            Column(
              children: <Widget>[
                for (final DestinationModel place in recent) ...<Widget>[
                  RecentPlaceCard(
                    destination: place,
                    onTap: () => onSelect(place),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _AlarmSoundCard extends StatelessWidget {
  const _AlarmSoundCard({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  // Sized down deliberately so it reads as a chip, not a primary card —
  // smaller than SavedPlaceCard (172×78) so the row feels secondary.
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 144,
        height: 56,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.primaryLight
                : Colors.white.withValues(alpha: 0.06),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primaryLight, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primaryLight,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
