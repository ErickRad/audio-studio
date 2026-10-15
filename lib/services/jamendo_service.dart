import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/search_result.dart';

class JamendoService {
  Future<List<SearchResult>> search(String query) async {
    if (jamendoClientId == 'SEU_CLIENT_ID') {
      throw Exception('Defina o client_id do Jamendo em lib/config.dart');
    }
    final uri = Uri.https('api.jamendo.com', '/v3.0/tracks/', {
      'client_id': jamendoClientId,
      'format': 'json',
      'limit': '30',
      'search': query,
      'audiodlformat': 'mp32',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final results = (body['results'] as List).cast<Map<String, dynamic>>();
    return results
        .where((j) => j['audiodownload_allowed'] == true)
        .map((j) => SearchResult(
              source: SearchSource.jamendo,
              id: j['id'].toString(),
              title: (j['name'] ?? 'Sem titulo').toString(),
              artist: (j['artist_name'] ?? 'Desconhecido').toString(),
              imageUrl: (j['image'] ?? '').toString(),
              streamUrl: (j['audio'] ?? '').toString(),
              downloadUrl: (j['audiodownload'] ?? '').toString(),
              license: (j['license_ccurl'] ?? '').toString(),
              durationMs: (int.tryParse(j['duration'].toString()) ?? 0) * 1000,
            ))
        .toList();
  }
}
