import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/storage_service.dart';

// Two areas the user cares about: how the alarm sounds (tone / volume /
// vibration) and the About/legal block. The alarm prefs are wired to real
// behaviour — read at fire-time by the background isolate.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  // Local mirror of the volume so the slider stays smooth while dragging; the
  // committed value is written to storage on change-end only (avoids a disk
  // write per pixel).
  double _volume = AppConstants.defaultAlarmVolume;

  @override
  void initState() {
    super.initState();
    _volume = context.read<StorageService>().alarmVolume;
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = 'v${info.version} (${info.buildNumber})');
  }

  // Opens the system audio picker, copies the chosen file into the app's
  // documents dir (the picker's path is volatile cache on Android), and saves
  // the stable copy as the default alarm sound. Mirrors the Home flow.
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
      final String destPath = '${docs.path}/wakeme_alarm_$safeName';
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

  Future<void> _resetAlarmSound() async {
    await context.read<StorageService>().clearAlarmSound();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Alarm sound reset to the default beep.'),
    ));
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _emailSupport() async {
    final Uri uri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      query: 'subject=WakeMe support',
    );
    await launchUrl(uri);
  }

  // Single, tidy About surface: app name, version, the short story, how it
  // works, and a built-in licenses button — all in one dialog.
  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: _version,
      applicationIcon: const Icon(Icons.notifications_active_rounded,
          color: AppColors.primaryLight, size: 40),
      children: const <Widget>[
        SizedBox(height: 8),
        Text(AppConstants.tagline, style: AppTextStyles.bodyMuted),
        SizedBox(height: 12),
        Text(
          'WakeMe started from one annoying problem: dozing off on the bus '
          'or train and waking up past your stop. So it does one thing well '
          '— it watches your location and wakes you the moment you are '
          'almost there.',
        ),
        SizedBox(height: 12),
        Text(
          'How it works: pick a destination, press Sleep, then rest. WakeMe '
          'keeps tracking in the background — even with the screen locked — '
          'and rings a full-screen alarm as you approach. Your location '
          'never leaves your phone.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final StorageService storage = context.watch<StorageService>();
    final bool customSound = storage.alarmSoundPath != null;
    final String soundLabel = storage.alarmSoundLabel ?? 'Default beep';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings', style: AppTextStyles.title),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            // ---- ALARM ------------------------------------------------
            const _SectionHeader('ALARM'),
            ListTile(
              leading: const Icon(Icons.music_note_rounded,
                  color: AppColors.primaryLight),
              title: const Text('Alarm sound', style: AppTextStyles.bodyLarge),
              subtitle: Text(soundLabel, style: AppTextStyles.bodyMuted),
              trailing: customSound
                  ? TextButton(
                      onPressed: _resetAlarmSound,
                      child: const Text('Reset'),
                    )
                  : const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted),
              onTap: _pickAlarmSound,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.volume_up_rounded,
                      color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  const Text('Volume', style: AppTextStyles.bodyLarge),
                  const Spacer(),
                  Text('${(_volume * 100).round()}%',
                      style: AppTextStyles.bodyMuted),
                ],
              ),
            ),
            Slider(
              value: _volume,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              activeColor: AppColors.primaryLight,
              label: '${(_volume * 100).round()}%',
              onChanged: (double v) => setState(() => _volume = v),
              onChangeEnd: (double v) =>
                  context.read<StorageService>().setAlarmVolume(v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration_rounded,
                  color: AppColors.primaryLight),
              title: const Text('Vibration', style: AppTextStyles.bodyLarge),
              subtitle: Text(
                storage.alarmVibrate
                    ? 'The phone vibrates with the alarm.'
                    : 'Sound only — no vibration.',
                style: AppTextStyles.bodyMuted,
              ),
              value: storage.alarmVibrate,
              activeThumbColor: AppColors.primaryLight,
              onChanged: (bool on) =>
                  context.read<StorageService>().setAlarmVibrate(on),
            ),

            // ---- ABOUT ------------------------------------------------
            const _SectionHeader('ABOUT'),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded,
                  color: AppColors.primaryLight),
              title: const Text('About WakeMe',
                  style: AppTextStyles.bodyLarge),
              subtitle: Text(
                _version.isEmpty ? 'Version & app info' : _version,
                style: AppTextStyles.bodyMuted,
              ),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
              onTap: _showAbout,
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined,
                  color: AppColors.textSecondary),
              title:
                  const Text('Privacy Policy', style: AppTextStyles.bodyLarge),
              trailing: const Icon(Icons.open_in_new_rounded,
                  size: 18, color: AppColors.textMuted),
              onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline_rounded,
                  color: AppColors.textSecondary),
              title: const Text('Contact support',
                  style: AppTextStyles.bodyLarge),
              subtitle: const Text(AppConstants.supportEmail,
                  style: AppTextStyles.bodyMuted),
              onTap: _emailSupport,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(label, style: AppTextStyles.sectionLabel),
    );
  }
}
