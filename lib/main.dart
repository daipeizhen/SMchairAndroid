import 'package:flutter/material.dart';
import 'screens/home_page.dart';
import 'state/chair_sync_controller.dart';
import 'state/wellness_controller.dart';

/// 初始化 Flutter 並啟動 Smart Chair 應用程式。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartChairApp());
}

/// 應用程式根元件，負責共用控制器與全域主題。
class SmartChairApp extends StatefulWidget {
  const SmartChairApp({super.key});

  @override
  State<SmartChairApp> createState() => _SmartChairAppState();
}

class _SmartChairAppState extends State<SmartChairApp> {
  late final ChairSyncController chairSyncController;
  late final WellnessController wellnessController;
  static const _appFont = 'SmartChairKai';
  static const _fontFallback = ['SmartChairKai'];
  static const _appFontStyle = TextStyle(
    fontFamily: _appFont,
    fontFamilyFallback: _fontFallback,
  );

  @override
  void initState() {
    super.initState();
    // 整個應用程式生命週期共用這兩個控制器實例。
    chairSyncController = ChairSyncController();
    wellnessController = WellnessController();
  }

  @override
  void dispose() {
    // 應用程式根元件卸載時，釋放控制器計時器與監聽器。
    chairSyncController.dispose();
    wellnessController.dispose();
    super.dispose();
  }

  /// 套用全域 Material 主題並載入主頁外殼。
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E7490),
      brightness: Brightness.light,
    );
    final textTheme = Typography.material2018().black.apply(
      fontFamily: _appFont,
      fontFamilyFallback: _fontFallback,
    );
    final primaryTextTheme = Typography.material2018().white.apply(
      fontFamily: _appFont,
      fontFamilyFallback: _fontFallback,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '智慧座椅',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: _appFont,
        fontFamilyFallback: _fontFallback,
        textTheme: textTheme,
        primaryTextTheme: primaryTextTheme,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF2F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 22,
            fontWeight: FontWeight.w800,
            fontFamily: _appFont,
            fontFamilyFallback: _fontFallback,
          ),
          toolbarTextStyle: _appFontStyle,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFD8F3F7),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: _appFont,
              fontFamilyFallback: _fontFallback,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0F172A),
          contentTextStyle: _appFontStyle.copyWith(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: _appFontStyle,
          hintStyle: _appFontStyle.copyWith(color: const Color(0xFF64748B)),
          helperStyle: _appFontStyle,
          errorStyle: _appFontStyle.copyWith(color: Colors.red),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(textStyle: _appFontStyle),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(textStyle: _appFontStyle),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(textStyle: _appFontStyle),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(textStyle: _appFontStyle),
        ),
        tooltipTheme: const TooltipThemeData(textStyle: _appFontStyle),
      ),
      home: HomePage(
        chairSyncController: chairSyncController,
        wellnessController: wellnessController,
      ),
    );
  }
}
