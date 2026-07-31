import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/appearance_settings.dart';

/// Wraps any card content with a swipe-to-reveal action (e.g. delete,
/// archive) — only active when "Swipe Actions" is on in Customize App
/// Look. When off, it's a transparent passthrough with zero overhead.
class SwipeableCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSwipeAction;
  final IconData actionIcon;
  final Color actionColor;
  final Object dismissKey;

  const SwipeableCard({
    super.key,
    required this.child,
    required this.dismissKey,
    this.onSwipeAction,
    this.actionIcon = Icons.delete_outline,
    this.actionColor = Colors.redAccent,
  });

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();
    if (!appearance.swipeActionsEnabled || onSwipeAction == null) return child;

    return Dismissible(
      key: ValueKey(dismissKey),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onSwipeAction!();
        return false; // the action runs; the item stays unless the caller removes it itself
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: actionColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(appearance.cornerRadius)),
        child: Icon(actionIcon, color: actionColor),
      ),
      child: child,
    );
  }
}
