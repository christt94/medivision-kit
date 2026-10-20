import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

class ApiClient {
  // Override for deployed/mobile environments with:
  // flutter run --dart-define=API_BASE_URL=https://server.example/api
  static const String base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api',
  );

  static const _tokenKey = 'medivision_access_token';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final token = await getToken();
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static Future<dynamic> get(String path) async {
    final res = await http.get(Uri.parse('$base$path'), headers: await _headers());
    if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes));
    throw Exception('GET $path → ${res.statusCode}: ${res.body}');
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$base$path'),
      headers: await _headers(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    throw Exception('POST $path → ${res.statusCode}: ${res.body}');
  }

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(
      Uri.parse('$base$path'),
      headers: await _headers(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    throw Exception('PATCH $path → ${res.statusCode}: ${res.body}');
  }

  static Future<void> delete(String path) async {
    final res = await http.delete(Uri.parse('$base$path'), headers: await _headers());
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('DELETE $path → ${res.statusCode}: ${res.body}');
    }
  }

  static Future<dynamic> postMultipartBytes(
    String path,
    Map<String, String> fields,
    String fileField,
    Uint8List fileBytes,
    String fileName,
  ) async {
    final req = http.MultipartRequest('POST', Uri.parse('$base$path'));
    req.headers.addAll(await _headers());
    req.fields.addAll(fields);
    req.files.add(
      http.MultipartFile.fromBytes(fileField, fileBytes, filename: fileName),
    );
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Multipart $path → ${res.statusCode}: ${res.body}');
  }

  static Future<Map<String, dynamic>> uploadFile(
    String path, {
    required Uint8List fileBytes,
    required String fileName,
    required Map<String, String> fields,
    String fileField = 'file',
  }) async {
    final data = await postMultipartBytes(
      path,
      fields,
      fileField,
      fileBytes,
      fileName,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$base/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': username, 'password': password},
    );
    if (res.statusCode != 200) throw Exception('Identifiants invalides (${res.statusCode})');
    final data = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    await saveToken(data['access_token'] as String);
    return data;
  }

  static Future<Map<String, dynamic>> register({
    required String username,
    required String fullName,
    required String password,
  }) async {
    final data = await post('/auth/register', {
      'username': username, 'full_name': fullName, 'password': password,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<void> downloadPdf(
    String path, {
    required Map<String, String> fields,
    required String fileName,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$base$path'));
    req.fields.addAll(fields);

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception('PDF $path → ${res.statusCode}: ${res.body}');
    }

    final bytes = res.bodyBytes;
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}
