import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_text_styles.dart';

// Deliberately minimal for v1: one reliability control (the thing that actually
// makes alarms fail on aggressive OEMs) plus the About/legal links the store
// expects. Everything here uses dependencies the app already ships.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _batteryExempt = false;
  bool _checkingBattery = true;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    bool exempt = true;
    if (Platform.isAndroid) {
      exempt = await Permission.ignoreBatteryOptimizations.isGranted;
    }
    if (!mounted) return;
    setState(() {
      _version = 'v${info.version} (${info.buildNumber})';
      _batteryExempt = exempt;
      _checkingBattery = false;
    });
  }

  Future<void> _fixBattery() async {
    await Permission.ignoreBatteryOptimizations.request();
    await _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings', style: AppTextStyles.title),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          if (Platform.isAndroid) ...<Widget>[
            const _SectionHeader('ALARM RELIABILITY'),
            ListTile(
              leading: const Icon(Icons.battery_saver_rounded,
                  color: AppColors.primaryLight),
              title: const Text('Battery optimization',
                  style: AppTextStyles.bodyLarge),
              subtitle: Text(
                _checkingBattery
                    ? 'Checking…'
                    : _batteryExempt
                        ? 'Allowed to run in the background — the alarm can '
                            'fire reliably.'
                        : 'Restricted. Tap to let WakeMe run in the background '
                            'so the alarm always fires.',
                style: AppTextStyles.bodyMuted,
              ),
              trailing: _checkingBattery
                  ? null
                  : Icon(
                      _batteryExempt
                          ? Icons.check_circle_rounded
                          : Icons.chevron_right_rounded,
                      color: _batteryExempt
                          ? AppColors.primaryLight
                          : AppColors.textMuted,
                    ),
              onTap: _batteryExempt ? null : _fixBattery,
            ),
          ],
          const _SectionHeader('ABOUT'),
          ListTile(
            leading:
                const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary),
            title: const Text('Version', style: AppTextStyles.bodyLarge),
            trailing: Text(_version, style: AppTextStyles.bodyMuted),
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
            title:
                const Text('Contact support', style: AppTextStyles.bodyLarge),
            subtitle: const Text(AppConstants.supportEmail,
                style: AppTextStyles.bodyMuted),
            onTap: _emailSupport,
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined,
                color: AppColors.textSecondary),
            title: const Text('Open-source licenses',
                style: AppTextStyles.bodyLarge),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConstants.appName,
              applicationVersion: _version,
            ),
          ),
        ],
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
