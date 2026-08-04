import 'package:flutter/material.dart';

/// 微信风格配色。
class WeColors {
  static const Color bg = Color(0xFFEDEDED); // 页面 / 聊天背景灰
  static const Color barBg = Color(0xFFF7F7F7); // 顶栏 / 底栏
  static const Color green = Color(0xFF07C160); // 微信绿（选中、按钮）
  static const Color bubbleMine = Color(0xFF95EC69); // 自己的气泡绿
  static const Color bubbleOther = Colors.white; // 对方气泡白
  static const Color divider = Color(0xFFE5E5E5);
  static const Color subtitle = Color(0xFF9A9A9A); // 次要文字
  static const Color avatar = Color(0xFFB2B2B2); // 默认头像底色
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: WeColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: WeColors.green,
      primary: WeColors.green,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: WeColors.barBg,
      foregroundColor: Colors.black,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    fontFamily: 'PingFang SC',
  );
}
