import 'dart:convert';

/// Flask API'den dönen tekil tahmin elemanı
class PredictionItem {
  final int code;
  final String label;
  final double score;

  PredictionItem({
    required this.code,
    required this.label,
    required this.score,
  });

  factory PredictionItem.fromJson(Map<String, dynamic> json) {
    return PredictionItem(
      code: json['code'] as int,
      label: json['label'] as String,
      score: (json['score'] as num).toDouble(),
    );
  }
}

/// Flask API yanıtının tamamı
class PredictionResponse {
  final List<PredictionItem> prediction;
  final PredictionItem top1;

  PredictionResponse({
    required this.prediction,
    required this.top1,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    final list = json['prediction'] as List<dynamic>;
    return PredictionResponse(
      prediction: list
          .map((e) => PredictionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      top1: PredictionItem.fromJson(json['top1'] as Map<String, dynamic>),
    );
  }

  /// İstersen debug için direkt string olarak yazdırmak istersen
  @override
  String toString() {
    return jsonEncode({
      'prediction': prediction
          .map((e) => {
                'code': e.code,
                'label': e.label,
                'score': e.score,
              })
          .toList(),
      'top1': {
        'code': top1.code,
        'label': top1.label,
        'score': top1.score,
      },
    });
  }
}

/// Uygulama içinde görsel + bu görsele ait tahmin bilgisini birlikte tutmak için
class ImagePredictionData {
  /// Cihazdaki dosya yolu (galeriden / kameradan seçtiğin resmin path'i)
  final String filePath;

  /// API'den gelen yanıt (istek atılmadan önce null olabilir)
  final PredictionResponse? predictionResponse;

  ImagePredictionData({
    required this.filePath,
    this.predictionResponse,
  });

  ImagePredictionData copyWith({
    String? filePath,
    PredictionResponse? predictionResponse,
  }) {
    return ImagePredictionData(
      filePath: filePath ?? this.filePath,
      predictionResponse: predictionResponse ?? this.predictionResponse,
    );
  }
}


