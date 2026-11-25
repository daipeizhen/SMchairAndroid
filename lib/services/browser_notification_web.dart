// 瀏覽器專用實作；條件式匯入可避免原生平台載入此檔案。
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// 必要時向瀏覽器請求通知權限，取得授權後顯示通知。
Future<void> showBrowserNotification(String title, String body) async {
  if (html.Notification.permission == 'denied') return;
  if (html.Notification.permission != 'granted') {
    final permission = await html.Notification.requestPermission();
    if (permission != 'granted') return;
  }
  html.Notification(title, body: body);
}
