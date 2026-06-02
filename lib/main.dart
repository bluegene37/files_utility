import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';

import 'screens/main_screen.dart';
import 'providers/file_process_provider.dart';
import 'providers/delete_process_provider.dart';
import 'providers/copy_files_provider.dart';
import 'providers/count_files_provider.dart';
import 'providers/history_provider.dart';
import 'services/global_db_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GlobalDbService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Files Utility',
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}

class MainAppWrapper extends StatelessWidget {
  const MainAppWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => FileProcessProvider()),
        ChangeNotifierProvider(create: (_) => DeleteProcessProvider()),
        ChangeNotifierProvider(create: (_) => CopyFilesProvider()),
        ChangeNotifierProvider(create: (_) => CountFilesProvider()),
      ],
      // We use a nested Navigator to ensure all pushed routes inherit the MultiProvider
      child: Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => const MainScreen(),
          );
        },
      ),
    );
  }
}