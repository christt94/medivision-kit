import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

class ApiClient {
  static const String base = 'http://localhost:8000/api';

  static Future<dynamic> get(String path) async {
    final res = await http.get(Uri.parse('$base$path'));
    if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes));
    throw Exception('GET $path → ${res.statusCode}: ${res.body}');
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$base$path'),
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    throw Exception('PATCH $path → ${res.statusCode}: ${res.body}');
  }

  static Future<void> delete(String path) async {
    final res = await http.delete(Uri.parse('$base$path'));
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
