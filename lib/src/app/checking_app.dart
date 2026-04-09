import 'package:checking/src/core/theme/app_theme.dart';
import 'package:checking/src/features/checking/view/checking_screen.dart';
import 'package:flutter/material.dart';

class CheckingApp extends StatelessWidget {
  const CheckingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Checking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const CheckingScreen(),
    );
  }
}