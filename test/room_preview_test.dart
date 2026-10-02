import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';

void main() {
  test(
    'typed join codes are normalised and look-alike characters rejected',
    () {
      expect(joinRequestFor(' ab3-k7x '), {'joinCode': 'AB3K7X'});
      expect(joinRequestFor('AB3K7X'), {'joinCode': 'AB3K7X'});
      expect(joinRequestFor('O0I1L5'), isNull);
      expect(joinRequestFor('ABC'), isNull);
    },
  );
  test('the long room ID reconnects instead of joining', () {
    expect(joinRequestFor('5a535286384ff134d226bceb'), {
      'roomId': '5A535286384FF134D226BCEB',
    });
  });
}
