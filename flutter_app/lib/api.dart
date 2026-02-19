import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class SophistryApi {
  final String baseUrl;
  SophistryApi({String? baseUrl}) : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path').replace(
          queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  /// Create a new run, returns run_uuid
  Future<String> createRun() async {
    final res = await http.post(_u('/api/mobile/run/'));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('createRun failed: ${res.statusCode} ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['run_uuid'] as String;
  }

  /// Get next question for a run
  Future<Map<String, dynamic>?> getQuestion(String runUuid) async {
    final res = await http.get(_u('/api/mobile/question', {'run_uuid': runUuid}));
    if (res.statusCode == 404) return null; // no more questions
    if (res.statusCode != 200) {
      throw Exception('getQuestion failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Submit an answer
  Future<Map<String, dynamic>> submitAnswer({
    required String runUuid,
    required int testcaseId,
    required String answer,
  }) async {
    final res = await http.post(
      _u('/api/mobile/answer/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'run_uuid': runUuid,
        'testcase_id': testcaseId,
        'answer': answer,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('submitAnswer failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Get review data for a completed run
  Future<Map<String, dynamic>> getReview(String runUuid) async {
    final res = await http.get(_u('/api/mobile/review/', {'run_uuid': runUuid}));
    if (res.statusCode != 200) {
      throw Exception('getReview failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Preview structural score without persisting a Result
  Future<Map<String, dynamic>> previewScore({
    required int testcaseId,
    required String answer,
  }) async {
    final res = await http.post(
      _u('/api/mobile/preview_score/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'testcase_id': testcaseId,
        'answer': answer,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('previewScore failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Submit a new testcase (user-contributed question)
  Future<void> submitTestcase({
    required String slug,
    required String prompt,
    String title = '',
  }) async {
    final res = await http.post(
      _u('/api/mobile/testcase/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'slug': slug, 'prompt': prompt, 'title': title}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('submitTestcase failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Reset session — Django issues new cookie
  Future<void> resetSession() async {
    await http.post(
      _u('/api/session/reset/'),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
