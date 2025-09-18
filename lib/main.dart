import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// ★ 追加
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// ステップ3：
/// - assets/tokyo_municipal.geojson を読み込む
/// - リスト表示（自治体名 + 頂点数）
/// - リストの行をタップすると、下部の地図にその自治体のBBoxを薄赤で描画

const String kAssetPath = 'assets/tokyo_municipal.geojson';

/// 表示用モデル
class MunicipalRow {
  final String name; // 例：杉並区
  final int vertexCount; // 頂点数
  // ★ 追加: BBox
  final double minLat, minLng, maxLat, maxLng;

  const MunicipalRow(this.name, this.vertexCount, {this.minLat = 0, this.minLng = 0, this.maxLat = 0, this.maxLng = 0});
}

void main() {
  runApp(const Step3App());
}

class Step3App extends StatelessWidget {
  const Step3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step3: List + Map BBox',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF5566EE)),
      home: const Step3Page(),
    );
  }
}

class Step3Page extends StatefulWidget {
  const Step3Page({super.key});

  @override
  State<Step3Page> createState() => _Step3PageState();
}

class _Step3PageState extends State<Step3Page> {
  late Future<List<MunicipalRow>> _future;

  // ★ 追加: 地図用の状態
  final MapController _mapController = MapController();
  final LatLng _center = const LatLng(35.6895, 139.6917); // 都庁あたり
  MunicipalRow? _selected; // 選択中

  @override
  void initState() {
    super.initState();
    _future = _loadRows();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ステップ3：リスト + 地図にBBox描画')),
      body: FutureBuilder<List<MunicipalRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('読み込みエラー: ${snap.error}', style: const TextStyle(color: Colors.red)),
            );
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('データが空です'));
          }

          return Column(
            children: [
              // ---- リスト（上）----
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final selected = identical(_selected, r);
                    return ListTile(
                      title: Text(r.name),
                      trailing: Text(r.vertexCount.toString()),
                      selected: selected,
                      onTap: () => setState(() => _selected = r), // ★ タップで選択
                    );
                  },
                ),
              ),
              // ---- 地図（下）----
              SizedBox(
                height: 260,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: _center, initialZoom: 10),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.step3_bbox_preview',
                    ),
                    // ★ 選択されたBBoxを描画
                    if (_selected != null)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _bboxToPolygon(_selected!),
                            isFilled: true,
                            color: const Color(0x33FF0000),
                            borderColor: const Color(0xFFFF0000),
                            borderStrokeWidth: 1.5,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ★ BBox → ポリゴン化
  List<LatLng> _bboxToPolygon(MunicipalRow r) {
    return [
      LatLng(r.minLat, r.minLng),
      LatLng(r.minLat, r.maxLng),
      LatLng(r.maxLat, r.maxLng),
      LatLng(r.maxLat, r.minLng),
    ];
  }
}

/// GeoJSON を読み込み、
/// - 自治体名
/// - 頂点数
/// - BBox
Future<List<MunicipalRow>> _loadRows() async {
  final text = await rootBundle.loadString(kAssetPath);
  final data = jsonDecode(text);

  final List features;
  if (data['type'] == 'FeatureCollection') {
    features = (data['features'] as List);
  } else if (data['type'] == 'Feature') {
    features = [data];
  } else {
    throw Exception('Unsupported root type: ${data['type']}');
  }

  final rows = <MunicipalRow>[];

  for (final f in features) {
    final props = Map<String, dynamic>.from(f['properties'] ?? {});
    final geom = Map<String, dynamic>.from(f['geometry'] ?? {});
    if (geom.isEmpty) continue;

    final name = (props['N03_004'] ?? props['name'] ?? '') as String;
    if (name.isEmpty) continue;

    final type = geom['type'] as String?;
    final coords = geom['coordinates'];

    int count = 0;
    double? minLat, minLng, maxLat, maxLng;

    void addPoint(double lng, double lat) {
      count++;
      minLat = (minLat == null) ? lat : (lat < minLat! ? lat : minLat);
      maxLat = (maxLat == null) ? lat : (lat > maxLat! ? lat : maxLat);
      minLng = (minLng == null) ? lng : (lng < minLng! ? lng : minLng);
      maxLng = (maxLng == null) ? lng : (lng > maxLng! ? lng : maxLng);
    }

    if (type == 'Polygon') {
      for (final ring in (coords as List)) {
        for (final pt in (ring as List)) {
          addPoint((pt[0] as num).toDouble(), (pt[1] as num).toDouble());
        }
      }
    } else if (type == 'MultiPolygon') {
      for (final poly in (coords as List)) {
        for (final ring in (poly as List)) {
          for (final pt in (ring as List)) {
            addPoint((pt[0] as num).toDouble(), (pt[1] as num).toDouble());
          }
        }
      }
    } else {
      continue;
    }

    rows.add(
      MunicipalRow(name, count, minLat: minLat ?? 0, minLng: minLng ?? 0, maxLat: maxLat ?? 0, maxLng: maxLng ?? 0),
    );
  }

  rows.sort((a, b) => a.name.compareTo(b.name));
  return rows;
}
