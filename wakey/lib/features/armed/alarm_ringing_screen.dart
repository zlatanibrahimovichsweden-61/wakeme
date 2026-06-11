import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

// Full-screen arrival alarm — modeled on the stock Android alarm-clock screen:
// a clean, full-bleed surface (no map behind it) with a live clock, a pulsing
// pin, and a slide-to-dismiss control. Shown over the lock screen because
// MainActivity declares showWhenLocked + turnScreenOn.
class AlarmRingingScreen extends StatefulWidget {
  const AlarmRingingScreen({
    super.key,
    required this.destinationName,
    required this.radiusMeters,
    required this.onDismiss,
  });

  final String destinationName;
  final double radiusMeters;
  // Single dismissal path shared with the volume keys + lock button.
  final Future<void> Function() onDismiss;

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _clock;
  late String _time;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _time = _formatNow();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _time = _formatNow());
    });
  }

  String _formatNow() {
    final DateTime now = DateTime.now();
    final int h24 = now.hour;
    final int h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final String m = now.minute.toString().padLeft(2, '0');
    final String period = h24 < 12 ? 'AM' : 'PM';
    return '$h12:$m $period';
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    setState(() => _dismissing = true);
    await widget.onDismiss();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Block the system back gesture — the alarm is dismissed only by the
    // slider, a volume key, or the lock button (matches a real alarm clock).
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[AppColors.surface, AppColors.background],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const Spacer(flex: 2),
                  // Live clock.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _time,
                      style: AppTextStyles.displayLarge.copyWith(
                        fontSize: 54,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'WAKEY',
                    style: AppTextStyles.sectionLabel.copyWith(
                      color: AppColors.primaryLight,
                      letterSpacing: 5,
                    ),
                  ),
                  const Spacer(flex: 2),
                  // Pulsing pin.
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.86, end: 1.12).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      width: 124,
                      height: 124,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.25),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: AppColors.primaryLight.withValues(alpha: 0.4),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on,
                        size: 60,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    "You're almost there!",
                    style: AppTextStyles.headline,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Within ${widget.radiusMeters.round()} m of '
                    '${widget.destinationName}',
                    style: AppTextStyles.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(flex: 3),
                  // Slide-to-dismiss.
                  _SlideToDismiss(onDismissed: _dismiss),
                  const SizedBox(height: 14),
                  const Text(
                    'Slide to dismiss · or press volume / lock',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Full-width slide-to-dismiss. The ENTIRE track is draggable (not just the
// knob). Reaching the end auto-fires; releasing past 65% also fires; otherwise
// the knob springs back.
class _SlideToDismiss extends StatefulWidget {
  const _SlideToDismiss({required this.onDismissed});

  final VoidCallback onDismissed;

  @override
  State<_SlideToDismiss> createState() => _SlideToDismissState();
}

class _SlideToDismissState extends State<_SlideToDismiss> {
  static const double _trackHeight = 66;
  static const double _knobSize = 58;
  static const double _pad = 4;
  double _dragX = 0;
  bool _fired = false;

  void _fire() {
    if (_fired) return;
    _fired = true;
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxX = constraints.maxWidth - _knobSize - _pad * 2;
        final double progress =
            maxX <= 0 ? 0 : (_dragX / maxX).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (DragUpdateDetails d) {
            if (_fired) return;
            setState(() => _dragX = (_dragX + d.delta.dx).clamp(0.0, maxX));
            if (_dragX >= maxX - 0.5) _fire();
          },
          onHorizontalDragEnd: (DragEndDetails d) {
            if (_fired) return;
            if (progress >= 0.65) {
              setState(() => _dragX = maxX);
              _fire();
            } else {
              setState(() => _dragX = 0);
            }
          },
          child: Container(
            width: double.infinity,
            height: _trackHeight,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(_trackHeight / 2),
              border: Border.all(
                color: AppColors.primaryLight.withValues(alpha: 0.3),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Opacity(
                  opacity: (1 - progress * 1.6).clamp(0.0, 1.0),
                  child: Text(
                    'Slide to dismiss',
                    style: AppTextStyles.buttonMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: _pad + _dragX),
                    child: Container(
                      width: _knobSize,
                      height: _knobSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                      child: const Icon(
                        Icons.keyboard_double_arrow_right,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
