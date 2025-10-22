import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class HaritaSayfasi extends StatefulWidget {
  const HaritaSayfasi({Key? key}) : super(key: key);

  @override
  State<HaritaSayfasi> createState() => _HaritaSayfasiState();
}

class _HaritaSayfasiState extends State<HaritaSayfasi> {
  final MapController _mapController = MapController();

  LatLng? _current;

  List<LatLng> _markers = [];

  @override
  void initState() {
    super.initState();
    _loadMarkers(); 
    _getLocation(); 
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
    final list = _markers.map((m) => jsonEncode({'lat': m.latitude, 'lng': m.longitude})).toList();
    await p.setStringList('markers', list);
  }

  Future<void> _getLocation() async {
    try {
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) return; 

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _current = LatLng(pos.latitude, pos.longitude);
      });

      _mapController.move(_current!, 15);
    } catch (_) {
    }
  }

  void _addMarker() {
    if (_current == null) return; 
    setState(() {
      _markers.add(_current!);
    });
    _saveMarkers();
  }

  @override
  Widget build(BuildContext context) {
    final center = _current ?? LatLng(39.925533, 32.866287);
    return Scaffold(
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(center: center, zoom: 13),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          ),

          MarkerLayer(
            markers: [
              if (_current != null)
                Marker(point: _current!, width: 36, height: 36, child: Icon(Icons.my_location, color: Colors.blue)),

              ..._markers.map((m) => Marker(point: m, width: 36, height: 36, child: Icon(Icons.location_on, color: Colors.red))).toList(),
            ],
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _addMarker,
        child: Icon(Icons.add_location),
      ),
    );
  }
}
