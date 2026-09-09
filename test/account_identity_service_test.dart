import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/services/account_identity.dart';

void main() {
  group('AccountIdentityService', () {
    test('browser pointers are isolated by authenticated user', () {
      expect(
        localClubKeyForUser('user-a'),
        isNot(localClubKeyForUser('user-b')),
      );
      expect(
        activeClubKeyForUser('user-a'),
        isNot(activeClubKeyForUser('user-b')),
      );
    });

    test('manual club ids remain distinct even with the same club name', () {
      final first = manualClubIdForUser(
        '11111111-aaaa-bbbb-cccc-111111111111',
        'club-central',
      );
      final second = manualClubIdForUser(
        '22222222-aaaa-bbbb-cccc-222222222222',
        'club-central',
      );
      expect(first, isNot(second));
      expect(first, startsWith('externo-'));
      expect(first, endsWith('-club-central'));
    });
  });
}
