import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class RadiusSlider extends StatelessWidget {
  const RadiusSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.routeDistanceMeters,
    this.routeDurationSeconds,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  // Both null => route unknown, show a "Calculating ETA…" placeholder.
  final double? routeDistanceMeters;
  final double? routeDurationSeconds;

  String _distanceLabel(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} km';
    }
    return '${meters.round()} m';
  }

  String _timeLabel() {
    final double? d = routeDistanceMeters;
    final double? t = routeDurationSeconds;
    if (d == null || t == null || d <= 0) return 'Calculating ETA…';
    // Time before arrival = radius / average speed = radius * duration / distance.
    final double seconds = value * t / d;
    if (seconds < 60) return '~${seconds.round()} s before';
    final int minutes = (seconds / 60).round();
    if (minutes < 60) return '~$minutes min before';
    final int hours = minutes ~/ 60;
    final int rem = minutes % 60;
    return rem == 0 ? '~$hours h before' : '~$hours h $rem min before';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Trigger radius', style: AppTextStyles.sectionLabel),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  _distanceLabel(value),
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(_timeLabel(), style: AppTextStyles.caption),
              ],
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.surfaceLight,
            thumbColor: AppColors.primaryLight,
            overlayColor: AppColors.primary.withValues(alpha: 0.2),
            trackHeight: 4,
          ),
          child: Slider(
            min: min,
            max: max,
            divisions: ((max - min) / 50).round(),
            value: value.clamp(min, max),
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(_distanceLabel(min), style: AppTextStyles.caption),
            Text(_distanceLabel(max), style: AppTextStyles.caption),
          ],
        ),
      ],
    );
  }
}
