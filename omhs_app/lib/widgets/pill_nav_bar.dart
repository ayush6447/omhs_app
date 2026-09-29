import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PillNavItem {
  const PillNavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Floating blue pill navigation bar with a soft highlight on the active icon.
class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<PillNavItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: c.primary,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: context.isDark ? 0.25 : 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < items.length; i++)
                _NavIcon(
                  item: items[i],
                  selected: i == index,
                  onTap: () => onChanged(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PillNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Tooltip(
        message: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
            child: Icon(
              item.icon,
              size: 22,
              color: Colors.white.withValues(alpha: selected ? 1 : 0.72),
            ),
          ),
        ),
      ),
    );
  }
}
