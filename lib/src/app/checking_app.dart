import 'dart:async';

import 'package:checking/src/core/theme/app_theme.dart';
import 'package:checking/src/features/checking/view/checking_screen.dart';
import 'package:flutter/material.dart';

const Color _presentationBlue = Color(0xFF173E75);

class CheckingApp extends StatelessWidget {
  const CheckingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Checking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const _PresentationGate(),
    );
  }
}

class _PresentationGate extends StatefulWidget {
  const _PresentationGate();

  @override
  State<_PresentationGate> createState() => _PresentationGateState();
}

class _PresentationGateState extends State<_PresentationGate> {
  Timer? _presentationTimer;
  bool _showPresentation = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _presentationTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _showPresentation = false;
        });
      });
    });
  }

  @override
  void dispose() {
    _presentationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _showPresentation
          ? const _PresentationScreen()
          : const CheckingScreen(),
    );
  }
}

class _PresentationScreen extends StatelessWidget {
  const _PresentationScreen();

  static const double _titleFontSize = 40;
  static const double _nameFontSize = _titleFontSize / 2;

  @override
  Widget build(BuildContext context) {
    final logoWidth = MediaQuery.sizeOf(context).width * 0.5;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: const Offset(0, -200),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: logoWidth,
                        child: Image.asset(
                          'assets/img/app_icon_3x.png',
                          width: logoWidth,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: logoWidth,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Checking',
                            style: TextStyle(
                              fontSize: _titleFontSize,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: _presentationBlue,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 50,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Dilnei Schmidt (CYMQ)',
                      style: TextStyle(
                        fontSize: _nameFontSize,
                        fontWeight: FontWeight.w300,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tamer Salmem (HR70)',
                      style: TextStyle(
                        fontSize: _nameFontSize,
                        fontWeight: FontWeight.w300,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
