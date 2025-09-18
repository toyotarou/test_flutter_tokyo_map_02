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

          final backgroundRows = rows.where(_isMainland).toList();
          final mainlandBounds = _boundsOfAll(backgroundRows, fallback: rows);

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
                        _mapController.fitCamera(
                          CameraFit.bounds(bounds: mainlandBounds, padding: const EdgeInsets.all(24)),
                        );
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
                        _mapController.fitCamera(
                          CameraFit.bounds(bounds: mainlandBounds, padding: const EdgeInsets.all(24)),
                        );
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
                        _mapController.fitCamera(
                          CameraFit.bounds(bounds: mainlandBounds, padding: const EdgeInsets.all(24)),
                        );
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
                    if (backgroundRows.isNotEmpty)
                      PolygonLayer(
                        polygons: backgroundRows
                            .expand((r) => _toPolygonsWithColors(r, const Color(0x22000000), const Color(0x33000000)))
                            .toList(),
                      ),
                    if (_selected != null) PolygonLayer(polygons: _toPolygons(_selected!)),
                    if (_selected != null)
                      MarkerLayer(
                        markers:
                            _stationsIn(_selected!).map((s) {
                                return Marker(
                                  point: LatLng(s.lat, s.lng),
                                  //=================== 変更
                                  width: 168,
                                  height: 52,
                                  //=================== 変更
                                  alignment: Alignment.topCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.92),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.black26),
                                        ),
                                        child: const DefaultTextStyle(
                                          style: TextStyle(fontSize: 11, color: Colors.black),
                                          child: Text('', maxLines: 1),
                                        ),
                                      ),
                                      //=================== 変更
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                                        ),
                                      ),
                                      //=================== 変更
                                    ],
                                  ),
                                );
                              }).toList()
                              // ラベルは上の DefaultTextStyle を再利用して描く
                              ..asMap().forEach((i, m) {
                                // これはダミー。実際の駅名は別マーカーとして重ねる
                              }),
                      ),
                    if (_selected != null)
                      MarkerLayer(
                        markers: _stationsIn(_selected!).map((s) {
                          return Marker(
                            point: LatLng(s.lat, s.lng),
                            width: 168,
                            height: 52,
                            alignment: Alignment.topCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.92),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.black26),
                                  ),
                                  child: Text(s.name, style: const TextStyle(fontSize: 11)),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
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

  bool _isMainland(MunicipalRow r) {
    if (r.centroidLat < 35.0) return false;
    if (r.centroidLng > 140.5) return false;
    return true;
  }

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

  static const List<_Station> _yamanote = [
    _Station('東京', 35.68124, 139.76712),
    _Station('有楽町', 35.67507, 139.76333),
    _Station('新橋', 35.66629, 139.75865),
    _Station('浜松町', 35.65539, 139.75795),
    _Station('田町', 35.64574, 139.74758),
    _Station('高輪ゲートウェイ', 35.63594, 139.74044),
    _Station('品川', 35.62847, 139.73876),
    _Station('大崎', 35.61970, 139.72853),
    _Station('五反田', 35.62648, 139.72316),
    _Station('目黒', 35.63395, 139.71541),
    _Station('恵比寿', 35.64669, 139.71010),
    _Station('渋谷', 35.65803, 139.70164),
    _Station('原宿', 35.67016, 139.70268),
    _Station('代々木', 35.68306, 139.70204),
    _Station('新宿', 35.69092, 139.70026),
    _Station('新大久保', 35.70130, 139.70045),
    _Station('高田馬場', 35.71227, 139.70363),
    _Station('目白', 35.72129, 139.70663),
    _Station('池袋', 35.72892, 139.71004),
    _Station('大塚', 35.73167, 139.72935),
    _Station('巣鴨', 35.73344, 139.73938),
    _Station('駒込', 35.73656, 139.74696),
    _Station('田端', 35.73810, 139.76158),
    _Station('西日暮里', 35.73283, 139.76684),
    _Station('日暮里', 35.72785, 139.77033),
    _Station('鶯谷', 35.72027, 139.77764),
    _Station('上野', 35.71377, 139.77727),
    _Station('御徒町', 35.70726, 139.77450),
    _Station('秋葉原', 35.69847, 139.77313),
    _Station('神田', 35.69166, 139.77088),
  ];

  List<_Station> _stationsIn(MunicipalRow r) {
    return _yamanote.where((s) => _pointInMunicipality(s.lat, s.lng, r)).toList();
  }

  bool _pointInMunicipality(double lat, double lng, MunicipalRow r) {
    for (final rings in r.polygons) {
      if (rings.isEmpty) continue;
      final outer = rings.first;
      if (_pointInRing(lat, lng, outer)) {
        bool inHole = false;
        for (int i = 1; i < rings.length; i++) {
          if (_pointInRing(lat, lng, rings[i])) {
            inHole = true;
            break;
          }
        }
        if (!inHole) return true;
      }
    }
    return false;
  }

  bool _pointInRing(double lat, double lng, List<List<double>> ring) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i][1], yi = ring[i][0];
      final xj = ring[j][1], yj = ring[j][0];
      final intersect =
          ((xi > lat) != (xj > lat)) && (lng < (yj - yi) * (lat - xi) / ((xj - xi) == 0 ? 1e-12 : (xj - xi)) + yi);
      if (intersect) inside = !inside;
    }
    return inside;
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

class _Station {
  final String name;
  final double lat;
  final double lng;

  const _Station(this.name, this.lat, this.lng);
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
