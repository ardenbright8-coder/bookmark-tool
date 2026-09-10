// ---
// 这是啥: 本地通知封装——Android 13+ 运行时权限请求 + 弹通知
// 谁看: main（初始化）、账本/输入页（收到电脑推送时弹）
// 什么时候用: 收到下行消息（回执以外的推送）时弹通知
// 改之前必看: 第一版无前台服务，通知只在 APP 进程活着时收到；权限被拒就静默跳过
// ---
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionGranted = true;

  bool get ready => _ready;

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings: initSettings);
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    _permissionGranted = granted ?? true;
    _ready = true;
  }

  Future<void> show(String title, String body) async {
    if (!_ready || !_permissionGranted) return;
    const details = AndroidNotificationDetails(
      'inbox', '收发箱通知',
      channelDescription: '电脑端回报与看板动态',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 0x7fffffff,
      title: title, body: body,
      notificationDetails: const NotificationDetails(android: details),
    );
  }
}
