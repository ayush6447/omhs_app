import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/readings_store.dart';
import 'device/device_service.dart';
import 'device/mock_device_service.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_settings.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();

  // Swap MockDeviceService for the BLE implementation once Board 5 is ready.
  final DeviceService device = MockDeviceService();
  final store = ReadingsStore(device, seedDemoData: true);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
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
