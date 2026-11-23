import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/goong.dart';
import '../core/models.dart';
import 'common.dart';

typedef KioskPoint = ({double latitude, double longitude});
typedef KioskLocation = ({KioskPoint point, String? address});

class GoongSuggestionPanel extends StatelessWidget {
  const GoongSuggestionPanel({
    required this.predictions,
    required this.loading,
    required this.empty,
    required this.onSelect,
    this.error,
    this.onManualMap,
    this.maxListHeight = 220,
    super.key,
  });

  final List<Json> predictions;
  final bool loading;
  final bool empty;
  final String? error;
  final ValueChanged<Json> onSelect;
  final VoidCallback? onManualMap;
  final double maxListHeight;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFD4E0D4)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Đang tìm địa chỉ gợi ý…',
                    style: TextStyle(fontSize: 13, color: Color(0xFF617568)),
                  ),
                ),
              ],
            ),
          )
        else if (error != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: Color(0xFFB42318),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFB42318),
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (empty)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Không tìm thấy địa chỉ phù hợp. Bạn có thể chọn trực tiếp trên bản đồ.',
              style: TextStyle(fontSize: 13, color: Color(0xFF617568)),
            ),
          )
        else if (predictions.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: predictions.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xFFEAEFEA)),
              itemBuilder: (context, index) {
                final item = predictions[index];
                final parsed = parseGoongSuggestion(item);
                return InkWell(
                  onTap: () => onSelect(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.location_on_outlined,
                            size: 18,
                            color: forest,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                parsed.mainText,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F3428),
                                ),
                              ),
                              if (parsed.secondaryText.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  parsed.secondaryText,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF617568),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (onManualMap != null && !loading) ...[
          const Divider(height: 1, color: Color(0xFFEAEFEA)),
          InkWell(
            onTap: onManualMap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(Icons.pin_drop_outlined, size: 18, color: forest),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ghim thủ công trên bản đồ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: forest,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class KioskLocationPicker extends StatefulWidget {
  const KioskLocationPicker({
    this.initial,
    this.initialAddress = '',
    this.placesClient,
    this.configOverride,
    super.key,
  });
  final KioskPoint? initial;
  final String initialAddress;
  final GoongPlacesClient? placesClient;
  final GoongConfig? configOverride;
  @override
  State<KioskLocationPicker> createState() => _KioskLocationPickerState();
}

class _KioskLocationPickerState extends State<KioskLocationPicker> {
  late final search = TextEditingController(text: widget.initialAddress);
  late KioskPoint point =
      widget.initial ?? (latitude: 10.7769, longitude: 106.7009);
  MapLibreMapController? controller;
  GoongConfig? config;
  GoongPlacesClient? places;
  List<Json> predictions = [];
  Timer? debounce, styleTimeout;
  int requestId = 0, mapVersion = 0;
  bool loading = true,
      searching = false,
      selecting = false,
      searchEmpty = false,
      mapReady = false;
  late bool selected = widget.initial != null;
  bool moved = false;
  String? selectedAddress, searchError, mapError;

  @override
  void initState() {
    super.initState();
    unawaited(loadConfig());
  }

  Future<void> loadConfig() async {
    final value = widget.configOverride ?? await GoongConfig.load();
    if (!mounted) return;
    setState(() {
      config = value;
      places = widget.placesClient ?? GoongPlacesClient(value.apiKey);
      loading = false;
    });
    if (value.mapTilesKey.isNotEmpty) armTimeout();
    if (widget.initial == null && search.text.trim().length >= 3) {
      lookup(search.text);
    }
  }

  void armTimeout() {
    styleTimeout?.cancel();
    styleTimeout = Timer(const Duration(seconds: 25), () {
      if (mounted && !mapReady) {
        setState(
          () => mapError =
              'Chưa tải được bản đồ Goong. Kiểm tra mạng hoặc thử lại.',
        );
      }
    });
  }

  void _clearSearch() {
    debounce?.cancel();
    requestId++;
    search.clear();
    setState(() {
      predictions = [];
      searching = false;
      selecting = false;
      searchEmpty = false;
      searchError = null;
      moved = false;
      selected = false;
      selectedAddress = null;
    });
  }

  void lookup(String query) {
    debounce?.cancel();
    final id = ++requestId;
    setState(() {
      predictions = [];
      searching = false;
      selecting = false;
      searchEmpty = false;
      moved = false;
      searchError = null;
      selected = false;
      selectedAddress = null;
    });
    if (query.trim().length < 3 || places == null) return;
    debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || id != requestId) return;
      setState(() => searching = true);
      try {
        final result = await places!.suggestions(query);
        if (mounted && id == requestId) {
          setState(() {
            predictions = result;
            searchEmpty = result.isEmpty;
          });
        }
      } catch (e) {
        if (mounted && id == requestId) setState(() => searchError = '$e');
      } finally {
        if (mounted && id == requestId) setState(() => searching = false);
      }
    });
  }

  Future<void> choose(Json prediction) async {
    debounce?.cancel();
    final id = ++requestId;
    setState(() {
      selecting = true;
      selected = false;
      predictions = [];
      searchEmpty = false;
      searchError = null;
    });
    try {
      final place = await places!.detail('${prediction['place_id']}');
      if (!mounted || id != requestId) return;
      final address = place.address.isEmpty
          ? valueOf(prediction, 'description', search.text)
          : place.address;
      setState(() {
        point = (latitude: place.latitude, longitude: place.longitude);
        selected = true;
        selectedAddress = address;
        search.text = address;
      });
      FocusScope.of(context).unfocus();
      await controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(point.latitude, point.longitude), 16),
      );
    } catch (e) {
      if (mounted && id == requestId) setState(() => searchError = '$e');
    } finally {
      if (mounted && id == requestId) setState(() => selecting = false);
    }
  }

  @override
  void dispose() {
    requestId++;
    debounce?.cancel();
    styleTimeout?.cancel();
    if (widget.placesClient == null) places?.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSuggestions =
        searching ||
        searchEmpty ||
        searchError != null ||
        predictions.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Vị trí lắp đặt')),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: search,
                          onChanged: lookup,
                          decoration: InputDecoration(
                            hintText: 'Tìm địa chỉ lắp đặt',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: searching || selecting
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : search.text.isNotEmpty
                                ? IconButton(
                                    tooltip: 'Xóa địa chỉ',
                                    onPressed: _clearSearch,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        if (showSuggestions)
                          GoongSuggestionPanel(
                            predictions: predictions,
                            loading: searching,
                            empty: searchEmpty,
                            error: searchError,
                            onSelect: choose,
                          ),
                      ],
                    ),
                  ),
                  if (mapError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        mapError!,
                        style: const TextStyle(
                          color: Color(0xFFB42318),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Expanded(
                    child: config!.mapTilesKey.isEmpty
                        ? const Center(
                            child: Text(
                              'Chưa cấu hình bản đồ Goong.',
                              style: TextStyle(color: Color(0xFFB42318)),
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              MapLibreMap(
                                key: ValueKey(mapVersion),
                                styleString: config!.styleUrl,
                                initialCameraPosition: CameraPosition(
                                  target: LatLng(
                                    point.latitude,
                                    point.longitude,
                                  ),
                                  zoom: selected ? 16 : 12,
                                ),
                                trackCameraPosition: true,
                                rotateGesturesEnabled: false,
                                tiltGesturesEnabled: false,
                                onMapCreated: (value) => controller = value,
                                onStyleLoadedCallback: () {
                                  styleTimeout?.cancel();
                                  if (mounted) {
                                    setState(() {
                                      mapReady = true;
                                      mapError = null;
                                    });
                                  }
                                },
                                onCameraMoveStarted: (reason) {
                                  moved = reason == CameraMoveReason.gesture;
                                  if (moved && mounted) {
                                    requestId++;
                                    debounce?.cancel();
                                    setState(() {
                                      predictions = [];
                                      searching = false;
                                      selecting = false;
                                      searchEmpty = false;
                                      searchError = null;
                                    });
                                  }
                                },
                                onCameraIdle: () {
                                  if (!moved ||
                                      !mapReady ||
                                      controller?.cameraPosition == null ||
                                      !mounted) {
                                    return;
                                  }
                                  final target =
                                      controller!.cameraPosition!.target;
                                  setState(() {
                                    point = (
                                      latitude: target.latitude,
                                      longitude: target.longitude,
                                    );
                                    selected = true;
                                    moved = false;
                                  });
                                },
                                onMapClick: (_, target) async {
                                  if (!mapReady) return;
                                  requestId++;
                                  debounce?.cancel();
                                  setState(() {
                                    point = (
                                      latitude: target.latitude,
                                      longitude: target.longitude,
                                    );
                                    selected = true;
                                    predictions = [];
                                    searching = false;
                                    selecting = false;
                                    searchEmpty = false;
                                    searchError = null;
                                  });
                                  await controller?.animateCamera(
                                    CameraUpdate.newLatLng(target),
                                  );
                                },
                              ),
                              if (mapReady)
                                const IgnorePointer(
                                  child: Center(
                                    child: Padding(
                                      padding: EdgeInsets.only(bottom: 48),
                                      child: Icon(
                                        Icons.location_pin,
                                        size: 48,
                                        color: Color(0xFFB42318),
                                      ),
                                    ),
                                  ),
                                ),
                              if (!mapReady)
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              const Positioned(
                                bottom: 0,
                                right: 0,
                                child: ColoredBox(
                                  color: Colors.white,
                                  child: Padding(
                                    padding: EdgeInsets.all(5),
                                    child: Text(
                                      '© Goong Maps · MapLibre',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Kéo bản đồ để chỉnh ghim đúng điểm lắp đặt.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF617568),
                          ),
                        ),
                        if (!mapReady && config!.mapTilesKey.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() {
                              mapVersion++;
                              mapError = null;
                              armTimeout();
                            }),
                            child: const Text('Tải lại bản đồ'),
                          ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed:
                              !selected || !mapReady || selecting || searching
                              ? null
                              : () => Navigator.pop<KioskLocation>(context, (
                                  point: point,
                                  address:
                                      selectedAddress ?? search.text.trim(),
                                )),
                          child: const Text('Chọn vị trí này'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
