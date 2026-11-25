# Smart Chair Android

Smart Chair 是以 Flutter 和 Dart 開發的智慧座椅應用程式，主要提供 Android 使用者即時坐姿監測、AI 伸展建議與健康任務追蹤。應用程式透過 REST API 與後端同步座椅、帳號及健康花園資料。

## 功能

- **健康總覽**：顯示即時姿勢、姿勢分數、風險、座椅電量、就座時間、提醒次數與健康花園進度，並呈現最近姿勢紀錄分布；不提供今日報表頁。
- **座椅管理**：登入後選擇線上座椅、入座、查看連線狀態與電量，並可手動更新或校準。
- **AI 物理治療師**：依目前姿勢取得文字建議與伸展建議，最多顯示 3 個推薦影片。
- **健康花園**：接受並完成每日任務、回報身體感受，追蹤能量、連續天數與完成紀錄。
- **通知**：查看姿勢提醒、週報與健康介入通知。
- **帳號與設定**：登入、註冊、忘記密碼、更新個人資料、上傳頭像、更換座椅及刪除帳號。登入後可從右上角齒輪開啟設定，登出按鈕位於旁邊。

## 技術

- Flutter；Dart SDK 版本需求為 `^3.11.1`。
- `http`：REST API 呼叫。
- `shared_preferences`：登入狀態、座椅選擇與健康花園資料的本機保存。
- `fl_chart`：姿勢紀錄分布圖。
- `file_picker`：選取個人頭像。
- `url_launcher`：開啟推薦伸展影片。

## 開發環境

- Flutter SDK 與符合 `pubspec.yaml` SDK 限制的 Dart SDK。
- Android SDK、Android Emulator，以及已建立的 Android Virtual Device（AVD）。
- Windows PowerShell、VS Code 或 Android Studio。

## 快速開始

請在專案根目錄執行以下指令，安裝 `pubspec.yaml` 所列的套件：

```powershell
# 在專案根目錄還原 Flutter 套件依賴。
flutter pub get
```

### 啟動 Android 模擬器與 App

專案提供 `scripts/start_android.ps1`，會檢查 Android SDK/ADB、啟動指定 AVD、等待模擬器開機，再執行 Flutter App。以下指令與根目錄的 `開啟Android指令.txt` 相同：

```powershell
# 從專案根目錄以 Bypass 執行；啟動指定 AVD、等待模擬器開機，再執行 App。
powershell -ExecutionPolicy Bypass -File scripts\start_android.ps1 -AvdName "Medium_Phone_API_36.1" -DeviceId "emulator-5554" -ApiBaseUrl "https://sandbar-badass-subfloor.ngrok-free.dev/api"
```

也可以指定 AVD、ADB 裝置 ID 與後端網址。請將範例網址替換成目前可連線的後端：

```powershell
# 自訂模擬器、裝置與 API 網址；網址可包含 /api。
powershell -ExecutionPolicy Bypass -File scripts\start_android.ps1 -AvdName "Medium_Phone_API_36.1" -DeviceId "emulator-5554" -ApiBaseUrl "https://api.example.com/api"
```

腳本的預設 API 網址目前指向開發用 ngrok 網址，可能會失效；正式或日常開發時，請傳入自己的後端網址。`-NoDds` 可在 Dart Development Service 連線異常時停用 DDS。

### 建置 Android APK

以下指令會產生 Debug APK。第二個指令示範在單次建置中覆寫 API 網址；請替換範例網域：

```powershell
# 使用 ApiService 內的預設 API 網址建置 Debug APK。
flutter build apk --debug

# 為本次建置指定後端 API 網址。
flutter build apk --debug '--dart-define=API_BASE_URL=https://api.example.com/api'
```

APK 預設輸出至 `build/app/outputs/flutter-apk/app-debug.apk`。`API_BASE_URL` 可設定為主機根網址或以 `/api` 結尾的網址；應用程式會處理 API 前綴，避免重複加入 `/api`。

## API 整合

API 網址由 `lib/services/api_service.dart` 管理，呼叫需登入的端點時會附上登入 Token。App 目前整合的主要端點如下：

- **帳號與個人資料**：`/api/users/exists`、`/api/login`、`/api/register`、`/api/me`、`/api/me/update`、`/api/me/avatar/upload`、`/api/me/delete`。
- **密碼管理**：`/api/auth/forgot-password/request`、`/api/auth/forgot-password/verify`、`/api/auth/change-password`。
- **座椅與姿勢**：`/api/chairs`、`/api/chair/status`、`/api/chair/checkin`、`/api/chair/calibration`、`/api/chair/checkout`、`/api/posture/history`。
- **AI 建議與通知**：`/api/agent/jobs`、`/api/agent/jobs/{job_id}`、`/api/agent/stretch-plan`、`/api/notification/history`。
- **健康花園**：`/api/wellness/garden`、`/api/wellness/complete`、`/api/wellness/history`。

AI 建議採非同步工作流程：`POST /api/agent/jobs` 建立工作並回傳 `job_id`，App 接著查詢 `/api/agent/jobs/{job_id}`，直到工作完成或失敗。完成回應可包含文字建議和推薦伸展；以下為 JSONC 範例，註解用來說明欄位：

```jsonc
{
  // 工作完成後的狀態；App 會依此判斷是否呈現結果。
  "status": "done",
  // 後端提供的姿勢代碼。
  "posture": "left",
  // 對應姿勢代碼的使用者顯示文字。
  "posture_display": "身體左傾",
  // AI 產生的文字建議。
  "advice": "放鬆肩膀，進行溫和的側身伸展。",
  // 推薦伸展清單；App 最多顯示 3 項。
  "recommended_exercises": [
    {
      // 伸展項目名稱；App 也支援 title 欄位。
      "name": "坐姿側身伸展",
      // 推薦影片網址；未提供時仍可顯示伸展項目。
      "youtube_url": "https://www.youtube.com/watch?v=example"
    }
  ]
}
```

## 專案結構

- `lib/main.dart`：應用程式入口與主題設定。
- `lib/screens/`：登入、健康總覽、AI 建議、健康花園、通知及設定頁面。
- `lib/services/api_service.dart`：REST API、登入狀態、座椅及使用者資料服務。
- `lib/state/chair_sync_controller.dart`：同步姿勢、座椅狀態、電量與通知。
- `lib/state/wellness_controller.dart`、`lib/models/wellness_models.dart`：健康任務、完成紀錄與花園進度。
- `test/widget_test.dart`、`test/wellness_controller_test.dart`：Widget 與健康任務邏輯測試。
- `scripts/start_android.ps1`：啟動 Android 模擬器並執行 App 的 PowerShell 腳本。
- `開啟Android指令.txt`：提供專案目前使用的 Android 啟動指令。

主要資料流程為：座椅與姿勢同步至控制器，健康總覽與 AI 頁呈現狀態；使用者接受並完成伸展任務後，健康花園保存進度，通知與設定頁則呈現各自的紀錄與帳號功能。

## 品質檢查

請在專案根目錄執行以下指令，分別檢查 Dart 靜態問題並執行測試：

```powershell
# 檢查 Dart 與 Flutter 靜態分析問題。
flutter analyze

# 執行專案中的 Widget 與控制器測試。
flutter test
```

## 相關文件

- [後端整合說明](BACKEND_INTEGRATION.md)
- [後端診斷記錄](BACKEND_DIAGNOSIS.md)
- [AI 健康介入研究設計](AI_HEALTH_INTERVENTION_RESEARCH.md)

## 授權

目前尚未指定授權條款。
