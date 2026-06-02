import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/tables.dart';
import 'map_notifier.dart';
import 'poi_bottom_sheet.dart';
import 'roi_filter_bar.dart';
import '../../core/database/database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';


class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  static const List<Color> _roiColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.brown,
  ];

  LatLng? _currentLocation;
  
  // 用 roiId 對應到顏色
  final Map<String, Color> _roiColorMap = {};

  Color _getColorForRoi(String? roiId) {
    // POIs may have no region (roiId is nullable post-v4); bucket them together.
    final key = roiId ?? '__none__';
    if (!_roiColorMap.containsKey(key)) {
      _roiColorMap[key] = _roiColors[_roiColorMap.length % _roiColors.length];
    }
    return _roiColorMap[key]!;
  }

  List<Marker> _buildMarkers(List<Poi> pois, Poi? selected) {
    return pois.map((p) => Marker(
      point: LatLng(p.lat, p.lng),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () {
          ref.read(mapNotifierProvider.notifier).selectPoi(p);
          _showPoiSheet(p);
        },
        child: Icon(
          Icons.location_pin,
          color: selected?.id == p.id
              ? Colors.yellow      // 選中時變黃色
              : _getColorForRoi(p.roiId),
          size: 40,
        ),
      ),
    )).toList();
  }

  // 移動到標點群中心
  void _fitMarkers(List<Poi> pois) {
    if (pois.isEmpty) return;
    if (pois.length == 1) {
      _mapController.move(LatLng(pois.first.lat, pois.first.lng), 14);
      return;
    }

    final bounds = LatLngBounds.fromPoints(
      pois.map((p) => LatLng(p.lat, p.lng)).toList(),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  // 移動到使用者當前位置
  Future<void> _moveToCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(position.latitude, position.longitude), 10);
    } catch (e) {
      // 無法取得位置時不動
    }
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      // 無法取得位置
    }
  }

  void _showPoiSheet(Poi poi) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PoiBottomSheet(poi: poi),
    ).whenComplete(
      () => ref.read(mapNotifierProvider.notifier).clearSelection(),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapNotifierProvider);
    final markers = _buildMarkers(mapState.pois, mapState.selectedPoi);

    // 當 pois 更新時自動移動地圖
    ref.listen(mapNotifierProvider, (previous, next) {
      if (previous?.pois != next.pois) {
        if (next.pois.isEmpty) {
          _moveToCurrentLocation();
        } else if (next.selectedDate != null) {
          // 選了日期，移到標點群中心
          _fitMarkers(next.pois);
        } else if (next.selectedRoiId == null && next.selectedDate == null) {
          // 回到全部，移到使用者位置
          _moveToCurrentLocation();
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
                title: const Text('地點地圖'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.my_location),
                    onPressed: () async {
                      await _fetchCurrentLocation();
                      if (_currentLocation != null) {
                        _mapController.move(_currentLocation!, 14);
                      }
                    },
                  ),
                ],
              ),
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: RoiFilterBar(
                  selectedRoiId: mapState.selectedRoiId,
                  onChanged: (roiId) =>
                      ref.read(mapNotifierProvider.notifier).loadPois(roiId: roiId),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today),
                tooltip: '選擇日期',
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    final dateStr =
                        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    ref.read(mapNotifierProvider.notifier).loadPoisByDate(dateStr);
                  }
                },
              ),
              
            ],
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(23.0, 121.0),
                initialZoom: 7,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.trip_planner',
                ),
                MarkerLayer(markers: markers),
                if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentLocation!,
                        width: 48,
                        height: 48,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.3),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue, width: 2),
                              ),
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    rotate: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}