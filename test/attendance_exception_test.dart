// Tests for AttendanceException statusCode — Fix 3/4/12.
import 'package:flutter_test/flutter_test.dart';

import 'package:futuragest_mobile/features/attendance/domain/attendance_repository.dart';

void main() {
  group('AttendanceException', () {
    test('carries message with no statusCode by default', () {
      const e = AttendanceException('network failure');
      expect(e.message, 'network failure');
      expect(e.statusCode, isNull);
      expect(e.toString(), contains('null'));
    });

    test('carries statusCode when provided', () {
      const e = AttendanceException('Duplicate entry', statusCode: 409);
      expect(e.statusCode, 409);
      expect(e.message, 'Duplicate entry');
      expect(e.toString(), contains('409'));
    });

    test('422 carries real backend message', () {
      const e = AttendanceException(
        'La duración del turno es inválida.',
        statusCode: 422,
      );
      expect(e.statusCode, 422);
      expect(e.message, contains('duración'));
    });

    test('null statusCode signals TRANSIENT error', () {
      const e = AttendanceException('Connection refused');
      expect(e.statusCode, isNull);
    });
  });
}
