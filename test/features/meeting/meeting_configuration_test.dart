import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/meeting/data/meeting_configuration.dart';

void main() {
  test(
    'defaults to a disabled unavailable configuration without compile-time values',
    () {
      final configuration = MeetingConfiguration.fromEnvironment();

      expect(configuration.isEnabled, isFalse);
      expect(configuration.serverUrl, isEmpty);
      expect(configuration.maxParticipants, 8);
      expect(configuration.isAvailable, isFalse);
    },
  );

  test('defaults missing environment values to safe values', () {
    final configuration = MeetingConfiguration.fromEnvironment(
      environment: const {},
    );

    expect(configuration.isEnabled, isFalse);
    expect(configuration.serverUrl, isEmpty);
    expect(configuration.maxParticipants, 8);
    expect(configuration.isAvailable, isFalse);
  });

  test('parses and trims environment values', () {
    final configuration = MeetingConfiguration.fromEnvironment(
      environment: const {
        MeetingConfiguration.featureFlagEnvironmentKey: ' TRUE ',
        MeetingConfiguration.providerUrlEnvironmentKey:
            '  wss://meeting.example.test  ',
        MeetingConfiguration.participantLimitEnvironmentKey: ' 4 ',
      },
    );

    expect(configuration.isEnabled, isTrue);
    expect(configuration.serverUrl, 'wss://meeting.example.test');
    expect(configuration.maxParticipants, 4);
    expect(configuration.isAvailable, isTrue);
  });

  test('normalizes participant limits outside the supported range', () {
    expect(
      MeetingConfiguration(
        isEnabled: true,
        serverUrl: 'wss://meeting.example.test',
        maxParticipants: 1,
      ).maxParticipants,
      8,
    );
    expect(
      MeetingConfiguration(
        isEnabled: true,
        serverUrl: 'wss://meeting.example.test',
        maxParticipants: 9,
      ).maxParticipants,
      8,
    );
    expect(
      MeetingConfiguration(
        isEnabled: true,
        serverUrl: 'wss://meeting.example.test',
        maxParticipants: 2,
      ).maxParticipants,
      2,
    );
    expect(
      MeetingConfiguration(
        isEnabled: true,
        serverUrl: 'wss://meeting.example.test',
        maxParticipants: 8,
      ).maxParticipants,
      8,
    );
  });

  test('uses the default participant limit for invalid environment values', () {
    for (final value in ['not-a-number', '1', '9']) {
      final configuration = MeetingConfiguration.fromEnvironment(
        environment: {
          MeetingConfiguration.participantLimitEnvironmentKey: ' $value ',
        },
      );

      expect(configuration.maxParticipants, 8, reason: value);
    }
  });

  test('is unavailable when the provider URL is blank', () {
    final configuration = MeetingConfiguration.fromEnvironment(
      environment: const {
        MeetingConfiguration.featureFlagEnvironmentKey: 'true',
        MeetingConfiguration.providerUrlEnvironmentKey: '   ',
      },
    );

    expect(configuration.serverUrl, isEmpty);
    expect(configuration.isAvailable, isFalse);
  });

  test('trims the provider URL passed to the constructor', () {
    final configuration = MeetingConfiguration(
      isEnabled: true,
      serverUrl: '  wss://meeting.example.test  ',
      maxParticipants: 8,
    );

    expect(configuration.serverUrl, 'wss://meeting.example.test');
  });
}
