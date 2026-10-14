import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/notifications.dart';
import 'data/readings_store.dart';
import 'data/trend_alerts.dart';
import 'data/user_profile.dart';
import 'device/ble_device_service.dart';
import 'device/device_service.dart';
import 'device/mock_device_service.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_settings.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final profile = await ProfileStore.load();

  // Real device over BLE by default. For the simulated device (no hardware):
  //   flutter run --dart-define=OMHS_MOCK=true
  const useMock = bool.fromEnvironment('OMHS_MOCK');
  final DeviceService device = useMock
      ? MockDeviceService()
      : BleDeviceService(await SharedPreferences.getInstance());
  // Sample history only with the simulated device, so it never mixes into
  // a real person's saved readings.
  final store =
      await ReadingsStore.load(device, profile, seedDemoData: useMock);

  final notifications = NotificationService();
  await notifications.init();
  await notifications.applyReminder(settings.reminder);
  // A reading that finishes while the app is in the background: say so if
  // it needs attention. In the foreground the screens show the alerts.
  // Subscribed after the store, so the new reading is already in it.
  device.results.listen((_) {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    final alerts =
        trendAlerts(store.items, ageAt: profile.profile.ageAt);
    if (alerts.isEmpty) return;
    notifications.showAlert(
        alerts.first.title(settings.unit), alerts.first.message(settings.unit));
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<ProfileStore>.value(value: profile),
        ChangeNotifierProvider<DeviceService>.value(value: device),
        ChangeNotifierProvider<ReadingsStore>.value(value: store),
        Provider<NotificationService>.value(value: notifications),
      ],
      child: const OmhsApp(),
    ),
  );
  // Reconnect to the last device in the background, if there is one.
  device.resume();
}

class OmhsApp extends StatelessWidget {
  const OmhsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppSettings, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'OMHS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      themeAnimationDuration: const Duration(milliseconds: 350),
      home: const WelcomeScreen(),
    );
  }
}
