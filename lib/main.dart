import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/main_screen.dart';
import 'providers/transfer_files_provider.dart';
import 'providers/delete_files_provider.dart';
import 'providers/copy_files_provider.dart';
import 'providers/count_files_provider.dart';
import 'providers/history_provider.dart';
import 'providers/theme_provider.dart';
import 'services/global_db_service.dart';
import 'theme/app_theme.dart';
import 'services/window_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowService().init();
  await GlobalDbService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => TransferFilesProvider()),
        ChangeNotifierProvider(create: (_) => DeleteFilesProvider()),
        ChangeNotifierProvider(create: (_) => CopyFilesProvider()),
        ChangeNotifierProvider(create: (_) => CountFilesProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Files Utility',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

class MainAppWrapper extends StatelessWidget {
  const MainAppWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainScreen();
  }
}