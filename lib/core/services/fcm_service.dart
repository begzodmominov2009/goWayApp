import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/notification_repository.dart';

// Bu funksiya top-level (klass tashqarisida) bo'lishi SHART — Firebase
// background xabarlarni shu funksiya orqali qabul qiladi, ilova
// yopiq/background holatda bo'lsa ham ishlaydi.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background holatda alohida ish qilish shart emas — tizim o'zi
  // xabarni ko'rsatadi (agar "notification" maydoni bo'lsa)
}

class FcmService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Firebase'ni ishga tushiradi, ruxsat so'raydi, tokenni oladi va
  /// backend'ga yuboradi. Ilova ochilganda (splash'dan oldin yoki
  /// keyin) bir marta chaqiriladi.
  static Future<void> init(WidgetRef ref) async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // Ruxsat so'rash (Android 13+ va iOS uchun majburiy)
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Local notifications sozlash — ilova ochiq (foreground) holatda
      // push kelganda ham xabar ko'rsatish uchun kerak
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      const channel = AndroidNotificationChannel(
        'goway_channel',
        'GoWay bildirishnomalar',
        description: 'Buyurtma, hamyon va boshqa muhim xabarlar',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Foreground holatda push kelganda — qo'lda ko'rsatamiz (aks
      // holda ilova ochiq turganda hech narsa ko'rinmaydi)
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'goway_channel',
                'GoWay bildirishnomalar',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
          );
        }
      });

      // Tokenni olib, backend'ga yuborish
      final token = await messaging.getToken();
      if (token != null) {
        await ref.read(notificationRepositoryProvider).saveFcmToken(token);
      }

      // Token yangilansa (kamdan-kam holat), qayta yuborish
      messaging.onTokenRefresh.listen((newToken) {
        ref.read(notificationRepositoryProvider).saveFcmToken(newToken);
      });
    } catch (e) {
      debugPrint('⚠️ FCM sozlashda xatolik: $e');
    }
  }
}