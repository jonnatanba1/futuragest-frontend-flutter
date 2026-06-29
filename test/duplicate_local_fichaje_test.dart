// Tests for DuplicateLocalFichajeException and the enqueue guard — Fix 7.
import 'package:flutter_test/flutter_test.dart';

import 'package:futuragest_mobile/features/attendance/domain/ports/fichaje_queue_repository.dart';

void main() {
  group('DuplicateLocalFichajeException', () {
    test('carries operarioId, date, and existingLocalId', () {
      const e = DuplicateLocalFichajeException(
        operarioId: 'op-1',
        date: '2026-06-10',
        existingLocalId: 42,
      );
      expect(e.operarioId, 'op-1');
      expect(e.date, '2026-06-10');
      expect(e.existingLocalId, 42);
      expect(e.toString(), contains('op-1'));
      expect(e.toString(), contains('2026-06-10'));
      expect(e.toString(), contains('42'));
    });

    test('implements Exception', () {
      const e = DuplicateLocalFichajeException(
        operarioId: 'op-1',
        date: '2026-06-10',
        existingLocalId: 1,
      );
      expect(e, isA<Exception>());
    });
  });
}
