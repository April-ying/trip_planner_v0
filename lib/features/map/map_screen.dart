import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'map_notifier.dart';
import 'poi_bottom_sheet.dart';
import 'roi_filter_bar.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:trip_planner/core/database/database.dart';



class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {

  // 1. 宣告一個變數用來儲存訂閱狀態
  ProviderSubscription? _mapSubscription;
  
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.mapEventStream.first.then((_) {
        // 2. 將監聽器存入變數
        _mapSubscription = ref.listenManual(mapNotifierProvider, (previous, next) {
          if (previous?.pois != next.pois) {
            if (next.selectedDate != null || next.selectedRoiId != null) {
              _fitMarkers(next.pois);
            }
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapNotifierProvider);
    final markers = _buildMarkers(mapState.pois, mapState.selectedPoi);

    return Scaffold(
      appBar: AppBar(
                title: const Text('Map'),
              ),
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: RoiFilterBar(
                  selectedRoiId: mapState.selectedRoiId,
                  onChanged: (roiId) async {
                    // 1. 先等待資料載入並更新狀態
                    await ref.read(mapNotifierProvider.notifier).loadPois(roiId: roiId);
                    
                    // 2. 檢查 Widget 是否還存在（防止非同步期間使用者已經跳出畫面）
                    if (!mounted) return;
                    
                    // 3. 告訴 Flutter：當這一幀的資料渲染到畫面上後，立刻執行縮放
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _fitMarkers(ref.read(mapNotifierProvider).pois);
                      }
                    });
                  },
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
                    await ref.read(mapNotifierProvider.notifier).loadPoisByDate(dateStr);
                    await Future.delayed(const Duration(milliseconds: 300));
                    if (mounted) {
                      _fitMarkers(ref.read(mapNotifierProvider).pois);
                    }
                  }
                },
              ),
              if (mapState.selectedDate != null)
                TextButton(
                  onPressed: () => ref.read(mapNotifierProvider.notifier).clearDateFilter(),
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
  @override
  void dispose() {
    // 3. 當畫面銷毀時，務必手動關閉監聽器，防止記憶體洩漏！
    _mapSubscription?.close();
    super.dispose();
  }
}