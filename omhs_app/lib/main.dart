import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/readings_store.dart';
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
  final DeviceService device =
      useMock ? MockDeviceService() : BleDeviceService();
  final store = ReadingsStore(device, seedDemoData: true);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<ProfileStore>.value(value: profile),
        ChangeNotifierProvider<DeviceService>.value(value: device),
        ChangeNotifierProvider<ReadingsStore>.value(value: store),
      ],
      child: const OmhsApp(),
    ),
  );
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
