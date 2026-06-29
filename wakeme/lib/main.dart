import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'core/services/background_alarm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env is optional on first run; the maps key will fall back to an empty
    // string and the Google Maps watermark will surface a missing-key error.
  }
  // Configure (but don't start) the background alarm service so it's ready to
  // launch the moment the user arms. See background_alarm_service.dart.
  try {
    await BackgroundAlarmService.initialize();
  } catch (_) {}
  runApp(const WakeMeApp());
}
