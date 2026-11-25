import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/browser_notification_stub.dart'
    if (dart.library.html) '../services/browser_notification_web.dart';

/// 保存座椅即時狀態，並與後端同步姿勢及通知資料。
class ChairSyncController extends ChangeNotifier {
  ChairSyncController() : sessionOpenedAt = null;

  String postureLabel = '';
  String postureCode = '';
  int postureScore = 0;
  bool isGoodPosture = false;
  String latestAdvice = '等待後端資料同步';
  DateTime? sessionOpenedAt;
  DateTime updatedAt = DateTime.now();
  DateTime lastBackendSyncAt = DateTime.now();
  bool _lastPostureWasSedentary = false;
  final Set<String> _knownNotificationIds = {};
  bool _notificationHistoryLoaded = false;

  Timer? _syncTimer;
  ChairBattery? chairBattery;
  bool chairOnline = false;

  final List<Map<String, dynamic>> notifications = [];
  final List<Map<String, dynamic>> postureHistory = [];

  /// 更新目前姿勢、記錄歷史，並在需要調整時建立提醒。
  void updatePosture({
    required String code,
    required String label,
    required int score,
    required String advice,
    required bool isGood,
  }) {
    postureCode = code;
    postureLabel = label;
    postureScore = score;
    isGoodPosture = isGood;
    latestAdvice = _cleanAdviceText(advice);
    updatedAt = DateTime.now();

    addPostureHistory(label: label, score: score, isGood: isGood);
    if (!isGood) addPostureNotification(label);

    notifyListeners();
  }

  /// 新增本機姿勢紀錄，並將保留筆數限制為 100 筆。
  void addPostureHistory({
    required String label,
    required int score,
    required bool isGood,
  }) {
    postureHistory.add({
      'label': label,
      'score': score,
      'isGood': isGood,
      'time': DateTime.now(),
    });
    if (postureHistory.length > 100) postureHistory.removeAt(0);
  }

  /// 為需要調整的姿勢建立本機提醒。
  void addPostureNotification(String posture) {
    final now = TimeOfDay.now();
    final timeText =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    notifications.insert(0, {
      'title': posture,
      'time': timeText,
      'message': '坐姿提醒：請調整坐姿。',
      'icon': Icons.warning_amber_rounded,
      'color': ApiService.postureColor(posture),
    });

    if (notifications.length > 20) notifications.removeLast();
  }

  /// 清除目前顯示的提醒，並通知監聽中的畫面。
  void clearNotifications() {
    notifications.clear();
    notifyListeners();
  }

  /// 清除目前控制器記憶體中的姿勢紀錄。
  void clearPostureHistory() {
    postureHistory.clear();
    notifyListeners();
  }

  /// 登出時清除帳號相關姿勢、座椅與通知狀態。
  void clearUserData() {
    postureLabel = '';
    postureCode = '';
    postureScore = 0;
    isGoodPosture = false;
    latestAdvice = '等待後端資料同步';
    sessionOpenedAt = null;
    _lastPostureWasSedentary = false;
    chairBattery = null;
    chairOnline = false;
    notifications.clear();
    postureHistory.clear();
    _knownNotificationIds.clear();
    _notificationHistoryLoaded = false;
    notifyListeners();
  }

  /// 尚未開始計時時，建立新的入座使用時段。
  void startSession() {
    sessionOpenedAt ??= DateTime.now();
    notifyListeners();
  }

  /// 結束目前使用時段並清除暫存的座椅連線狀態。
  void stopSession() {
    sessionOpenedAt = null;
    _lastPostureWasSedentary = false;
    chairBattery = null;
    chairOnline = false;
    notifyListeners();
  }

  /// 銷毀控制器前取消定期同步計時器。
  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  /// 啟動定期同步，並立即向後端取得最新狀態。
  void startAutoSync({Duration interval = const Duration(seconds: 5)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) async {
      await _pullFromServer();
    });
    _pullFromServer();
  }

  /// 單次同步後端資料，不變更定期同步計時器。
  Future<void> refreshFromServer() async {
    await _pullFromServer();
  }

  /// 停止定期 API 輪詢，但保留目前畫面上的狀態。
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// 取得姿勢、座椅與通知資料，成功後通知監聽者更新畫面。
  Future<void> _pullFromServer() async {
    try {
      // 取得最新姿勢歷史與通知歷史。
      final history = await ApiService.getPostureHistory(limit: 100);
      final notificationHistory = await ApiService.getNotificationHistory(
        limit: 50,
      );
      final chairStatus = await ApiService.getChairStatus();
      if (chairStatus != null) {
        chairOnline = chairStatus['online'] == true;
        chairBattery = ChairBattery.fromJson(chairStatus['battery']);
      }

      // 將後端姿勢資料轉換成控制器使用的格式。
      if (history.isNotEmpty) {
        postureHistory.clear();
        _applyPosturePayload(history.first);
      } else {
        if (chairStatus != null) {
          _applyPosturePayload(chairStatus);
        }
      }
      for (final item in history) {
        final label =
            item['posture'] as String? ?? item['label'] as String? ?? '未知';
        final score = ApiService.toScore(label);
        final isGood = label == 'normal' || label == '姿勢正常';
        final parsedTime = DateTime.tryParse(
          item['timestamp']?.toString() ?? '',
        )?.toLocal();
        postureHistory.add({
          'code': label,
          'label':
              item['posture_display']?.toString() ??
              ApiService.toDisplayName(label),
          'score': score,
          'isGood': isGood,
          'time': parsedTime ?? DateTime.now(),
        });
      }

      lastBackendSyncAt = DateTime.now();

      // 依後端歷史清單更新通知。
      notifications.clear();
      for (final n in notificationHistory) {
        final notificationId = n['id']?.toString();
        final isNewAutoCheckout =
            _notificationHistoryLoaded &&
            n['kind']?.toString() == 'auto_checkout' &&
            notificationId != null &&
            !_knownNotificationIds.contains(notificationId);
        final displayPosture = _notificationPostureLabel(n);
        final kind = n['kind']?.toString() ?? 'posture';
        final isWeekly = kind == 'weekly';
        final title = isWeekly ? '週報' : displayPosture;
        final message = _notificationMessage(n, displayPosture);
        final time = _notificationTime(n);
        final color = isWeekly
            ? const Color(0xFF2563EB)
            : ApiService.postureColor(displayPosture);
        notifications.add({
          'id': notificationId,
          'title': title,
          'time': time.isNotEmpty ? time : _formatNow(),
          'message': message,
          'kind': kind,
          'icon': Icons.notifications_active_rounded,
          'color': color,
        });
        if (notificationId != null) {
          _knownNotificationIds.add(notificationId);
        }
        if (isNewAutoCheckout) {
          unawaited(
            showBrowserNotification(
              '智慧座椅自动离座',
              n['message']?.toString() ?? '请回到 App 重新入座。',
            ),
          );
        }
      }
      _notificationHistoryLoaded = true;

      notifyListeners();
    } catch (_) {
      // 網路要求失敗時保留目前狀態。
    }
  }

  /// 後端未提供時間戳記時，使用本機時間產生通知時間文字。
  String _formatNow() {
    final now = TimeOfDay.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  /// 將後端不同格式的姿勢欄位轉為控制器狀態並更新計時資訊。
  void _applyPosturePayload(Map<String, dynamic> payload) {
    final source = _postureSource(payload);
    final code = _postureCodeFrom(source);
    final backendDisplay = source['posture_display']?.toString().trim();
    final displayName = backendDisplay?.isNotEmpty == true
        ? backendDisplay!
        : code.isEmpty
        ? '等待同步'
        : ApiService.toDisplayName(code);
    final score = ApiService.toScore(code);
    final isSedentary =
        code == 'sedentary' ||
        displayName.contains('久坐') ||
        displayName.contains('sedentary');
    final shouldResetTimer =
        _lastPostureWasSedentary && !isSedentary && code.isNotEmpty;

    postureCode = code;
    postureLabel = displayName;
    postureScore = score;
    isGoodPosture = code == 'normal' || displayName == '姿勢正常';
    latestAdvice = _cleanAdviceText(
      source['physio_advice']?.toString() ??
          source['advice']?.toString() ??
          (isGoodPosture ? '目前姿勢良好，請繼續維持。' : '請依照後端建議調整姿勢。'),
    );

    if (displayName == '無人就坐') {
      sessionOpenedAt = null;
      _lastPostureWasSedentary = false;
    } else if (code.isNotEmpty) {
      if (sessionOpenedAt == null || shouldResetTimer) {
        sessionOpenedAt = DateTime.now();
      }
    }

    _lastPostureWasSedentary = isSedentary;
  }

  /// 移除 Markdown 粗體標記，讓後端建議以純文字顯示。
  String _cleanAdviceText(String text) {
    return text.replaceAll('**', '').trim();
  }

  /// 後端將姿勢資料包在已知欄位中時，取出內層資料。
  Map<String, dynamic> _postureSource(Map<String, dynamic> payload) {
    for (final key in ['latest', 'current', 'posture_data', 'data']) {
      final value = payload[key];
      if (value is Map) {
        return value.cast<String, dynamic>();
      }
    }
    return payload;
  }

  /// 讀取後端支援的姿勢欄位別名與座椅使用狀態。
  String _postureCodeFrom(Map<String, dynamic> payload) {
    final occupied =
        payload['occupied'] ?? payload['is_occupied'] ?? payload['active'];
    if (occupied == false) {
      return 'empty';
    }

    for (final key in [
      'posture',
      'posture_code',
      'current_posture',
      'status',
      'state',
      'label',
    ]) {
      final value = payload[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return _normalizePostureCode(value);
      }
    }

    return occupied == true ? '' : 'empty';
  }

  /// 將常見的入座狀態文字轉換為應用程式使用的標準姿勢代碼。
  String _normalizePostureCode(String value) {
    switch (value.toLowerCase()) {
      case 'occupied':
      case 'seated':
      case 'sitting':
        return 'normal';
      case 'unoccupied':
      case 'empty':
      case 'none':
      case 'no_data':
        return 'empty';
      default:
        return value;
    }
  }

  /// 從結構化或舊版通知資料中擷取可讀的姿勢名稱。
  String _notificationPostureLabel(Map<String, dynamic> item) {
    for (final key in ['posture', 'posture_code', 'posture_display', 'label']) {
      final raw = item[key]?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        final displayName = ApiService.toDisplayName(raw);
        if (displayName != '姿勢正常' &&
            displayName != 'normal' &&
            displayName != 'notification' &&
            displayName != 'alert') {
          return displayName;
        }
      }
    }

    final message =
        item['message']?.toString().trim() ??
        item['content']?.toString().trim() ??
        item['description']?.toString().trim() ??
        '';
    final parsed = RegExp(
      r'坐姿(?:提醒|通知)\s*[:：]\s*([^，。,.]+)',
    ).firstMatch(message);
    if (parsed != null) {
      return parsed.group(1)?.trim() ?? '姿勢提醒';
    }

    final quoted = RegExp(r'目前姿勢為[「"]([^」"]+)[」"]').firstMatch(message);
    if (quoted != null) {
      return quoted.group(1)?.trim() ?? '姿勢提醒';
    }

    return '姿勢提醒';
  }

  /// 整理後端通知文字；沒有訊息時提供預設內容。
  String _notificationMessage(Map<String, dynamic> item, String postureLabel) {
    final message =
        item['message']?.toString().trim() ??
        item['content']?.toString().trim() ??
        item['description']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      final cleaned = message
          .replaceAll('通知', '提醒')
          .replaceAll(RegExp(r'^坐姿提醒\s*[:：]\s*'), '');
      return '坐姿提醒：$cleaned';
    }

    return '坐姿提醒：$postureLabel，請調整坐姿。';
  }

  /// 今天的時間只顯示時分，其他日期則同時顯示日期與時間。
  String _notificationTime(Map<String, dynamic> item) {
    final raw = item['timestamp']?.toString() ?? item['time']?.toString() ?? '';
    if (raw.isEmpty) return '';

    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;

    final now = DateTime.now();
    if (parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day) {
      return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    }

    return '${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }
}
