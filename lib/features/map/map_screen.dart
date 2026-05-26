import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/tables.dart';
import 'map_notifier.dart';
import 'poi_bottom_sheet.dart';
import 'roi_filter_bar.dart';
import '../../core/database/database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';


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

  // 用 roiId 對應到顏色
  final Map<String, Color> _roiColorMap = {};

  Color _getColorForRoi(String roiId) {
    if (!_roiColorMap.containsKey(roiId)) {
      _roiColorMap[roiId] = _roiColors[_roiColorMap.length % _roiColors.length];
    }
    return _roiColorMap[roiId]!;
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
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapNotifierProvider);
    final markers = _buildMarkers(mapState.pois, mapState.selectedPoi);

    return Scaffold(
      appBar: AppBar(title: const Text('地點地圖')),
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
              if (mapState.selectedDate != null)
                TextButton(
                  onPressed: () =>
                      ref.read(mapNotifierProvider.notifier).loadPoisByDate(null),
                  child: const Text('清除'),
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
                MarkerLayer(
                  markers: markers,
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