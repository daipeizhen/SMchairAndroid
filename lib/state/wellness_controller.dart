import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wellness_models.dart';
import '../services/api_service.dart';

/// 管理每日介入任務、完成紀錄與健康花園進度。
class WellnessController extends ChangeNotifier {
  static const _baseTasks = <WellnessTask>[
    WellnessTask(
      id: 'neck-reset',
      title: '頸部回正呼吸',
      description: '下巴微收，肩膀放鬆，配合 3 次慢呼吸。',
      postureCode: 'forward',
      durationSeconds: 45,
      points: 10,
    ),
    WellnessTask(
      id: 'side-open',
      title: '側身開展',
      description: '身體向相反側延展，讓腰側慢慢恢復活動度。',
      postureCode: 'left',
      durationSeconds: 40,
      points: 10,
    ),
    WellnessTask(
      id: 'side-balance',
      title: '左右平衡伸展',
      description: '雙腳踩穩，軀幹回到中央，左右各停留一次。',
      postureCode: 'right',
      durationSeconds: 40,
      points: 10,
    ),
    WellnessTask(
      id: 'chest-open',
      title: '胸口開展',
      description: '雙手向後延伸，打開胸腔並維持自然呼吸。',
      postureCode: 'recline',
      durationSeconds: 45,
      points: 10,
    ),
    WellnessTask(
      id: 'stand-reset',
      title: '起身重置',
      description: '離開座位走動一下，讓久坐狀態重新開始。',
      postureCode: 'sedentary',
      durationSeconds: 60,
      points: 15,
    ),
    WellnessTask(
      id: 'posture-check',
      title: '姿勢覺察練習',
      description: '確認腳掌、骨盆、肩膀與頭部位於同一條穩定軸線。',
      postureCode: 'normal',
      durationSeconds: 30,
      points: 8,
    ),
  ];

  String _scope = 'guest';
  int points = 0;
  int streak = 0;
  String? activeTaskId;
  String? latestFeedback;
  final List<WellnessRecord> records = [];
  List<WellnessTask> _dailyTasks = const [];
  final Set<String> _aiAdviceTaskKeys = {};

  /// 最多回傳六項每日任務，並排除與 AI 建議重複的項目。
  List<WellnessTask> get tasks {
    final source = _dailyTasks.isEmpty ? _baseTasks : _dailyTasks;
    final selected = <WellnessTask>[];
    for (final task in source) {
      if (!_conflictsWithAiAdvice(task)) selected.add(task);
      if (selected.length == 6) return List.unmodifiable(selected);
    }

    for (final task in _baseTasks) {
      if (!_conflictsWithAiAdvice(task) &&
          !selected.any((item) => item.id == task.id)) {
        selected.add(task);
      }
      if (selected.length == 6) break;
    }
    return List.unmodifiable(selected);
  }

  int get level => (points ~/ 100) + 1;

  int get pointsInLevel => points % 100;

  double get growthProgress => pointsInLevel / 100;

  /// 依姿勢代碼選取任務；找不到對應項目時使用姿勢覺察任務。
  WellnessTask taskForPosture(String postureCode) {
    if (_dailyTasks.isNotEmpty && postureCode == 'ai') {
      return _dailyTasks.first;
    }
    return _baseTasks.firstWhere(
      (task) => task.postureCode == postureCode,
      orElse: () => _baseTasks.last,
    );
  }

  /// 將已儲存的任務 ID 轉換為歷史紀錄使用的顯示名稱。
  String taskTitleForRecord(String taskId) {
    for (final task in [..._dailyTasks, ..._baseTasks]) {
      if (task.id == taskId) return task.title;
    }
    return '伸展任務';
  }

  /// 排除與目前 AI 推薦伸展重複的每日任務。
  void setAiAdviceTasks(List<Map<String, dynamic>> exercises) {
    _aiAdviceTaskKeys
      ..clear()
      ..addAll(
        exercises
            .expand(
              (exercise) => [
                exercise['id']?.toString(),
                exercise['group']?.toString(),
                exercise['name']?.toString(),
                exercise['title']?.toString(),
              ],
            )
            .whereType<String>()
            .map(_taskKey)
            .where((key) => key.isNotEmpty),
      );
    notifyListeners();
  }

  /// 使用正規化後的 AI 伸展 ID 與名稱比對任務。
  bool _conflictsWithAiAdvice(WellnessTask task) {
    if (_aiAdviceTaskKeys.isEmpty) return false;
    final titleKey = _taskKey(task.title);
    final idKey = _taskKey(task.id);
    return _aiAdviceTaskKeys.contains(titleKey) ||
        _aiAdviceTaskKeys.contains(idKey);
  }

  /// 移除標點並統一英文大小寫，避免影響文字比對。
  String _taskKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

  /// 檢查今天是否已有相同任務的完成紀錄。
  bool isCompletedToday(String taskId) {
    final today = _dateKey(DateTime.now());
    return records.any(
      (record) => record.taskId == taskId && record.dateKey == today,
    );
  }

  /// 切換帳號範圍並重設狀態，再載入本機與後端資料。
  Future<void> initialize(String? userScope) async {
    final nextScope = userScope?.trim().toLowerCase();
    _scope = nextScope == null || nextScope.isEmpty ? 'guest' : nextScope;
    points = 0;
    streak = 0;
    activeTaskId = null;
    latestFeedback = null;
    records.clear();
    _dailyTasks = const [];
    _aiAdviceTaskKeys.clear();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    points = prefs.getInt(_key('points')) ?? 0;
    streak = prefs.getInt(_key('streak')) ?? 0;
    final savedTaskId = prefs.getString(_key('activeTaskId'));
    activeTaskId = savedTaskId == null || savedTaskId.isEmpty
        ? null
        : savedTaskId;
    latestFeedback = prefs.getString(_key('latestFeedback'));
    records
      ..clear()
      ..addAll(_decodeRecords(prefs.getString(_key('records'))));
    _recalculateStreak();
    notifyListeners();
    await _loadDailyTasks();
    await _loadWellnessHistory();
    final garden = await ApiService.getWellnessGarden();
    if (garden != null) _applyGarden(garden);
    await _persist();
    notifyListeners();
  }

  /// 重新取得每日任務計畫，更新後通知畫面重新建置。
  Future<void> refreshDailyTasks() async {
    await _loadDailyTasks(force: true);
    notifyListeners();
  }

  /// 合併本機與後端完成紀錄，並重新計算連續天數。
  Future<void> refreshHistory() async {
    final prefs = await SharedPreferences.getInstance();
    records
      ..clear()
      ..addAll(_decodeRecords(prefs.getString(_key('records'))));
    await _loadWellnessHistory();
    final garden = await ApiService.getWellnessGarden();
    if (garden != null) _applyGarden(garden);
    _recalculateStreak();
    await _persist();
    notifyListeners();
  }

  /// 更新後端管理的點數與連續天數，不覆蓋本機任務紀錄。
  Future<void> refreshGarden() async {
    final garden = await ApiService.getWellnessGarden();
    if (garden != null) _applyGarden(garden);
    await _persist();
    notifyListeners();
  }

  /// 套用後端回傳的統計值；欄位缺漏時保留目前本機數值。
  void _applyGarden(Map<String, dynamic> garden) {
    points = (garden['points'] as num?)?.toInt() ?? points;
    streak = (garden['streak'] as num?)?.toInt() ?? streak;
  }

  /// 優先使用今天有效的快取，否則取得後端計畫或載入預設任務。
  Future<void> _loadDailyTasks({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey(DateTime.now());
    if (!force && prefs.getString(_key('dailyTasksDate')) == today) {
      final cached = prefs.getString(_key('dailyTasks'));
      if (cached != null && cached.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached);
          if (decoded is List) {
            _dailyTasks = decoded
                .whereType<Map>()
                .map((item) => _taskFromExercise(item.cast<String, dynamic>()))
                .take(6)
                .toList();
            if (_dailyTasks.isNotEmpty) return;
          }
        } on FormatException {
          // 快取格式錯誤時，改為重新取得任務計畫。
        }
      }
    }

    final exercises = await ApiService.getStretchPlan();
    if (exercises.isEmpty) {
      _dailyTasks = _baseTasks.take(6).toList();
      return;
    }

    _dailyTasks = exercises.take(6).map(_taskFromExercise).toList();
    await prefs.setString(_key('dailyTasksDate'), today);
    await prefs.setString(_key('dailyTasks'), jsonEncode(exercises.take(6)));
  }

  /// 將後端伸展項目的資料格式轉換為應用程式的任務模型。
  WellnessTask _taskFromExercise(Map<String, dynamic> exercise) {
    final name =
        exercise['name']?.toString().trim() ??
        exercise['title']?.toString().trim();
    final title = name == null || name.isEmpty ? 'AI 伸展任務' : name;
    final description =
        exercise['description']?.toString().trim() ??
        exercise['reps']?.toString().trim() ??
        '依照 AI 建議完成伸展動作。';
    final rawDuration =
        exercise['duration_sec'] ?? exercise['duration_seconds'];
    final duration = rawDuration is num
        ? rawDuration.toInt()
        : int.tryParse(rawDuration?.toString() ?? '') ?? 45;
    final id = exercise['id']?.toString().trim();
    return WellnessTask(
      id: id == null || id.isEmpty ? 'ai-${title.hashCode}' : id,
      title: title,
      description: description,
      postureCode: 'ai',
      durationSeconds: duration.clamp(15, 300).toInt(),
      points: 10,
      exerciseId: int.tryParse(id ?? ''),
      group: exercise['group']?.toString(),
    );
  }

  /// 匯入後端完成紀錄，並略過本機已有的重複項目。
  Future<void> _loadWellnessHistory() async {
    if (!await ApiService.isLoggedIn()) return;
    final history = await ApiService.getWellnessHistory();
    for (final item in history) {
      final exerciseId = item['exercise_id']?.toString();
      final date = item['date']?.toString();
      if (exerciseId == null || date == null) continue;
      if (records.any(
        (record) => record.taskId == exerciseId && record.dateKey == date,
      )) {
        continue;
      }
      records.add(
        WellnessRecord(
          taskId: exerciseId,
          dateKey: date,
          completedAt:
              DateTime.tryParse(item['completed_at']?.toString() ?? '') ??
              DateTime.now(),
          feedback: item['feedback']?.toString() ?? '',
          points: 0,
        ),
      );
    }
    _recalculateStreak();
  }

  /// 在任務完成流程開始前，儲存使用者目前選取的任務。
  Future<void> acceptTask(WellnessTask task) async {
    activeTaskId = task.id;
    await _persist();
    notifyListeners();
  }

  /// 每項任務每天只記錄一次，並套用本機或後端回傳的獎勵。
  Future<bool> completeTask(WellnessTask task, {String feedback = '完成'}) async {
    if (isCompletedToday(task.id)) return false;
    Map<String, dynamic>? garden;
    if (task.exerciseId != null) {
      garden = await ApiService.completeWellnessTask(
        exerciseId: task.exerciseId!,
        source: 'daily',
        feedback: feedback,
      );
      if (garden == null) return false;
    }

    final today = _dateKey(DateTime.now());
    final isFirstTaskToday = !records.any((record) => record.dateKey == today);
    final earnedPoints = task.points + (isFirstTaskToday ? 5 : 0);
    records.insert(
      0,
      WellnessRecord(
        taskId: task.id,
        dateKey: today,
        completedAt: DateTime.now(),
        feedback: feedback,
        points: earnedPoints,
      ),
    );
    if (garden != null && garden.isNotEmpty) {
      _applyGarden(garden);
    } else if (task.exerciseId == null) {
      points += earnedPoints;
    }
    activeTaskId = null;
    latestFeedback = feedback;
    if (task.exerciseId == null) _recalculateStreak();
    await _persist();
    notifyListeners();
    return true;
  }

  /// 建立目前帳號專屬的偏好設定鍵值。
  String _key(String field) => 'wellness_${_scope}_$field';

  /// 解碼已儲存的紀錄；JSON 無效時回傳空清單，讓初始化繼續。
  List<WellnessRecord> _decodeRecords(String? encoded) {
    if (encoded == null || encoded.isEmpty) return [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => WellnessRecord.fromJson(item.cast<String, dynamic>()))
          .toList();
    } on FormatException {
      return [];
    }
  }

  /// 產生本機日期鍵值，用於彙整每日任務完成紀錄。
  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// 從今天往前計算連續有完成任務的日數。
  void _recalculateStreak() {
    final completedDays = records.map((record) => record.dateKey).toSet();
    var cursor = DateTime.now();
    var count = 0;
    while (completedDays.contains(_dateKey(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    streak = count;
  }

  /// 將控制器狀態儲存在目前帳號專屬的偏好設定命名空間。
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key('points'), points);
    await prefs.setInt(_key('streak'), streak);
    await prefs.setString(_key('activeTaskId'), activeTaskId ?? '');
    await prefs.setString(_key('latestFeedback'), latestFeedback ?? '');
    await prefs.setString(
      _key('records'),
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }
}
