import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:futuragest_mobile/features/auth/domain/user_profile.dart';
import 'package:futuragest_mobile/features/attendance/domain/operario.dart';
import 'package:futuragest_mobile/features/attendance/application/attendance_providers.dart';
import 'package:futuragest_mobile/features/attendance/application/fichaje_sync_service.dart';
import 'package:futuragest_mobile/features/attendance/presentation/operario_detail_screen.dart';
import 'package:futuragest_mobile/features/auth/presentation/home_screen.dart';

// ── Test data ────────────────────────────────────────────────────────────────

const _testOperario = Operario(
  id: 'op-1',
  fullName: 'Juan Pérez',
  documento: '12345678',
  active: true,
);

const _testSupervisorProfile = UserProfile(
  id: 'sup-1',
  email: 'sup@test.com',
  role: UserRole.supervisor,
  mustChangePassword: false,
);

const _testLiderProfile = UserProfile(
  id: 'lid-1',
  email: 'lid@test.com',
  role: UserRole.liderOperativo,
  mustChangePassword: false,
);

const _testCoordProfile = UserProfile(
  id: 'coord-1',
  email: 'coord@test.com',
  role: UserRole.coordinador,
  mustChangePassword: false,
);

// ── Shared overrides ─────────────────────────────────────────────────────────

/// Overrides required for any test that renders HomeScreen. The HomeScreen
/// watches syncStatsProvider which chains into sqflite and firebase.
/// We stub all the infrastructure so the widget tree builds with pure mock data.
List<Override> _homeScreenOverrides() {
  return [
    // Stub sync stats so sqflite is never touched.
    syncStatsProvider.overrideWith(
      (ref) => const SyncStats(pending: 0, failed: 0, syncing: false),
    ),
    // Stub operario list — empty list is fine for nav tab tests.
    operarioListProvider.overrideWith(
      (ref) => Future.value(const <Operario>[]),
    ),
    // Stub recorded today — empty map.
    recordedTodayProvider.overrideWith(
      (ref) => Future.value(const <String, TodayFichaje>{}),
    ),
  ];
}

/// Builds a HomeScreen widget with the required provider overrides.
Widget _buildHomeScreen(UserProfile profile) {
  return ProviderScope(
    overrides: _homeScreenOverrides(),
    child: MaterialApp(
      home: HomeScreen(profile: profile),
    ),
  );
}

/// Builds OperarioDetailScreen with mock recordedToday data.
Widget _buildDetailScreen({required Map<String, TodayFichaje> todayData}) {
  return ProviderScope(
    overrides: [
      recordedTodayProvider.overrideWith((ref) {
        return Future.value(todayData);
      }),
    ],
    child: const MaterialApp(
      home: OperarioDetailScreen(operario: _testOperario),
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('T6.1 — Supervisor: Remove check-out', () {
    testWidgets(
      'OperarioDetailScreen no muestra "Registrar Salida" cuando no hay fichaje abierto',
      (WidgetTester tester) async {
        await tester.pumpWidget(_buildDetailScreen(todayData: const {}));
        await tester.pumpAndSettle();

        // No "Registrar Salida" button (check-out removed).
        expect(find.text('Registrar Salida'), findsNothing);

        // "Registrar Ingreso" IS present (check-in remains).
        expect(find.text('Registrar Ingreso'), findsOneWidget);
      },
    );

    testWidgets(
      'Con fichaje en curso se muestra "Solicitar Hora Extra" y NO "Registrar Salida"',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildDetailScreen(
            todayData: {
              'op-1': const (attendanceId: 'att-123', completed: false),
            },
          ),
        );

        await tester.pumpAndSettle();

        // "Solicitar Hora Extra" visible (overtime request from progress view).
        expect(find.text('Solicitar Hora Extra'), findsOneWidget);

        // "Registrar Salida" NOT present (removed per T6.1).
        expect(find.text('Registrar Salida'), findsNothing);
      },
    );
  });

  group('T6.3 — Role-based navigation', () {
    testWidgets(
      'Supervisor ve "Asistencia" y "Novedades", no "Solicitudes" ni "Llegadas Tarde"',
      (WidgetTester tester) async {
        await tester.pumpWidget(_buildHomeScreen(_testSupervisorProfile));
        // Pump several frames to let the widget tree fully build.
        // We avoid pumpAndSettle because Firebase init is forever-pending in tests.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Asistencia'), findsWidgets);
        expect(find.text('Novedades'), findsWidgets);
        expect(find.text('Solicitudes'), findsNothing);
        expect(find.text('Llegadas Tarde'), findsNothing);
      },
    );

    testWidgets(
      'Líder ve "Solicitudes" y "Llegadas Tarde", no "Asistencia"',
      (WidgetTester tester) async {
        await tester.pumpWidget(_buildHomeScreen(_testLiderProfile));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Solicitudes'), findsWidgets);
        expect(find.text('Llegadas Tarde'), findsWidgets);
        expect(find.text('Asistencia'), findsNothing);
      },
    );

    testWidgets(
      'Coordinador ve "Solicitudes" y "Llegadas Tarde"',
      (WidgetTester tester) async {
        await tester.pumpWidget(_buildHomeScreen(_testCoordProfile));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Solicitudes'), findsWidgets);
        expect(find.text('Llegadas Tarde'), findsWidgets);
      },
    );
  });
}
