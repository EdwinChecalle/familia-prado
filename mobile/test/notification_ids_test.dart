import 'package:flutter_test/flutter_test.dart';
import 'package:familia_prado/core/notification_ids.dart';

void main() {
  test('ID stable for the same account and reminder', () {
    final id = notificationId('user-a:appointment:abc:3h');
    expect(notificationId('user-a:appointment:abc:3h'), id);
    expect(id, inInclusiveRange(100000, 799999));
    expect(notificationId('user-b:appointment:abc:3h'), isNot(id));
  });
  test('Voice channels differ from normal and match event type', () {
    expect(reminderKindSound('APPOINTMENT'), 'prado_cita');
    expect(reminderKindChannel('APPOINTMENT', spoken:true), 'prado_cita_voz_v2');
    expect(reminderKindChannel('TURN', spoken:false), 'prado_general_v2');
  });
}
