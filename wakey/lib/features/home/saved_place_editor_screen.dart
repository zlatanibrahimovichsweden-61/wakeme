import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/destination_model.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/storage_service.dart';

// Full-screen editor used both to create a brand-new favorite and to re-point
// an existing one. The pin is fixed to the camera centre — the user pans the
// map until the pin is where they want, then saves.
class SavedPlaceEditorScreen extends StatefulWidget {
  const SavedPlaceEditorScreen({
    super.key,
    this.initial,
    this.iconNameForNew = 'star',
  });

  final DestinationModel? initial;
  final String iconNameForNew;

  @override
  State<SavedPlaceEditorScreen> createState() => _SavedPlaceEditorScreenState();
}

class _SavedPlaceEditorScreenState extends State<SavedPlaceEditorScreen> {
  GoogleMapController? _mapController;
  late final TextEditingController _nameController;
  late LatLng _pinPosition;
  String _addressLabel = '';
  bool _resolving = false;
  Timer? _resolveDebounce;
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final DestinationModel? initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _pinPosition = initial == null
        ? const LatLng(30.0444, 31.2357)
        : LatLng(initial.lat, initial.lng);
    _addressLabel = initial?.address ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedCameraOnUser());
  }

  // For brand-new entries, jump the map to the user's GPS so they can drop
  // a pin near themselves with one tap. For edits we keep the saved location.
  Future<void> _seedCameraOnUser() async {
    if (_isEdit) return;
    final LocationService location = context.read<LocationService>();
    final Position? pos = await location.getCurrentPosition();
    if (!mounted || pos == null) return;
    final LatLng user = LatLng(pos.latitude, pos.longitude);
    setState(() => _pinPosition = user);
    await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(user, 16));
    _scheduleReverseLookup();
  }

  void _onCameraMove(CameraPosition position) {
    _pinPosition = position.target;
  }

  void _onCameraIdle() {
    if (!mounted) return;
    setState(() {});
    _scheduleReverseLookup();
  }

  // Debounce so panning quickly doesn't fire dozens of geocoder requests.
  void _scheduleReverseLookup() {
    _resolveDebounce?.cancel();
    setState(() => _resolving = true);
    _resolveDebounce =
        Timer(const Duration(milliseconds: 600), _reverseLookup);
  }

  Future<void> _reverseLookup() async {
    final LatLng pin = _pinPosition;
    final PlaceResult? result = await GeocodingService.reverseLookup(
      pin.latitude,
      pin.longitude,
    );
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _addressLabel = result?.displayName ??
          '${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)}';
    });
  }

  Future<void> _centerOnUser() async {
    final LocationService location = context.read<LocationService>();
    final Position? pos = await location.getCurrentPosition();
    if (pos == null) return;
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
    );
  }

  Future<void> _save() async {
    final String trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give this place a name.')),
      );
      return;
    }
    setState(() => _saving = true);
    final StorageService storage = context.read<StorageService>();
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String address = _addressLabel.isEmpty
        ? '${_pinPosition.latitude.toStringAsFixed(5)}, ${_pinPosition.longitude.toStringAsFixed(5)}'
        : _addressLabel;

    if (_isEdit) {
      final DestinationModel updated = widget.initial!.copyWith(
        name: trimmedName,
        address: address,
        lat: _pinPosition.latitude,
        lng: _pinPosition.longitude,
      );
      await storage.updateSaved(updated);
    } else {
      final DestinationModel created = DestinationModel.create(
        name: trimmedName,
        address: address,
        lat: _pinPosition.latitude,
        lng: _pinPosition.longitude,
        iconName: widget.iconNameForNew,
      );
      await storage.addSaved(created);
    }

    if (!navigator.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(_isEdit
          ? '"$trimmedName" updated.'
          : '"$trimmedName" added to favorites.'),
    ));
    navigator.pop();
  }

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    _nameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pinPosition,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              if (_isEdit) _scheduleReverseLookup();
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
          ),
          // Fixed centre pin — sits at screen centre regardless of pan.
          IgnorePointer(
            child: Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primaryLight,
                    size: 44,
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: <Widget>[
                  _RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SearchBar(
                      onSelected: (PlaceResult place) async {
                        final LatLng target = LatLng(place.lat, place.lng);
                        _pinPosition = target;
                        await _mapController?.animateCamera(
                          CameraUpdate.newLatLngZoom(target, 16),
                        );
                        setState(() {
                          _addressLabel = place.displayName;
                          _resolving = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 260,
            child: _RoundIconButton(
              icon: Icons.my_location_rounded,
              onTap: _centerOnUser,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _EditorBottomCard(
              isEdit: _isEdit,
              nameController: _nameController,
              addressLabel: _addressLabel,
              resolving: _resolving,
              saving: _saving,
              onSave: _save,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorBottomCard extends StatelessWidget {
  const _EditorBottomCard({
    required this.isEdit,
    required this.nameController,
    required this.addressLabel,
    required this.resolving,
    required this.saving,
    required this.onSave,
  });

  final bool isEdit;
  final TextEditingController nameController;
  final String addressLabel;
  final bool resolving;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
            Text(
              isEdit ? 'Edit favorite' : 'New favorite',
              style: AppTextStyles.headline,
            ),
            const SizedBox(height: 4),
            const Text(
              'Pan the map to position the pin.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameController,
              style: AppTextStyles.bodyLarge,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Name (e.g. Mom\'s place)',
                prefixIcon: Icon(Icons.label_outline_rounded,
                    color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: 8),
                  child: Icon(
                    Icons.place_outlined,
                    color: AppColors.primaryLight,
                    size: 18,
                  ),
                ),
                Expanded(
                  child: resolving && addressLabel.isEmpty
                      ? const Text(
                          'Looking up address…',
                          style: AppTextStyles.bodyMuted,
                        )
                      : Text(
                          addressLabel.isEmpty
                              ? 'Pin the location on the map.'
                              : addressLabel,
                          style: AppTextStyles.bodyMuted,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: saving ? null : onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : Text(
                        isEdit ? 'Save changes' : 'Add favorite',
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: AppColors.primaryLight, size: 22),
        ),
      ),
    );
  }
}

// Minimal search bar reused inside the editor. Mirrors the home-screen
// version but skips the giant results panel — results inline below the field.
class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.onSelected});

  final ValueChanged<PlaceResult> onSelected;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<PlacePrediction> _results = const <PlacePrediction>[];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              const Icon(Icons.search_rounded, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  style: AppTextStyles.body,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search address…',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryLight,
                  ),
                ),
            ],
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.35,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(
                color: AppColors.surfaceLight,
                height: 1,
              ),
              itemBuilder: (BuildContext context, int i) {
                final PlacePrediction p = _results[i];
                return InkWell(
                  onTap: () => _select(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.place_outlined,
                            color: AppColors.primaryLight,
                            size: 18,
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
