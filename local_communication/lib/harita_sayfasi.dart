import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_communication/services/prediction_api_service.dart';

class DamageMapPage extends StatefulWidget {
  const DamageMapPage({Key? key}) : super(key: key);

  @override
  State<DamageMapPage> createState() => _DamageMapPageState();
}

/// Modelden gelen tahmin bilgisiyle birlikte haritada göstereceğimiz marker verisi
class _PredictedMarker {
  final LatLng position;
  final int code;
  final String label;
  final double score;
  final String imageAsset;

  _PredictedMarker({
    required this.position,
    required this.code,
    required this.label,
    required this.score,
    required this.imageAsset,
  });
}

class _DamageMapPageState extends State<DamageMapPage> {
  final MapController _mapController = MapController();
  final PredictionApiService _apiService = PredictionApiService();

  LatLng? _current;
  
  final List<LatLng> _gatheringPoints = [
    LatLng(38.879814451796165, 40.52121304116331),
    LatLng(38.87441351117073, 40.524680139077205),
  ];

  List<LatLng> _markers = [];

  List<_PredictedMarker> _predictedMarkers = [];

  _PredictedMarker? _selectedMarker;

  @override
  void initState() {
    super.initState();
    _loadMarkers();
    _getLocation();
    _loadPredictionMarkers();
  }

  Future<void> _loadMarkers() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('markers') ?? [];
    setState(() {
      _markers = list.map((e) {
        final m = jsonDecode(e);
        return LatLng(m['lat'], m['lng']);
      }).toList();
    });
  }

  Future<void> _saveMarkers() async {
    final p = await SharedPreferences.getInstance();
    final list = _markers
        .map((m) => jsonEncode({'lat': m.latitude, 'lng': m.longitude}))
        .toList();
    await p.setStringList('markers', list);
  }

  Future<void> _getLocation() async {
    try {
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) return;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _current = LatLng(pos.latitude, pos.longitude);
      });

      // Haritayı otomatik hareket ettirme - kullanıcı manuel kontrol edebilir
      // _mapController.move(_current!, 15);
    } catch (_) {
      // Konum alınamazsa sessizce yoksay
    }
  }

  /// Şu anki konuma manuel marker ekler (mevcut davranış)
  void _addMarker() {
    if (_current == null) return;
    setState(() {
      _markers.add(_current!);
    });
    _saveMarkers();
  }

  Future<void> _openGoogleMapsDirections(LatLng destination) async {
    if (_current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to determine your location')),
      );
      return;
    }

    final String googleUrl =
        'https://www.google.com/maps/dir/?api=1&origin=${_current!.latitude},${_current!.longitude}&destination=${destination.latitude},${destination.longitude}&travelmode=driving';

    if (await canLaunchUrl(Uri.parse(googleUrl))) {
      await launchUrl(Uri.parse(googleUrl), mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  /// Dosya adındaki koordinat bilgisinden LatLng üretir
  /// Örnek: "1 (4)38.88717322064629, 40.51533692765841.jpg"
  LatLng? _latLngFromFilename(String assetPath) {
    try {
      final name = assetPath.split('/').last; // 1 (4)38.88...,40.51....jpg
      final dotIndex = name.lastIndexOf('.');
      final withoutExt = dotIndex != -1 ? name.substring(0, dotIndex) : name;
      final parenIndex = withoutExt.indexOf(')');
      if (parenIndex == -1 || parenIndex + 1 >= withoutExt.length) {
        return null;
      }
      final coordPart = withoutExt.substring(parenIndex + 1).trim();
      final parts = coordPart.split(',');
      if (parts.length != 2) return null;
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  /// Modeldeki sınıf koduna göre renk belirler
  Color _colorForCode(int code) {
    switch (code) {
      case 1: // hasarlı
        return Colors.orange;
      case 2: // yıkılmış
        return Colors.red;
      case 3: // hasarsız
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  /// Model koduna göre kullanılacak ikon asset'ini döndürür
  /// 1: hasarlı (sarı), 2: yıkılmış (kırmızı), 3: hasarsız (yeşil)
  String _iconAssetForCode(int code) {
    switch (code) {
      case 1:
        return 'assets/icons/yellow.png';
      case 2:
        return 'assets/icons/red.png';
      case 3:
        return 'assets/icons/green.png';
      default:
        return 'assets/icons/yellow.png';
    }
  }

  Future<void> _loadPredictionMarkers() async {
    final List<_PredictedMarker> result = [];
    
    try {
      final manifest = await DefaultAssetBundle.of(context).loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifest);
      
      final imageAssets = manifestMap.keys
          .where((String key) => key.startsWith('assets/images/'))
          .toList();

      for (final asset in imageAssets) {
        final pos = _latLngFromFilename(asset);
        if (pos == null) {
          debugPrint('Dosya adından koordinat okunamadı: $asset');
          continue;
        }

        try {
          final byteData = await rootBundle.load(asset);
          final bytes = byteData.buffer
              .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
          final filename = asset.split('/').last;

          final prediction = await _apiService.predictDamageBytes(
            bytes: bytes,
            filename: filename,
          );

          final top1 = prediction.top1;
          result.add(
            _PredictedMarker(
              position: pos,
              code: top1.code,
              label: top1.label,
              score: top1.score,
              imageAsset: asset,
            ),
          );
        } catch (e) {
          debugPrint('Tahmin alınırken hata oluştu ($asset): $e');
        }
      }
    } catch (e) {
      debugPrint('AssetManifest yüklenirken hata: $e');
    }

    if (!mounted) return;
    setState(() {
      _predictedMarkers = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Elazığ merkez koordinatları (deprem bölgesi) - sabit konumda kal
    final center = LatLng(38.888, 40.515);
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Damage Map'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: isMobile ? _buildMobileLayout(center) : _buildDesktopLayout(center),
    );
  }

  Widget _buildMobileLayout(LatLng center) {
    return Column(
      children: [
        // Harita alanı
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
                  minZoom: 10,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),

                  // Yıkılmış binaların etrafındaki tehlikeli bölgeler (Kırmızı) - SABİT ÇAP
                  CircleLayer(
                    circles: _predictedMarkers
                        .where((pm) => pm.code == 2) // 2: yıkılmış
                        .map(
                          (pm) => CircleMarker(
                            point: pm.position,
                            color: Colors.red.withOpacity(0.15),
                            borderColor: Colors.red.withOpacity(0.6),
                            borderStrokeWidth: 2,
                            radius: 40, // Metre cinsinden - daha büyük çap
                            useRadiusInMeter: true,
                          ),
                        )
                        .toList(),
                  ),

                  
                MarkerLayer(
                  markers: [
                    // Kullanıcının mevcut konumu (mavi)
                    if (_current != null)
                      Marker(
                        point: _current!,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 28,
                          ),
                        ),
                      ),

                    // Kullanıcının manuel eklediği marker'lar (kırmızı)
                    ..._markers
                        .map(
                          (m) => Marker(
                            point: m,
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                            ),
                          ),
                        )
                        .toList(),

                    ..._gatheringPoints.map(
                      (point) => Marker(
                        point: point,
                        width: 50,
                        height: 50,
                        child: GestureDetector(
                          onTap: () => _openGoogleMapsDirections(point),
                          child: Tooltip(
                            message: 'Gathering Point - Get Directions',
                            child: Image.asset(
                              'assets/icons/pngwing.com (18).png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ).toList(),

                    // Model tahminine göre özel ikon ile gösterilen marker'lar
                    ..._predictedMarkers.map(
                      (pm) => Marker(
                        point: pm.position,
                        width: 40,
                        height: 56,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedMarker = pm;
                            });
                          },
                          child: Tooltip(
                            message:
                                '${pm.label} (${pm.score.toStringAsFixed(2)})',
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    _iconAssetForCode(pm.code),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.black87,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Floating butonlar
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_current != null)
                    FloatingActionButton(
                      heroTag: 'myLocation',
                      mini: true,
                      onPressed: () => _mapController.move(_current!, 15),
                      child: const Icon(Icons.my_location),
                    ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'addMarker',
                    mini: true,
                    onPressed: _addMarker,
                    child: const Icon(Icons.add_location),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // Alt bilgi paneli (mobil için) - Kaydırılabilir ve daha büyük
      if (_selectedMarker != null)
        Container(
          height: 500,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Column(
            children: [
              // Kapatma çubuğu
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _selectedMarker = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildInfoPanel(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(LatLng center) {
    return Row(
      children: [
        // Harita alanı
        Expanded(
          flex: 3,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
              minZoom: 10,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),

              // Yıkılmış binaların etrafındaki bölgeler (Kırmızı) - SABİT ÇAP
              CircleLayer(
                circles: _predictedMarkers
                    .where((pm) => pm.code == 2) // 2: yıkılmış
                    .map(
                      (pm) => CircleMarker(
                        point: pm.position,
                        color: Colors.red.withOpacity(0.15),
                        borderColor: Colors.red.withOpacity(0.6),
                        borderStrokeWidth: 2,
                        radius: 80, // Metre cinsinden - daha büyük çap
                        useRadiusInMeter: true,
                      ),
                    )
                    .toList(),
              ),

              // Hasarlı binaların etrafındaki bölgeler (Sarı) - SABİT ÇAP
              CircleLayer(
                circles: _predictedMarkers
                    .where((pm) => pm.code == 1) // 1: hasarlı
                    .map(
                      (pm) => CircleMarker(
                        point: pm.position,
                        color: Colors.yellow.withOpacity(0.15),
                        borderColor: Colors.orange.withOpacity(0.6),
                        borderStrokeWidth: 2,
                        radius: 80, // Metre cinsinden - aynı çap
                        useRadiusInMeter: true,
                      ),
                    )
                    .toList(),
              ),

              // Hasarsız binaların etrafındaki bölgeler (Yeşil) - SABİT ÇAP
              CircleLayer(
                circles: _predictedMarkers
                    .where((pm) => pm.code == 3) // 3: hasarsız
                    .map(
                      (pm) => CircleMarker(
                        point: pm.position,
                        color: Colors.green.withOpacity(0.15),
                        borderColor: Colors.green.withOpacity(0.6),
                        borderStrokeWidth: 2,
                        radius: 80, // Metre cinsinden - aynı çap
                        useRadiusInMeter: true,
                      ),
                    )
                    .toList(),
              ),

              MarkerLayer(
                markers: [
                  // Kullanıcının mevcut konumu (mavi)
                  if (_current != null)
                    Marker(
                      point: _current!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 28,
                        ),
                      ),
                    ),

                  // Kullanıcının manuel eklediği marker'lar
                  ..._markers
                      .map(
                        (m) => Marker(
                          point: m,
                          width: 36,
                          height: 36,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                          ),
                        ),
                      )
                      .toList(),

                  ..._gatheringPoints.map(
                    (point) => Marker(
                      point: point,
                      width: 50,
                      height: 50,
                      child: GestureDetector(
                        onTap: () => _openGoogleMapsDirections(point),
                        child: Tooltip(
                          message: 'Gathering Point - Get Directions',
                          child: Image.asset(
                            'assets/icons/pngwing.com (18).png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ).toList(),

                  // Model tahminine göre özel ikon ile gösterilen marker'lar
                  ..._predictedMarkers.map(
                    (pm) => Marker(
                      point: pm.position,
                      width: 40,
                      height: 56,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedMarker = pm;
                          });
                        },
                        child: Tooltip(
                          message:
                              '${pm.label} (${pm.score.toStringAsFixed(2)})',
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  _iconAssetForCode(pm.code),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const Icon(
                                Icons.arrow_drop_down,
                                color: Colors.black87,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Sağ tarafta bilgi paneli
        Container(
          width: 320,
          color: Colors.white,
          child: Column(
            children: [
              // Üst kısım - başlık ve kapat butonu
              if (_selectedMarker != null)
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Building Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedMarker = null;
                          });
                        },
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
              // İçerik
              Expanded(
                child: _buildInfoPanel(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Sağ tarafta, seçili marker'ın detaylarını gösteren panel
  Widget _buildInfoPanel(BuildContext context) {
    final marker = _selectedMarker;

    if (marker == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Click on an icon on the map.\n\n'
            'Selected building photo and location/damage information will appear here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Selected Building',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              marker.imageAsset,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Coordinates',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Latitude: ${marker.position.latitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 15),
          ),
          Text(
            'Longitude: ${marker.position.longitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 16),
          Text(
            'Damage Status',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Class: ${marker.label}',
            style: const TextStyle(fontSize: 15),
          ),
          Text(
            'Confidence: ${(marker.score * 100).toStringAsFixed(1)} %',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedMarker = null;
                });
              },
              icon: const Icon(Icons.close),
              label: const Text('Close'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.red[400],
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

