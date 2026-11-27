import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../core/api.dart';
import '../core/goong.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'preorder_support.dart' show normalizeOrderQuery;

LatLng? kioskPoint(Json row) {
  final lat = row['latitude'], lng = row['longitude'];
  if (lat is! num ||
      lng is! num ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat < -90 ||
      lat > 90 ||
      lng < -180 ||
      lng > 180) {
    return null;
  }
  return LatLng(lat.toDouble(), lng.toDouble());
}

int kioskPriority(Json row) => switch (row['status']) {
  'ONLINE' || 'ACTIVE' => 0,
  'MAINTENANCE' => 1,
  _ => 2,
};
List<Json> sortedCustomerKiosks(
  List<Json> rows, {
  String query = '',
  String status = '',
  LatLng? origin,
}) {
  final result = rows
      .where(
        (row) =>
            (status.isEmpty || row['status'] == status) &&
            normalizeOrderQuery(
              '${row['name']} ${row['code']} ${row['address']} ${row['region']}',
            ).contains(normalizeOrderQuery(query)),
      )
      .toList();
  double distance(Json row) {
    final point = kioskPoint(row);
    return point == null || origin == null
        ? double.infinity
        : Geolocator.distanceBetween(
            origin.latitude,
            origin.longitude,
            point.latitude,
            point.longitude,
          );
  }

  result.sort((a, b) {
    final priority = kioskPriority(a).compareTo(kioskPriority(b));
    if (priority != 0) return priority;
    if (origin != null) {
      final d = distance(a).compareTo(distance(b));
      if (d != 0) return d;
    }
    return valueOf(a, 'name').compareTo(valueOf(b, 'name'));
  });
  return result;
}

class CustomerKiosksPage extends StatefulWidget {
  const CustomerKiosksPage(
    this.api, {
    this.locate,
    this.showMap = true,
    super.key,
  });
  final ApiClient api;
  final Future<LatLng> Function()? locate;
  final bool showMap;
  @override
  State<CustomerKiosksPage> createState() => _CustomerKiosksPageState();
}

class _CustomerKiosksPageState extends State<CustomerKiosksPage> {
  String query = '', status = '';
  LatLng? origin;
  Json? selected;
  bool locating = false;
  String? error;
  MapLibreMapController? map;
  GoongConfig? config;
  bool styleReady = false;
  List<Json> markers = [];
  @override
  void initState() {
    super.initState();
    if (widget.showMap) unawaited(loadConfig());
  }

  Future<void> loadConfig() async {
    final value = await GoongConfig.load();
    if (mounted) setState(() => config = value);
  }

  Future<void> nearest() async {
    if (locating) return;
    setState(() {
      locating = true;
      error = null;
    });
    try {
      LatLng point;
      if (widget.locate != null) {
        point = await widget.locate!();
      } else {
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw const ApiError(
            400,
            'Bật vị trí trên thiết bị để tìm kiosk gần bạn.',
          );
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw const ApiError(
            400,
            'Chưa có quyền vị trí. Bạn vẫn có thể tìm theo tên hoặc địa chỉ.',
          );
        }
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          ),
        );
        point = LatLng(position.latitude, position.longitude);
      }
      if (!mounted) return;
      setState(() => origin = point);
      if (map != null) {
        await map!.animateCamera(CameraUpdate.newLatLngZoom(point, 12));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> draw() async {
    if (!styleReady || map == null) return;
    try {
      await map!.clearCircles();
      for (final row in markers) {
        if (!mounted) return;
        final point = kioskPoint(row);
        if (point == null) continue;
        await map!.addCircle(
          CircleOptions(
            geometry: point,
            circleRadius: 9,
            circleColor: kioskPriority(row) == 0
                ? '#196447'
                : kioskPriority(row) == 1
                ? '#B57905'
                : '#B53D3D',
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ),
          {'id': row['id']},
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Chưa tải được điểm trên bản đồ. Bạn vẫn có thể chọn kiosk bên dưới.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Vị trí kiosk',
    load: () => widget.api.get('/api/kiosks'),
    builder: (context, data, state) {
      final rows = sortedCustomerKiosks(
        itemsOf(data),
        query: query,
        status: status,
        origin: origin,
      );
      final signature = rows
          .map(
            (row) =>
                '${row['id']}:${row['status']}:${row['latitude']}:${row['longitude']}',
          )
          .join('|');
      if (markers
              .map(
                (row) =>
                    '${row['id']}:${row['status']}:${row['latitude']}:${row['longitude']}',
              )
              .join('|') !=
          signature) {
        markers = rows;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(draw());
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Tìm kiosk',
              hintText: 'Tên, mã hoặc địa chỉ',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Trạng thái'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Tất cả')),
              DropdownMenuItem(value: 'ONLINE', child: Text('Trực tuyến')),
              DropdownMenuItem(value: 'MAINTENANCE', child: Text('Bảo trì')),
              DropdownMenuItem(value: 'OFFLINE', child: Text('Ngoại tuyến')),
            ],
            onChanged: (value) => setState(() => status = value ?? ''),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: locating ? null : nearest,
            icon: const Icon(Icons.my_location),
            label: Text(locating ? 'Đang tìm vị trí…' : 'Tìm kiosk gần tôi'),
          ),
          const SizedBox(height: 16),
          if (error != null) InfoBox(error!, warning: true),
          if (widget.showMap &&
              config != null &&
              config!.mapTilesKey.isNotEmpty) ...[
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: MapLibreMap(
                  styleString: config!.styleUrl,
                  initialCameraPosition: CameraPosition(
                    target:
                        rows.map(kioskPoint).whereType<LatLng>().firstOrNull ??
                        const LatLng(16.05, 108.2),
                    zoom: rows.any((row) => kioskPoint(row) != null) ? 10 : 4,
                  ),
                  onMapCreated: (controller) {
                    map = controller;
                    controller.onCircleTapped.add((circle) {
                      final row = markers
                          .where((r) => r['id'] == circle.data?['id'])
                          .firstOrNull;
                      if (mounted) setState(() => selected = row);
                    });
                  },
                  onStyleLoadedCallback: () {
                    styleReady = true;
                    unawaited(draw());
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.showMap && config != null && config!.mapTilesKey.isEmpty)
            const InfoBox(
              'Bản đồ chưa được cấu hình. Bạn vẫn có thể xem kiosk và chỉ đường.',
            ),
          if (rows.isEmpty) const InfoBox('Không có kiosk phù hợp.'),
          for (final row in [
            if (selected != null && rows.any((r) => r['id'] == selected!['id']))
              rows.firstWhere((r) => r['id'] == selected!['id']),
            ...rows.where((r) => r['id'] != selected?['id']),
          ])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      valueOf(row, 'name'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(valueOf(row, 'address')),
                    Text(
                      kioskPriority(row) == 0
                          ? 'Trực tuyến'
                          : kioskPriority(row) == 1
                          ? 'Đang bảo trì'
                          : 'Ngoại tuyến',
                      style: TextStyle(
                        color: kioskPriority(row) == 0
                            ? forest
                            : kioskPriority(row) == 1
                            ? const Color(0xFF966408)
                            : Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (origin != null && kioskPoint(row) != null)
                      Text(
                        '${(Geolocator.distanceBetween(origin!.latitude, origin!.longitude, kioskPoint(row)!.latitude, kioskPoint(row)!.longitude) / 1000).toStringAsFixed(1)} km',
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: kioskPoint(row) == null
                              ? null
                              : () async {
                                  setState(() => selected = row);
                                  if (map != null) {
                                    await map!.animateCamera(
                                      CameraUpdate.newLatLngZoom(
                                        kioskPoint(row)!,
                                        15,
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.place_outlined),
                          label: const Text('Xem vị trí'),
                        ),
                        TextButton.icon(
                          onPressed: kioskPoint(row) == null
                              ? null
                              : () async {
                                  try {
                                    final p = kioskPoint(row)!;
                                    await openSafeLink(
                                      'https://www.google.com/maps/dir/?api=1&destination=${p.latitude},${p.longitude}',
                                    );
                                  } catch (e) {
                                    if (context.mounted) message(context, '$e');
                                  }
                                },
                          icon: const Icon(Icons.directions_outlined),
                          label: const Text('Chỉ đường'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
