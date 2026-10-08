import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/services/live_search.dart';

FirebaseFunctionsException limited(String code, Map<String, Object?> details) =>
    FirebaseFunctionsException(code: code, message: 'raw', details: details);

void main() {
  test('the allowance reads the server answer; guests have none', () {
    final allowance =
        LiveSearchAllowance.fromCallable({
          'eligible': true,
          'weeklyCap': 20,
          'used': 3,
          'remaining': 17,
          'resetsAt': '2026-10-12T00:00:00.000Z',
          'paused': false,
        })!;
    expect(
      (allowance.weeklyCap, allowance.used, allowance.remaining),
      (20, 3, 17),
    );
    expect(allowance.resetsAt, DateTime.utc(2026, 10, 12));
    expect(allowance.paused, isFalse);
    expect(LiveSearchAllowance.fromCallable({'eligible': false}), isNull);
  });

  test('reset times read in the local zone', () {
    expect(resetTimeText(DateTime(2026, 10, 11, 19)), 'Sunday at 7 PM');
    expect(resetTimeText(DateTime(2026, 10, 12, 0, 30)), 'Monday at 12:30 AM');
    expect(resetTimeText(DateTime(2026, 10, 12, 12)), 'Monday at 12 PM');
  });

  test('live-search limits get their own messages when starting a room', () {
    expect(
      startRoomErrorMessage(
        limited('resource-exhausted', {
          'reason': 'weekly-cap',
          'resetsAt': '2026-10-12T00:00:00.000Z',
        }),
      ),
      "You've used this week's live searches. More arrive "
      '${resetTimeText(DateTime.utc(2026, 10, 12))}.',
    );
    expect(
      startRoomErrorMessage(
        limited('unavailable', {'reason': 'live-search-paused'}),
      ),
      'Live restaurant search is paused for now. Try again later.',
    );
    expect(
      startRoomErrorMessage(limited('aborted', {'reason': 'in-progress'})),
      'This search is already running. Give it a moment.',
    );
    // Without a reason these are still the rate limit and an outage.
    expect(
      startRoomErrorMessage(limited('resource-exhausted', {})),
      startsWith('Restaurant search is busy'),
    );
    expect(
      startRoomErrorMessage(limited('unavailable', {})),
      startsWith('Restaurant search is unavailable'),
    );
    expect(
      startRoomErrorMessage(
        limited('failed-precondition', {'reason': 'too-few-results'}),
      ),
      'Not enough restaurants nearby match. Try a wider distance.',
    );
  });
}
