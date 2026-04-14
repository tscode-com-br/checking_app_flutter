import 'package:checking/src/app/checking_app.dart';
import 'package:checking/src/features/checking/services/checking_background_service.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CheckingBackgroundLocationService.initialize();
  runApp(const CheckingApp());
}
