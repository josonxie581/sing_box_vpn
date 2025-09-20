import 'package:flutter/material.dart';

class AppTheme {
  // 主色调 - 赛博朋克霓虹色
  static const Color primaryNeon = Color(0xFF00D4FF); // 霓虹蓝
  static const Color accentNeon = Color(0xFFFF00FF); // 霓虹紫
  static const Color successGreen = Color(0xFF00FF88); // 霓虹绿
  static const Color warningOrange = Color(0xFFFF9500); // 警告橙
  static const Color errorRed = Color(0xFFFF0055); // 错误红

  // 背景色 - 深色调
  static const Color bgDark = Color(0xFF0A0E1A); // 深背景
  static const Color bgCard = Color.fromARGB(255, 32, 38, 57); // 卡片背景
  static const Color bgSurface = Color(0xFF1C2333); // 表面背景
  static const Color bgElevated = Color(0xFF252B3D); // 提升背景

  // 边框和分割线
  static const Color borderColor = Color(0xFF2A3245);
  static const Color dividerColor = Color(0xFF1F2937);

  // 文字颜色
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB8BCC8);
  static const Color textHint = Color(0xFF6B7280);

  // 获取暗色主题
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // 颜色方案
      colorScheme: const ColorScheme.dark(
        primary: primaryNeon,
        secondary: accentNeon,
        surface: bgCard,
        error: errorRed,
        onPrimary: bgDark,
        onSecondary: bgDark,
        onSurface: textPrimary,
        onError: textPrimary,
      ),

      // 脚手架背景
      scaffoldBackgroundColor: bgDark,

      // 卡片主题
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor.withOpacity(0.3), width: 1),
        ),
        shadowColor: primaryNeon.withOpacity(0.2),
      ),

      // 应用栏主题
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
      ),

      // 输入装饰主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryNeon, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorRed),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textHint.withOpacity(0.7)),
      ),

      // 提升按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryNeon,
          foregroundColor: bgDark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // 填充按钮主题
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryNeon,
          foregroundColor: bgDark,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // 文本按钮主题
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryNeon,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // 图标按钮主题
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          highlightColor: primaryNeon.withOpacity(0.1),
        ),
      ),

      // 对话框主题
      dialogTheme: DialogThemeData(
        backgroundColor: bgCard,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // 列表瓦片主题
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: primaryNeon.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // 分割线主题
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),

      // 开关主题
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryNeon;
          }
          return textHint;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryNeon.withOpacity(0.3);
          }
          return borderColor;
        }),
      ),

      // 复选框主题
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryNeon;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(bgDark),
        side: const BorderSide(color: borderColor, width: 2),
      ),

      // 标签栏主题
      tabBarTheme: TabBarThemeData(
        labelColor: primaryNeon,
        unselectedLabelColor: textSecondary,
        indicatorColor: primaryNeon,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: dividerColor,
        overlayColor: WidgetStateProperty.all(primaryNeon.withOpacity(0.1)),
      ),

      // 字体主题
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
        bodySmall: TextStyle(fontSize: 12, color: textHint),
      ),
    );
  }

  // 渐变背景装饰
  static BoxDecoration gradientBackground() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bgDark, bgDark.withBlue(20)],
      ),
    );
  }

  // 霓虹光晕装饰
  static BoxDecoration neonGlow({
    Color color = primaryNeon,
    double radius = 16,
    double spread = 4,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.4),
          blurRadius: spread * 2,
          spreadRadius: spread / 2,
        ),
        BoxShadow(
          color: color.withOpacity(0.2),
          blurRadius: spread * 4,
          spreadRadius: spread,
        ),
      ],
    );
  }
}
