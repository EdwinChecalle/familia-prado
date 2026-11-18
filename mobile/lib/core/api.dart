import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

class ApiException implements Exception {
  ApiException(this.message, this.status);
  final String message;
  final int status;
  @override String toString() => message;
}

class FamilyApi {
  FamilyApi();
  final _secure = const FlutterSecureStorage();
  String? _token;
  String? get token => _token;

  Future<bool> restore() async {
    _token = await _secure.read(key: 'session_token');
    if (_token == null) return false;
    try {
      await get('/api/auth/me');
      return true;
    } catch (_) {
      await logout(localOnly: true);
      return false;
    }
  }

  Future<void> login(String email, String password) async {
    final response = await post('/api/auth/login', {'email': email, 'password': password}, authenticated: false);
    _token = response['token'] as String;
    await _secure.write(key: 'session_token', value: _token);
  }

  Future<void> logout({bool localOnly = false}) async {
    if (!localOnly && _token != null) {
      try { await post('/api/auth/logout', {}); } catch (_) { /* revoke is best effort */ }
    }
    _token = null;
    await _secure.delete(key: 'session_token');
  }

  Future<dynamic> uploadCareDocument(String title, String category, String filename,
      Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw ApiException('El documento debe tener entre 1 byte y 5 MB', 400);
    }
    final uri = Uri.parse('$apiBase/api/care/documents');
    if (kReleaseMode && uri.scheme != 'https') throw ApiException('Se requiere HTTPS', 0);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['title'] = title
      ..fields['category'] = category
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 40));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 400) {
        throw ApiException('No se pudo guardar el documento (${response.statusCode})', response.statusCode);
      }
      return jsonDecode(response.body);
    } on ApiException { rethrow; }
    catch (_) { throw ApiException('Error al cargar el documento privado', 0); }
  }

  Future<Uint8List> downloadCareDocument(String id) async {
    final uri = Uri.parse('$apiBase/api/care/documents/$id/download');
    if (kReleaseMode && uri.scheme != 'https') throw ApiException('Se requiere HTTPS', 0);
    try {
      final response = await http.get(uri,
        headers: {'Authorization': 'Bearer $_token'}).timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw ApiException('No se pudo abrir el documento (${response.statusCode})', response.statusCode);
      }
      return response.bodyBytes;
    } on ApiException { rethrow; }
    catch (_) { throw ApiException('No se pudo obtener el documento', 0); }
  }

  Future<dynamic> get(String path) => _request('GET', path);
  Future<dynamic> post(String path, Map<String, dynamic> data, {bool authenticated = true}) =>
      _request('POST', path, data: data, authenticated: authenticated);
  Future<dynamic> put(String path, Map<String, dynamic> data) => _request('PUT', path, data: data);
  Future<dynamic> patch(String path, Map<String, dynamic> data) => _request('PATCH', path, data: data);

  Future<dynamic> _request(String method, String path, {Map<String, dynamic>? data, bool authenticated = true}) async {
    if (!kDebugMode && !Uri.parse(apiBase).hasScheme) {
      throw ApiException('Dirección del servidor incorrecta', 0);
    }
    final uri = Uri.parse('$apiBase$path');
    // Only permit HTTP when developing against an emulator/PC; production requires HTTPS.
    if (kReleaseMode && uri.scheme != 'https') {
      throw ApiException('En producción se necesita una conexión HTTPS segura', 0);
    }
    final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (authenticated && _token != null) headers['Authorization'] = 'Bearer $_token';
    late http.Response response;
    try {
      response = await (switch (method) {
        'GET' => http.get(uri, headers: headers),
        'POST' => http.post(uri, headers: headers, body: jsonEncode(data)),
        'PUT' => http.put(uri, headers: headers, body: jsonEncode(data)),
        'PATCH' => http.patch(uri, headers: headers, body: jsonEncode(data)),
        _ => throw ApiException('Método de red desconocido', 0),
      }).timeout(const Duration(seconds: 18));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('No se pudo conectar con el servidor. Revisa internet y la dirección configurada.', 0);
    }
    dynamic decoded;
    try { decoded = response.body.isEmpty ? null : jsonDecode(response.body); }
    catch (_) { decoded = null; }
    if (response.statusCode >= 400) {
      final message = decoded is Map ? (decoded['error'] ?? decoded['detail'] ?? 'Error del servidor') : 'Error del servidor';
      throw ApiException('$message', response.statusCode);
    }
    return decoded;
  }
}

String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
DateTime peruToday() {
  final clock = DateTime.now().toUtc().subtract(const Duration(hours: 5));
  return DateTime(clock.year, clock.month, clock.day);
}
DateTime firstMonday(DateTime value) => DateTime(value.year, value.month, value.day - (value.weekday - DateTime.monday));
const daysSpanish = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
String dateSpanish(DateTime date) => '${date.day}/${date.month.toString().padLeft(2, '0')}/${date.year}';
DateTime parseDate(String value) => DateTime.parse(value);

// API appointments use UTC instants, but the calendar is always presented in Peru time (UTC-5).
DateTime peruClock(String isoUtc) => DateTime.parse(isoUtc).toUtc().subtract(const Duration(hours: 5));
String peruToUtcIso(DateTime day, int hour, int minute) =>
    DateTime.utc(day.year, day.month, day.day, hour + 5, minute).toIso8601String();
