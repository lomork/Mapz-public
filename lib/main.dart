import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';
import 'models/discovered_road.dart';
import 'services/road_discovery_service.dart';
import 'services/leaderboard_service.dart';

import 'api/google_maps_api_service.dart';
import 'firebase_options.dart';
import 'screens/auth/auth_gate.dart';
import 'services/notification_service.dart';
import 'providers/map_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/onboarding/animated_splash_screen.dart';


// --- App Global State ---
enum AppTheme { automatic, light, dark }
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.requestPermissions();
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [DiscoveredRoadSchema], // Tell Isar about our road model
    directory: dir.path,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<GoogleMapsApiService>(
          create: (_) => GoogleMapsApiService(),
        ),
        Provider<RoadDiscoveryService>(
          create: (context) => RoadDiscoveryService(isar, context.read<GoogleMapsApiService>()),
        ),
        Provider<LeaderboardService>(
          create: (_) => LeaderboardService(),
        ),
        ChangeNotifierProvider<MapProvider>(
          create: (context) => MapProvider(
            context.read<GoogleMapsApiService>(),
          ),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'Mapz',
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          debugShowCheckedModeBanner: false,
          home: const AnimatedSplashScreen(),
        );
      },
    );
  }
}