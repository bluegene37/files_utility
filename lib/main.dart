import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'providers/file_process_provider.dart';
import 'providers/delete_process_provider.dart';
import 'providers/copy_files_provider.dart';
import 'providers/count_files_provider.dart';
import 'providers/history_provider.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Files Utility',
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
