import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../models/destination_model.dart';

class StorageService extends ChangeNotifier {
  StorageService();

  SharedPreferences? _prefs;
  List<DestinationModel> _recent = <DestinationModel>[];
  List<DestinationModel> _saved = <DestinationModel>[];
  String? _alarmSoundPath;
  String? _alarmSoundLabel;
  double _alarmVolume = AppConstants.defaultAlarmVolume;
  bool _alarmVibrate = AppConstants.defaultAlarmVibrate;

  List<DestinationModel> get recent => List.unmodifiable(_recent);
  List<DestinationModel> get saved => List.unmodifiable(_saved);

  // null => use the bundled default beep
  String? get alarmSoundPath => _alarmSoundPath;
  String? get alarmSoundLabel => _alarmSoundLabel;

  // Alarm playback prefs (0.0–1.0 volume; vibration on/off). Defaults applied
  // when the keys were never written.
  double get alarmVolume => _alarmVolume;
  bool get alarmVibrate => _alarmVibrate;

  // True once we've taken the user through the background-location prompt.
  bool get askedBackgroundPermission =>
      _prefs?.getBool(AppConstants.prefsAskedBackgroundKey) ?? false;

  Future<void> markAskedBackgroundPermission() async {
    await _prefs?.setBool(AppConstants.prefsAskedBackgroundKey, true);
  }

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _recent = _readList(AppConstants.prefsRecentKey);
    _saved = _readList(AppConstants.prefsSavedKey);
    if (_saved.isEmpty) {
      _saved = _seedSavedPlaces();
      await _writeList(AppConstants.prefsSavedKey, _saved);
    } else {
      await _migrateSavedPlacesSchema();
    }
    _alarmSoundPath = _prefs?.getString(AppConstants.prefsAlarmSoundPathKey);
    _alarmSoundLabel = _prefs?.getString(AppConstants.prefsAlarmSoundLabelKey);
    _alarmVolume = _prefs?.getDouble(AppConstants.prefsAlarmVolumeKey) ??
        AppConstants.defaultAlarmVolume;
    _alarmVibrate = _prefs?.getBool(AppConstants.prefsAlarmVibrateKey) ??
        AppConstants.defaultAlarmVibrate;
    notifyListeners();
  }

  // One-shot upgrade for users who already had Home/University/Work saved
  // before the `removable` flag existed. fromMap defaults `removable` to true
  // for any entry whose JSON lacked the field, which would surface a delete
  // badge on the three seeded defaults. Match by (name, iconName) of the seed
  // and force-flip them to non-removable.
  Future<void> _migrateSavedPlacesSchema() async {
    const Map<String, String> seedNameToIcon = <String, String>{
      'Home': 'home',
      'University': 'university',
      'Work': 'work',
    };
    bool changed = false;
    for (int i = 0; i < _saved.length; i++) {
      final DestinationModel d = _saved[i];
      final String? expectedIcon = seedNameToIcon[d.name];
      if (expectedIcon != null &&
          d.iconName == expectedIcon &&
          d.removable) {
        _saved[i] = d.copyWith(removable: false);
        changed = true;
      }
    }
    if (changed) {
      await _writeList(AppConstants.prefsSavedKey, _saved);
    }
  }

  Future<void> setAlarmSound({required String path, required String label}) async {
    _alarmSoundPath = path;
    _alarmSoundLabel = label;
    await _prefs?.setString(AppConstants.prefsAlarmSoundPathKey, path);
    await _prefs?.setString(AppConstants.prefsAlarmSoundLabelKey, label);
    notifyListeners();
  }

  Future<void> clearAlarmSound() async {
    _alarmSoundPath = null;
    _alarmSoundLabel = null;
    await _prefs?.remove(AppConstants.prefsAlarmSoundPathKey);
    await _prefs?.remove(AppConstants.prefsAlarmSoundLabelKey);
    notifyListeners();
  }

  Future<void> setAlarmVolume(double volume) async {
    _alarmVolume = volume.clamp(0.0, 1.0);
    await _prefs?.setDouble(AppConstants.prefsAlarmVolumeKey, _alarmVolume);
    notifyListeners();
  }

  Future<void> setAlarmVibrate(bool enabled) async {
    _alarmVibrate = enabled;
    await _prefs?.setBool(AppConstants.prefsAlarmVibrateKey, enabled);
    notifyListeners();
  }

  List<DestinationModel> _readList(String key) {
    final String? raw = _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return <DestinationModel>[];
    try {
      final List<dynamic> data = jsonDecode(raw) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(DestinationModel.fromMap)
          .toList();
    } catch (_) {
      return <DestinationModel>[];
    }
  }

  Future<void> _writeList(
      String key, List<DestinationModel> items) async {
    final String encoded =
        jsonEncode(items.map((DestinationModel d) => d.toMap()).toList());
    await _prefs?.setString(key, encoded);
  }

  Future<void> addRecent(DestinationModel destination) async {
    _recent.removeWhere((DestinationModel d) => d.id == destination.id);
    _recent.insert(0, destination);
    if (_recent.length > AppConstants.maxRecentPlaces) {
      _recent = _recent.sublist(0, AppConstants.maxRecentPlaces);
    }
    await _writeList(AppConstants.prefsRecentKey, _recent);
    notifyListeners();
  }

  Future<void> clearRecent() async {
    _recent = <DestinationModel>[];
    await _writeList(AppConstants.prefsRecentKey, _recent);
    notifyListeners();
  }

  Future<void> addSaved(DestinationModel destination) async {
    _saved.removeWhere((DestinationModel d) => d.id == destination.id);
    _saved.add(destination);
    await _writeList(AppConstants.prefsSavedKey, _saved);
    notifyListeners();
  }

  Future<void> removeSaved(String id) async {
    _saved.removeWhere((DestinationModel d) => d.id == id);
    await _writeList(AppConstants.prefsSavedKey, _saved);
    notifyListeners();
  }

  Future<void> updateSaved(DestinationModel updated) async {
    final int idx = _saved.indexWhere((DestinationModel d) => d.id == updated.id);
    if (idx == -1) return;
    _saved[idx] = updated;
    await _writeList(AppConstants.prefsSavedKey, _saved);
    notifyListeners();
  }

  List<DestinationModel> _seedSavedPlaces() {
    return <DestinationModel>[
      DestinationModel.create(
        name: 'Home',
        address: 'Set your home address',
        lat: 30.0444,
        lng: 31.2357,
        iconName: 'home',
        removable: false,
      ),
      DestinationModel.create(
        name: 'University',
        address: 'Set your university address',
        lat: 30.0264,
        lng: 31.2106,
        iconName: 'university',
        removable: false,
      ),
      DestinationModel.create(
        name: 'Work',
        address: 'Set your work address',
        lat: 30.0626,
        lng: 31.2497,
        iconName: 'work',
        removable: false,
      ),
    ];
  }
}
