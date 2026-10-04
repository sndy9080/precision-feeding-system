import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  static Future<void> kirimNotifStokKritis(String deviceName, int persen) async {
    await init();
    const detail = AndroidNotificationDetails(
      'stok_kritis',
      'Stok Pakan Kritis',
      channelDescription: 'Notifikasi saat stok pakan mendekati habis',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(
      id: 0,
      title: 'Stok Pakan Kritis!',
      body: '$deviceName — stok tinggal $persen%. Segera isi ulang.',
      notificationDetails: const NotificationDetails(android: detail),
    );
  }
}
