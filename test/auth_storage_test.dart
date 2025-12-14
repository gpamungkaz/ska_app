import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ska_app/services/auth_storage.dart';

void main() {
  group('AuthStorage Session Persistence Tests', () {
    setUp(() async {
      // Clear any existing data before each test
      SharedPreferences.setMockInitialValues({});
    });

    test('Should save session correctly', () async {
      // Arrange
      const testToken = 'test_token_12345';
      const testRole = 'sprinter';
      const testName = 'John Doe';

      // Act
      await AuthStorage.saveSession(
        token: testToken,
        role: testRole,
        name: testName,
      );

      // Assert
      final session = await AuthStorage.readSession();
      expect(session, isNotNull);
      expect(session!.token, equals(testToken));
      expect(session.role, equals(testRole));
      expect(session.name, equals(testName));
    });

    test('Should save session for sprinter role', () async {
      // Arrange
      const testToken = 'sprinter_token_xyz';
      const testRole = 'sprinter';
      const testName = 'Sprinter User';

      // Act
      await AuthStorage.saveSession(
        token: testToken,
        role: testRole,
        name: testName,
      );

      // Assert
      final session = await AuthStorage.readSession();
      expect(session, isNotNull);
      expect(session!.role, equals('sprinter'));
      expect(session.name, equals('Sprinter User'));
    });

    test('Should persist session after multiple reads', () async {
      // Arrange
      const testToken = 'persistent_token';
      const testRole = 'sprinter';
      const testName = 'Persistent User';

      // Act
      await AuthStorage.saveSession(
        token: testToken,
        role: testRole,
        name: testName,
      );

      // Read multiple times
      final session1 = await AuthStorage.readSession();
      final session2 = await AuthStorage.readSession();
      final session3 = await AuthStorage.readSession();

      // Assert - All reads should return the same data
      expect(session1, isNotNull);
      expect(session2, isNotNull);
      expect(session3, isNotNull);
      expect(session1!.token, equals(testToken));
      expect(session2!.token, equals(testToken));
      expect(session3!.token, equals(testToken));
    });

    test('Should return null when no session exists', () async {
      // Act
      final session = await AuthStorage.readSession();

      // Assert
      expect(session, isNull);
    });

    test('Should clear session correctly', () async {
      // Arrange
      await AuthStorage.saveSession(
        token: 'test_token',
        role: 'sprinter',
        name: 'Test User',
      );

      // Verify session exists
      var session = await AuthStorage.readSession();
      expect(session, isNotNull);

      // Act - Clear session
      await AuthStorage.clearSession();

      // Assert - Session should be null
      session = await AuthStorage.readSession();
      expect(session, isNull);
    });

    test('Should handle session with null name', () async {
      // Arrange & Act
      await AuthStorage.saveSession(
        token: 'test_token',
        role: 'sprinter',
        name: null,
      );

      // Assert
      final session = await AuthStorage.readSession();
      expect(session, isNotNull);
      expect(session!.token, equals('test_token'));
      expect(session.role, equals('sprinter'));
      expect(session.name, isNull);
    });

    test('Should handle session with empty name', () async {
      // Arrange & Act
      await AuthStorage.saveSession(
        token: 'test_token',
        role: 'sprinter',
        name: '',
      );

      // Assert
      final session = await AuthStorage.readSession();
      expect(session, isNotNull);
      expect(session!.name, isNull); // Empty string should be treated as null
    });

    test('Should return null for invalid session (missing token)', () async {
      // Arrange - Save only role, no token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ska_auth_role', 'sprinter');

      // Act
      final session = await AuthStorage.readSession();

      // Assert
      expect(session, isNull);
    });

    test('Should return null for invalid session (missing role)', () async {
      // Arrange - Save only token, no role
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ska_auth_token', 'test_token');

      // Act
      final session = await AuthStorage.readSession();

      // Assert
      expect(session, isNull);
    });

    test('Should overwrite existing session', () async {
      // Arrange - Save first session
      await AuthStorage.saveSession(
        token: 'old_token',
        role: 'marketing',
        name: 'Old User',
      );

      // Act - Save new session
      await AuthStorage.saveSession(
        token: 'new_token',
        role: 'sprinter',
        name: 'New User',
      );

      // Assert - Should have new session data
      final session = await AuthStorage.readSession();
      expect(session, isNotNull);
      expect(session!.token, equals('new_token'));
      expect(session.role, equals('sprinter'));
      expect(session.name, equals('New User'));
    });

    test('Should trim whitespace from name', () async {
      // Arrange & Act
      await AuthStorage.saveSession(
        token: 'test_token',
        role: 'sprinter',
        name: '  Trimmed User  ',
      );

      // Assert
      final session = await AuthStorage.readSession();
      expect(session, isNotNull);
      expect(session!.name, equals('Trimmed User'));
    });
  });
}
