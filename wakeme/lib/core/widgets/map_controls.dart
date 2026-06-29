import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

// Vertical stack of two map-control buttons (bottom-right of a FlutterMap).
// Top button: fit-view (route bounds or city overview); hidden when
// `onFitView` is null. Bottom button: snap to user's location.
class MapControls extends StatelessWidget {
  const MapControls({
    super.key,
    required this.onMyLocation,
    this.onFitView,
  });

  final VoidCallback onMyLocation;
  final VoidCallback? onFitView;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (onFitView != null) ...<Widget>[
          _ControlButton(
            icon: Icons.zoom_out_map_rounded,
            onTap: onFitView!,
          ),
          const SizedBox(height: 10),
        ],
        _ControlButton(
          icon: Icons.my_location_rounded,
          onTap: onMyLocation,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onTap});

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
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: AppColors.primaryLight,
            size: 22,
          ),
        ),
      ),
    );
  }
}
