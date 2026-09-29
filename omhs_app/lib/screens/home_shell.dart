import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../widgets/pill_nav_bar.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'measure_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _items = [
    PillNavItem(Icons.grid_view_rounded, 'Dashboard'),
    PillNavItem(Icons.monitor_heart_outlined, 'Measure'),
    PillNavItem(Icons.history_rounded, 'History'),
    PillNavItem(Icons.tune_rounded, 'Settings'),
  ];

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final overlay = context.isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _index,
          children: [
            DashboardScreen(
              onOpenHistory: () => _select(2),
              onMeasure: () => _select(1),
            ),
            const MeasureScreen(),
            const HistoryScreen(),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: PillNavBar(
          index: _index,
          onChanged: _select,
          items: _items,
        ),
      ),
    );
  }
}
