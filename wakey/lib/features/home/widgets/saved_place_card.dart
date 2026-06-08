import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/models/destination_model.dart';

// Horizontal pill for a saved favorite. Layout:
//   ┌──────────────────────────────┐
//   │ [icon]  Name                 │
//   │         optional address     │
//   └──[del]───────────────[edit]──┘
//
// Interactions:
//   • tap        → navigate to that place
//   • long-press → quickly re-point to current location (the original
//                  hold-while-you're-there shortcut)
//   • edit pen   → open the full map editor (works from anywhere)
//   • delete x   → only shown for user-added places (removable=true)
class SavedPlaceCard extends StatelessWidget {
  const SavedPlaceCard({
    super.key,
    required this.destination,
    required this.onTap,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
  });

  final DestinationModel destination;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      height: 78,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      // ClipRRect rounds the Stack so the Material splash from the
      // GestureDetector layer doesn't escape the rounded corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                // Right padding leaves room for the edit badge; left padding
                // leaves room for the optional delete badge below the text.
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        DestinationModel.iconFor(destination.iconName),
                        color: AppColors.primaryLight,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            destination.name,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            destination.address,
                            style:
                                AppTextStyles.bodyMuted.copyWith(fontSize: 10),
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
            if (onDelete != null)
              Positioned(
                left: 4,
                bottom: 4,
                child: _CornerBadge(
                  icon: Icons.close_rounded,
                  color: AppColors.danger,
                  onTap: onDelete!,
                ),
              ),
            if (onEdit != null)
              Positioned(
                right: 4,
                bottom: 4,
                child: _CornerBadge(
                  icon: Icons.edit_rounded,
                  color: AppColors.primary,
                  onTap: onEdit!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 20,
          height: 20,
          child: Icon(icon, color: AppColors.textPrimary, size: 12),
        ),
      ),
    );
  }
}

// "+" tile rendered at the end of the saved-places row to add a new favorite.
// Same height as SavedPlaceCard so the row stays visually aligned.
class AddSavedPlaceCard extends StatelessWidget {
  const AddSavedPlaceCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 108,
        height: 78,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryLight.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppColors.primaryLight,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Add',
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
