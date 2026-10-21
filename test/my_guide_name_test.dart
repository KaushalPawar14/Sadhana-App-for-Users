import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/GuideNameCache.dart';
import 'package:shared_preferences/shared_preferences.dart';

// "My Guide" appears as fast as Date of Birth and Commitments: the server stamps the guide's display name on the student's
// own user document (`guideName`), the profile reads it from the user stream it already listens to, and a copy is kept on
// the phone. No separate call is waited on (the `getMyGuide` callable only backs up a document not stamped yet).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the stamped name', () {
    test('a string is the name (trimmed); an empty one means no guide assigned; absent means not stamped yet', () {
      expect(stampedGuideName({'guideName': 'Amit Das'}), 'Amit Das');
      expect(stampedGuideName({'guideName': '  Amit Das '}), 'Amit Das');
      expect(stampedGuideName({'guideName': ''}), '', reason: 'stamped, but nobody assigned');
      expect(stampedGuideName({'name': 'Arjun'}), isNull, reason: 'not stamped yet: fall back to the callable');
      expect(stampedGuideName({'guideName': 5}), isNull);
      expect(stampedGuideName(null), isNull);
    });
  });

  group('the local copy', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('remembers the name per student and gives it back; nothing cached is null', () async {
      expect(await GuideNameCache.read('u1'), isNull);
      await GuideNameCache.write('u1', 'Amit Das');
      await GuideNameCache.write('u2', 'Radha Devi');
      expect(await GuideNameCache.read('u1'), 'Amit Das');
      expect(await GuideNameCache.read('u2'), 'Radha Devi');
      await GuideNameCache.write('u1', 'Amit Kumar Das');
      expect(await GuideNameCache.read('u1'), 'Amit Kumar Das', reason: 'a rename replaces it');
    });

    test('an empty cached name is no name', () async {
      SharedPreferences.setMockInitialValues({'my-guide-name-u1': '  '});
      expect(await GuideNameCache.read('u1'), isNull);
    });
  });

  test('Profile wiring: the name comes from the user stream first (then the cache), the callable is only the fallback', () {
    final src = File('lib/pages/Profile.dart').readAsStringSync();
    expect(src, contains('stampedGuideName(data)'), reason: 'read from the user stream already open');
    expect(src, contains('_readGuideName(data);'));
    expect(src, contains('GuideNameCache.read(uid)'), reason: 'the local copy shows before anything arrives');
    expect(src, contains('GuideNameCache.write(uid, stamped)'));
    final stampedAt = src.indexOf('final stamped = stampedGuideName(data);');
    final fallbackAt = src.indexOf('_refreshGuideName(guideId);', stampedAt);
    expect(stampedAt > 0 && fallbackAt > stampedAt, isTrue, reason: 'the callable is reached only when the document carries no name');
    final stampedBranch = src.substring(stampedAt, fallbackAt);
    expect(stampedBranch, contains('return;'), reason: 'a stamped name never triggers the callable');
  });
}
