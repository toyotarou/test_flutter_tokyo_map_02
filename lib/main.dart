import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const String kAssetPath = 'assets/tokyo_municipal.geojson';

class MunicipalRow {
  final String name;
  final int vertexCount;
  final double minLat, minLng, maxLat, maxLng;
  final List<List<List<List<double>>>> polygons;
  final double centroidLat;
  final double centroidLng;
  int? zKey;

  MunicipalRow(
    this.name,
    this.vertexCount, {
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
    required this.polygons,
    required this.centroidLat,
    required this.centroidLng,
    this.zKey,
  });
}

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tokyo Municipalities',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF5566EE)),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<MunicipalRow>> _future;
  final MapController _mapController = MapController();
  final LatLng _center = const LatLng(35.6895, 139.6917);
  MunicipalRow? _selected;
  String _category = '区';

  @override
  void initState() {
    super.initState();
    _future = _loadRows();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tokyo Municipalities')),
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
          var rows = snap.data ?? const [];
          rows = _sortedByZOrder(rows);
          final filtered = rows.where((r) {
            if (_category == '区') return r.name.endsWith('区');
            if (_category == '市') return r.name.endsWith('市');
            return !r.name.endsWith('区') && !r.name.endsWith('市');
          }).toList();
          if (rows.isEmpty) {
            return const Center(child: Text('データが空です'));
          }

          //=================== 変更（背景＝本土のみ、全体表示も本土範囲）
          final backgroundRows = rows.where(_isMainland).toList();
          final mainlandBounds = _boundsOfAll(backgroundRows, fallback: rows);
          //=================== 変更

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _CatButton(
                      label: '23区',
                      selected: _category == '区',
                      onTap: () {
                        setState(() {
                          _category = '区';
                          _selected = null;
                        });
                        //=================== 変更
                        _mapController.fitCamera(
                          CameraFit.bounds(bounds: mainlandBounds, padding: const EdgeInsets.all(24)),
                        );
                        //=================== 変更
                      },
                    ),
                    _CatButton(
                      label: '26市',
                      selected: _category == '市',
                      onTap: () {
                        setState(() {
                          _category = '市';
                          _selected = null;
                        });
                        //=================== 変更
                        _mapController.fitCamera(
                          CameraFit.bounds(bounds: mainlandBounds, padding: const EdgeInsets.all(24)),
                        );
                        //=================== 変更
                      },
                    ),
                    _CatButton(
                      label: '町村',
                      selected: _category == '町村',
                      onTap: () {
                        setState(() {
                          _category = '町村';
                          _selected = null;
                        });
                        //=================== 変更
                        _mapController.fitCamera(
                          CameraFit.bounds(bounds: mainlandBounds, padding: const EdgeInsets.all(24)),
                        );
                        //=================== 変更
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final r = filtered[i];
                    final selected = identical(_selected, r);
                    return ChoiceChip(
                      selected: selected,
                      label: Text(r.name),
                      onSelected: (_) {
                        setState(() => _selected = r);
                        final b = LatLngBounds(LatLng(r.minLat, r.minLng), LatLng(r.maxLat, r.maxLng));
                        _mapController.fitCamera(CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(24)));
                      },
                    );
                  },
                ),
              ),
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: _center, initialZoom: 10),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.tokyo_list_map',
                    ),
                    //=================== 変更（背景＝本土のみ）
                    if (backgroundRows.isNotEmpty)
                      PolygonLayer(
                        polygons: backgroundRows
                            .expand((r) => _toPolygonsWithColors(r, const Color(0x22000000), const Color(0x33000000)))
                            .toList(),
                      ),
                    //=================== 変更
                    if (_selected != null) PolygonLayer(polygons: _toPolygons(_selected!)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Polygon> _toPolygons(MunicipalRow r) {
    final ps = <Polygon>[];
    for (final rings in r.polygons) {
      if (rings.isEmpty) continue;
      final outer = rings.first.map((p) => LatLng(p[1], p[0])).toList();
      final holes = <List<LatLng>>[];
      for (int i = 1; i < rings.length; i++) {
        holes.add(rings[i].map((p) => LatLng(p[1], p[0])).toList());
      }
      ps.add(
        Polygon(
          points: outer,
          holePointsList: holes.isEmpty ? null : holes,
          isFilled: true,
          color: const Color(0x22FF0000),
          borderColor: const Color(0xFFFF0000),
          borderStrokeWidth: 1.5,
        ),
      );
    }
    return ps;
  }

  List<Polygon> _toPolygonsWithColors(MunicipalRow r, Color fill, Color stroke) {
    final ps = <Polygon>[];
    for (final rings in r.polygons) {
      if (rings.isEmpty) continue;
      final outer = rings.first.map((p) => LatLng(p[1], p[0])).toList();
      final holes = <List<LatLng>>[];
      for (int i = 1; i < rings.length; i++) {
        holes.add(rings[i].map((p) => LatLng(p[1], p[0])).toList());
      }
      ps.add(
        Polygon(
          points: outer,
          holePointsList: holes.isEmpty ? null : holes,
          isFilled: true,
          color: fill,
          borderColor: stroke,
          borderStrokeWidth: 1.0,
        ),
      );
    }
    return ps;
  }

  List<MunicipalRow> _sortedByZOrder(List<MunicipalRow> list) {
    if (list.isEmpty) return list;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final m in list) {
      if (m.centroidLat < minLat) minLat = m.centroidLat;
      if (m.centroidLat > maxLat) maxLat = m.centroidLat;
      if (m.centroidLng < minLng) minLng = m.centroidLng;
      if (m.centroidLng > maxLng) maxLng = m.centroidLng;
    }
    int morton(double lat, double lng) {
      final nx = _normalize(lng, minLng, maxLng);
      final ny = _normalize(lat, minLat, maxLat);
      return _mortonKey16(nx, ny);
    }

    final out = List<MunicipalRow>.from(list);
    for (final m in out) {
      m.zKey = morton(m.centroidLat, m.centroidLng);
    }
    out.sort((a, b) {
      final ka = a.zKey ?? 0, kb = b.zKey ?? 0;
      if (ka != kb) return ka.compareTo(kb);
      return a.name.compareTo(b.name);
    });
    return out;
  }

  //=================== 変更（島嶼を緯度経度で除外：本土のみを true）
  bool _isMainland(MunicipalRow r) {
    if (r.centroidLat < 35.0) return false; // 南の島嶼を除外
    if (r.centroidLng > 140.5) return false; // 小笠原など東側の島嶼を除外
    return true;
  }

  //=================== 変更

  LatLngBounds _boundsOfAll(List<MunicipalRow> list, {List<MunicipalRow>? fallback}) {
    final src = list.isNotEmpty ? list : (fallback ?? list);
    double? minLat, minLng, maxLat, maxLng;
    for (final r in src) {
      minLat = (minLat == null) ? r.minLat : (r.minLat < minLat! ? r.minLat : minLat);
      maxLat = (maxLat == null) ? r.maxLat : (r.maxLat > maxLat! ? r.maxLat : maxLat);
      minLng = (minLng == null) ? r.minLng : (r.minLng < minLng! ? r.minLng : minLng);
      maxLng = (maxLng == null) ? r.maxLng : (r.maxLng > maxLng! ? r.maxLng : maxLng);
    }
    return LatLngBounds(LatLng(minLat ?? 0, minLng ?? 0), LatLng(maxLat ?? 0, maxLng ?? 0));
  }

  double _normalize(double v, double vmin, double vmax) {
    final d = (vmax - vmin);
    if (d == 0) return 0.5;
    return ((v - vmin) / d).clamp(0.0, 1.0);
  }

  int _mortonKey16(double normX, double normY) {
    int x = (normX * 65535).round();
    int y = (normY * 65535).round();
    return _interleave16(x) | (_interleave16(y) << 1);
  }

  int _interleave16(int n) {
    int x = n & 0xFFFF;
    x = (x | (x << 8)) & 0x00FF00FF;
    x = (x | (x << 4)) & 0x0F0F0F0F;
    x = (x | (x << 2)) & 0x33333333;
    x = (x | (x << 1)) & 0x55555555;
    return x;
  }
}

class _CatButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CatButton({required this.label, required this.selected, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.primary : Colors.black54;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(label),
    );
  }
}

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
    final polygons = <List<List<List<double>>>>[];
    double sumLat = 0, sumLng = 0;
    int ptCnt = 0;

    void addPoint(double lng, double lat) {
      count++;
      minLat = (minLat == null) ? lat : (lat < minLat! ? lat : minLat);
      maxLat = (maxLat == null) ? lat : (lat > maxLat! ? lat : maxLat);
      minLng = (minLng == null) ? lng : (lng < minLng! ? lng : minLng);
      maxLng = (maxLng == null) ? lng : (lng > maxLng! ? lng : maxLng);
      sumLat += lat;
      sumLng += lng;
      ptCnt++;
    }

    if (type == 'Polygon') {
      final rings = <List<List<double>>>[];
      for (final ring in (coords as List)) {
        final rr = <List<double>>[];
        for (final pt in (ring as List)) {
          final lng = (pt[0] as num).toDouble();
          final lat = (pt[1] as num).toDouble();
          addPoint(lng, lat);
          rr.add([lng, lat]);
        }
        rings.add(rr);
      }
      polygons.add(rings);
    } else if (type == 'MultiPolygon') {
      for (final poly in (coords as List)) {
        final rings = <List<List<double>>>[];
        for (final ring in (poly as List)) {
          final rr = <List<double>>[];
          for (final pt in (ring as List)) {
            final lng = (pt[0] as num).toDouble();
            final lat = (pt[1] as num).toDouble();
            addPoint(lng, lat);
            rr.add([lng, lat]);
          }
          rings.add(rr);
        }
        polygons.add(rings);
      }
    } else {
      continue;
    }

    final centroidLat = ptCnt == 0 ? 0.0 : (sumLat / ptCnt);
    final centroidLng = ptCnt == 0 ? 0.0 : (sumLng / ptCnt);

    rows.add(
      MunicipalRow(
        name,
        count,
        minLat: minLat ?? 0,
        minLng: minLng ?? 0,
        maxLat: maxLat ?? 0,
        maxLng: maxLng ?? 0,
        polygons: polygons,
        centroidLat: centroidLat,
        centroidLng: centroidLng,
      ),
    );
  }

  return rows;
}
