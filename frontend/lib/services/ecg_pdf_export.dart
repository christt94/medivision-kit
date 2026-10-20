import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

class EcgPdfExport {
  static const String _base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api',
  );

  static Future<void> exportAndDownload({
    required Uint8List csvBytes,
    required Map<String, dynamic> result,
    required String patientName,
    required String recordDate,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/ecg/export-pdf'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'csv_b64':      base64Encode(csvBytes),
        'result':       result,
        'patient_name': patientName,
        'record_date':  recordDate,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Export PDF échoué : ${response.statusCode}\n${response.body}');
    }
    final bytes = response.bodyBytes;
    if (kIsWeb) {
      final blob   = html.Blob([bytes], 'application/pdf');
      final url    = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'ecg_report.pdf')
        ..click();
      html.Url.revokeObjectUrl(url);
      anchor.remove();
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }
}
