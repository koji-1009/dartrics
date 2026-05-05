import 'package:dartrics/src/config/config_loader.dart';
import 'package:test/test.dart';

void main() {
  test('ConfigException.toString includes the message', () {
    final ex = ConfigException('oops');
    expect(ex.toString(), 'ConfigException: oops');
  });
}
