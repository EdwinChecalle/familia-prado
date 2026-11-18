/// IDs reproducibles: al cambiar una cita se reemplaza su recordatorio,
/// no se cancelan todos los de la familia.
int notificationId(String key) {
  var hash = 0x811C9DC5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return 100000 + (hash % 700000);
}

String reminderKindSound(String kind) => switch (kind) {
  'APPOINTMENT' => 'prado_cita',
  'TURN' => 'prado_turno',
  'COLLECTION' => 'prado_colecta',
  _ => 'prado_aviso',
};

String reminderKindChannel(String kind, {required bool spoken}) {
  if (!spoken) return 'prado_general_v2';
  return switch (kind) {
    'APPOINTMENT' => 'prado_cita_voz_v2',
    'TURN' => 'prado_turno_voz_v2',
    'COLLECTION' => 'prado_colecta_voz_v2',
    _ => 'prado_aviso_voz_v2',
  };
}
