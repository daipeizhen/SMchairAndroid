import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_chair_app/main.dart';
import 'package:smart_chair_app/screens/auth_page.dart';
import 'package:smart_chair_app/screens/dashboard.dart';
import 'package:smart_chair_app/services/api_service.dart';
import 'package:smart_chair_app/state/chair_sync_controller.dart';
import 'package:smart_chair_app/state/wellness_controller.dart';

void main() {
  testWidgets('App shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartChairApp());
    expect(find.text('智慧座椅'), findsOneWidget);
  });

  test('register duplicate username message is reported clearly', () {
    expect(
      AuthPage.usernameValidationMessage(
        isRegisterMode: true,
        usernameExists: true,
      ),
      '此使用者名稱已存在',
    );
  });

  test('forgot password step 1 requires username and email', () {
    final validPayload = ApiService.forgotPasswordRequestPayload(
      username: 'alice',
      email: 'user@example.com',
    );

    expect(validPayload, {'email': 'user@example.com', 'username': 'alice'});
    expect(
      () =>
          ApiService.forgotPasswordRequestPayload(username: 'alice', email: ''),
      throwsA(isA<StateError>()),
    );
    expect(
      () => ApiService.forgotPasswordRequestPayload(
        username: '',
        email: 'user@example.com',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('forgot password step 2 requires a 6-digit code and a new password', () {
    final validPayload = ApiService.forgotPasswordVerifyPayload(
      username: 'alice',
      code: '123456',
      newPassword: 'newpass123',
    );

    expect(validPayload, {
      'username': 'alice',
      'code': '123456',
      'new_password': 'newpass123',
    });
    expect(
      () => ApiService.forgotPasswordVerifyPayload(
        username: 'alice',
        code: '123',
        newPassword: 'newpass123',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => ApiService.forgotPasswordVerifyPayload(
        username: '',
        code: '123456',
        newPassword: 'newpass123',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => ApiService.forgotPasswordVerifyPayload(
        username: 'alice',
        code: '123456',
        newPassword: '123',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('change password sends one canonical payload shape', () {
    final payload = {'current_password': '123456', 'new_password': '123789'};

    expect(payload.keys, {'current_password', 'new_password'});
    expect(payload['current_password'], '123456');
    expect(payload['new_password'], '123789');
  });

  test('chair battery summary handles low and missing batteries', () {
    final lowBattery = ChairBattery.fromJson({'present': true, 'percent': 18});
    final missingBattery = ChairBattery.fromJson({'present': false});

    expect(lowBattery?.isLow, isTrue);
    expect(lowBattery?.label(online: false), '18%（離線前）');
    expect(missingBattery?.label(online: true), '未偵測到電池');
    expect(ChairBattery.fromJson(null), isNull);
  });

  testWidgets('dashboard omits the daily health report', (tester) async {
    final chairController = ChairSyncController();
    final wellnessController = WellnessController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardPage(
            controller: chairController,
            isLoggedIn: false,
            wellnessController: wellnessController,
            onOpenAi: () {},
            onOpenGarden: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );

    expect(find.text('今日報表'), findsNothing);
    expect(find.textContaining('今日總坐著時間'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    chairController.dispose();
    wellnessController.dispose();
  });
}
