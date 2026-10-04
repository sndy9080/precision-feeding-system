import 'package:flutter_test/flutter_test.dart';
import 'package:pakan_ternak_iot/device_scope.dart';

void main() {
  test('DeviceScope keeps selected device ID', () {
    const scope = DeviceScope('ESP32_A1B2C3D4E5F6');
    expect(scope.id, 'ESP32_A1B2C3D4E5F6');
  });
}
