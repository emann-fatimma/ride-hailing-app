import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF4338CA);
  static const primaryLight = Color(0xFFA5A6F0);
  static const background = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF9CA3AF);
  static const border = Color(0xFFD1D5DB);
  static const error = Color(0xFFE53E3E);
  static const success = Color(0xFF34A853);
}

class AppTextStyles {
  static const heading1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: AppColors.primary,
  );
  static const subtitle = TextStyle(
    fontSize: 14,
    color: AppColors.textPrimary,
  );
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 15,
    color: AppColors.textPrimary,
  );
  static const helper = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );
  static const errorText = TextStyle(
    fontSize: 12,
    color: AppColors.error,
  );
  static const link = TextStyle(
    fontSize: 14,
    color: AppColors.primary,
    fontWeight: FontWeight.w600,
  );
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}