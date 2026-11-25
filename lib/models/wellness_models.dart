/// 描述一項健康任務及其完成獎勵。
class WellnessTask {
  const WellnessTask({
    required this.id,
    required this.title,
    required this.description,
    required this.postureCode,
    required this.durationSeconds,
    required this.points,
    this.exerciseId,
    this.group,
  });

  final String id;
  final String title;
  final String description;
  final String postureCode;
  final int durationSeconds;
  final int points;
  final int? exerciseId;
  final String? group;
}

/// 記錄已完成任務的日期、使用者回饋與取得點數。
class WellnessRecord {
  const WellnessRecord({
    required this.taskId,
    required this.dateKey,
    required this.completedAt,
    required this.feedback,
    required this.points,
  });

  final String taskId;
  final String dateKey;
  final DateTime completedAt;
  final String feedback;
  final int points;

  /// 將紀錄轉成可儲存於本機偏好設定的 JSON 格式。
  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'dateKey': dateKey,
    'completedAt': completedAt.toIso8601String(),
    'feedback': feedback,
    'points': points,
  };

  /// 從已儲存的 JSON 還原紀錄，並容許欄位缺漏或資料格式錯誤。
  factory WellnessRecord.fromJson(Map<String, dynamic> json) {
    return WellnessRecord(
      taskId: json['taskId']?.toString() ?? '',
      dateKey: json['dateKey']?.toString() ?? '',
      completedAt:
          DateTime.tryParse(json['completedAt']?.toString() ?? '') ??
          DateTime.now(),
      feedback: json['feedback']?.toString() ?? '',
      points: int.tryParse(json['points']?.toString() ?? '') ?? 0,
    );
  }
}
