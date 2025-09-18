import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// ステップ1：
/// - assets/tokyo_municipal.geojson を読み込む
/// - Feature（各自治体）の名前と「頂点数（座標点の数）」を計算して、
///   ListViewに「<自治体名>  <頂点数>」で表示するだけの最小アプリ。

const String kAssetPath = 'assets/tokyo_municipal.geojson';

/// 表示用モデル
class MunicipalRow {
  final String name; // 例：杉並区
  final int vertexCount; // 頂点数（全ポリゴン・外周＋穴の点を合算）
  const MunicipalRow(this.name, this.vertexCount);
}

void main() {
  runApp(const Step1App());
}

class Step1App extends StatelessWidget {
  const Step1App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step1: List Tokyo Municipalities',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF5566EE)),
      home: const Step1Page(),
    );
  }
}

class Step1Page extends StatefulWidget {
  const Step1Page({super.key});

  @override
  State<Step1Page> createState() => _Step1PageState();
}

class _Step1PageState extends State<Step1Page> {
  late Future<List<MunicipalRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadRows();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ステップ1：GeoJSON→リスト表示')),
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
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rows[i];
              return ListTile(title: Text(r.name), trailing: Text(r.vertexCount.toString()));
            },
          );
        },
      ),
    );
  }
}

/// GeoJSON を読み込み、
/// - 自治体名（通常 N03_004）
/// - 頂点数（Polygon / MultiPolygon の [lng,lat] 点の総数）
/// の一覧を返す。
Future<List<MunicipalRow>> _loadRows() async {
  final text = await rootBundle.loadString(kAssetPath);
  final data = jsonDecode(text);

  // FeatureCollection 前提（Feature単体でも動くようにケア）
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

    // 市区町村名（通常は N03_004。なければ name を見る）
    final name = (props['N03_004'] ?? props['name'] ?? '') as String;
    if (name.isEmpty) continue;

    final type = geom['type'] as String?;
    final coords = geom['coordinates'];

    int count = 0;
    if (type == 'Polygon') {
      // [rings][points][lng/lat]
      for (final ring in (coords as List)) {
        count += (ring as List).length;
      }
    } else if (type == 'MultiPolygon') {
      // [polygons][rings][points][lng/lat]
      for (final poly in (coords as List)) {
        for (final ring in (poly as List)) {
          count += (ring as List).length;
        }
      }
    } else {
      // Point / MultiLineString などは今回は対象外
      continue;
    }

    rows.add(MunicipalRow(name, count));
  }

  // 表示順：名前昇順（必要なら別の基準に変更可）
  rows.sort((a, b) => a.name.compareTo(b.name));
  return rows;
}
