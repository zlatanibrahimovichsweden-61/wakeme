import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../services/background_alarm_service.dart';

// ════════════════════════════════════════════════════════════════════════
// TEST-ONLY — temporary in-app testing harness for the alarm-arrival flow.
//
// Lets you fire a FAKE arrival without physically travelling into the radius.
// The 5-second countdown is owned by the background service isolate, so it
// fires correctly even after you leave WakeMe, lock the screen, or swipe the
// app away — exactly the scenarios that are otherwise impossible to test.
//
// HOW TO REMOVE after the testing phase:
//   • Quickest:  set kTestMode = false below (the 🧪 button and all hooks
//     vanish instantly, no other change needed).
//   • Clean:     delete this file, the two `if (kTestMode) const TestFab()`
//     lines in home_screen.dart / armed_screen.dart, and the four
//     `// TEST-ONLY` blocks in background_alarm_service.dart.
// ════════════════════════════════════════════════════════════════════════

/// Master switch for the whole testing harness. Flip to false to disable.
const bool kTestMode = false;

/// Small floating 🧪 button that opens the test panel. Renders nothing when
/// the harness is off, so it's safe to leave in the widget tree unconditionally.
class TestFab extends StatelessWidget {
  const TestFab({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kTestMode) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: FloatingActionButton.small(
          heroTag: null,
          backgroundColor: Colors.deepPurple,
          onPressed: () => _open(context),
          child: const Text('🧪', style: TextStyle(fontSize: 18)),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _TestPanel(),
    );
  }
}

class _TestPanel extends StatefulWidget {
  const _TestPanel();

  @override
  State<_TestPanel> createState() => _TestPanelState();
}

class _TestPanelState extends State<_TestPanel> {
  bool _loading = true;
  bool _armed = false;
  String _dest = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final bool armed = await BackgroundAlarmService.isArmed();
    final String dest = await BackgroundAlarmService.armedName();
    if (!mounted) return;
    setState(() {
      _armed = armed;
      _dest = dest;
      _loading = false;
    });
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _arriveIn5() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await BackgroundAlarmService.testEnsureArmed();
    await BackgroundAlarmService.testArriveIn(const Duration(seconds: 5));
    _close();
    messenger.showSnackBar(const SnackBar(
      content: Text('Arriving in 5s — switch apps or lock the screen now.'),
      duration: Duration(seconds: 4),
    ));
  }

  Future<void> _arriveNow() async {
    await BackgroundAlarmService.testEnsureArmed();
    await BackgroundAlarmService.testArriveIn(Duration.zero);
    _close();
  }

  Future<void> _reset() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await BackgroundAlarmService.testReset();
    messenger.showSnackBar(const SnackBar(
      content: Text('Pending test arrival cleared.'),
    ));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Text('🧪 ', style: TextStyle(fontSize: 16)),
                Text('TEST MODE', style: AppTextStyles.sectionLabel),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _loading
                  ? 'Checking…'
                  : _armed
                      ? 'Armed: ${_dest.isEmpty ? 'destination' : _dest}'
                      : 'No trip armed — the buttons below arm a test trip '
                          'automatically.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _arriveIn5,
              child: const Text('Arrive in 5s'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _arriveNow,
              child: const Text('Arrive now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _reset,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
