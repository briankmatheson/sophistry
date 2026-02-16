import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class SophistryApi {
  final String baseUrl;
  SophistryApi({String? baseUrl}) : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  Future<String> createRun() async {
    final res = await http.post(_u('/api/mobile/run/'));
    if (res.statusCode != 200) throw Exception('createRun failed: ${res.statusCode} ${res.body}');
    return (jsonDecode(res.body) as Map<String, dynamic>)['run_uuid'] as String;
  }

  Future<Map<String, dynamic>> getQuestion(String runUuid) async {
    final res = await http.get(_u('/api/mobile/question', {'run_uuid': runUuid}));
    if (res.statusCode != 200) throw Exception('getQuestion failed: ${res.statusCode} ${res.body}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> submitAnswer({required String runUuid, required int testcaseId, required String answer}) async {
    final res = await http.post(
      _u('/api/mobile/answer/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'run_uuid': runUuid, 'testcase_id': testcaseId, 'answer': answer}),
    );
    if (res.statusCode != 200) throw Exception('submitAnswer failed: ${res.statusCode} ${res.body}');
  }

  Future<void> submitTestcase({required String slug, required String prompt, String title = ''}) async {
    final res = await http.post(
      _u('/api/mobile/testcase/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'slug': slug, 'prompt': prompt, 'title': title}),
    );
    if (res.statusCode != 200) throw Exception('submitTestcase failed: ${res.statusCode} ${res.body}');
  }
}
