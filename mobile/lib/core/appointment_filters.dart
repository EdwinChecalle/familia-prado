/// Stable request builder shared by appointment lists and unit tests.
String appointmentSearchPath({
  required String bucket,
  required int limit,
  required int offset,
  String? from,
  String? to,
  String? responsibleMemberId,
  String? status,
}) {
  final parameters = <String, String>{
    'bucket': bucket,
    'limit': '$limit',
    'offset': '$offset',
  };
  if (from != null) parameters['from'] = from;
  if (to != null) parameters['to'] = to;
  if (responsibleMemberId != null) parameters['responsibleMemberId'] = responsibleMemberId;
  if (status != null && bucket == 'HISTORY') parameters['status'] = status;
  return '/api/appointments/search?${Uri(queryParameters: parameters).query}';
}
