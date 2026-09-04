import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/state/calendar_time.dart';

void main() {
  group('formatHm', () {
    test('zero-pads hour and minute', () {
      expect(formatHm(9, 5), '09:05');
      expect(formatHm(19, 30), '19:30');
      expect(formatHm(0, 0), '00:00');
    });
  });

  group('parseHm', () {
    test('parses HH:mm and H:mm', () {
      expect(parseHm('19:30'), (hour: 19, minute: 30));
      expect(parseHm('9:05'), (hour: 9, minute: 5));
    });

    test('parses common free-text variants', () {
      expect(parseHm(' 19.30 '), (hour: 19, minute: 30));
      expect(parseHm('1930'), (hour: 19, minute: 30));
    });

    test('rejects empty, out-of-range and garbage input', () {
      expect(parseHm(''), isNull);
      expect(parseHm('   '), isNull);
      expect(parseHm('25:00'), isNull);
      expect(parseHm('19:75'), isNull);
      expect(parseHm('mañana temprano'), isNull);
    });
  });
}
