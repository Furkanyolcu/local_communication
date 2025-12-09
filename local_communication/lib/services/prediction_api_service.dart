import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:local_communication/models/prediction_models.dart';

/// Görseli Flask API'ye gönderip tahmin sonucunu alan servis
class PredictionApiService {
  /// Flask sunucunun base URL'i
  ///
  /// Android emülatörden makinedeki localhost'a erişmek için `10.0.2.2` kullanıyoruz.
  /// Eğer Chrome/web'de çalıştıracaksan bunu tekrar `http://127.0.0.1:5000` yapabilirsin.
  // static const String _baseUrl = 'http://10.0.2.2:5000';
  static const String _baseUrl = 'http://127.0.0.1:5000';

  /// Dosya yolundan (`File`) `/predict` endpoint'ine multipart/form-data ile POST eder.
  /// Mobil / desktop platformları için kullanılır.
  Future<PredictionResponse> predictDamage({
    required File imageFile,
    String fieldName = 'file',
  }) async {
    final uri = Uri.parse('$_baseUrl/predict');

    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          fieldName,
          imageFile.path,
        ),
      );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw HttpException(
        'Tahmin isteği başarısız oldu: HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final Map<String, dynamic> jsonMap =
        jsonDecode(response.body) as Map<String, dynamic>;

    return PredictionResponse.fromJson(jsonMap);
  }

  /// Asset veya memory'deki `bytes` verisini kullanarak `/predict` endpoint'ine
  /// multipart/form-data ile POST eder.
  /// Özellikle web tarafında dosya sistemi kullanamadığımız durumlar için.
  Future<PredictionResponse> predictDamageBytes({
    required List<int> bytes,
    required String filename,
    String fieldName = 'file',
  }) async {
    final uri = Uri.parse('$_baseUrl/predict');

    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: filename,
        ),
      );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw HttpException(
        'Tahmin isteği başarısız oldu: HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final Map<String, dynamic> jsonMap =
        jsonDecode(response.body) as Map<String, dynamic>;

    return PredictionResponse.fromJson(jsonMap);
  }
}

