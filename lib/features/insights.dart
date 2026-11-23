import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

DateTime _today() {
  final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
  return DateTime(vn.year, vn.month, vn.day);
}

String _date(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String _display(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

String forecastWarning(String message) {
  if (message.startsWith(
    'Forecasts represent observed sales/invoice frequency',
  )) {
    return 'Dự báo chỉ để tham khảo, có thể thấp hơn nhu cầu thực tế nếu từng hết hàng.';
  }
  if (message.startsWith('Annual seasonality is not validated')) {
    return 'Dự báo chưa được kiểm chứng theo mùa hằng năm.';
  }
  if (message.startsWith('Some products have insufficient history')) {
    return 'Cần ít nhất 70 ngày dữ liệu và 10 ngày có đơn để dự báo.';
  }
  if (message.startsWith('Poisson regression')) {
    return 'Một số mẫu hoa đang dùng cách ước tính theo ngày trong tuần.';
  }
  return message;
}

class InsightsPage extends StatefulWidget {
  const InsightsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late DateTime from = _today().subtract(const Duration(days: 365));
  late DateTime to = _today();
  late DateTime target = DateTime(to.year, to.month + 1);
  Json? sales, forecast;
  Object? salesError, forecastError;
  bool salesLoading = true, forecastLoading = false;
  int salesEpoch = 0, forecastEpoch = 0, tab = 0;
  String get base => '/api/sellers/${widget.session.sellerId}/ai';

  DateTime get minMonth => DateTime(to.year, to.month + 1);
  DateTime get maxMonth {
    final end = to.add(const Duration(days: 366));
    return DateTime(
      end.year > 2100 ? 2100 : end.year,
      end.year > 2100 ? 12 : end.month,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(loadSales());
  }

  Future<void> loadSales() async {
    final epoch = ++salesEpoch;
    setState(() {
      salesLoading = true;
      salesError = null;
    });
    try {
      final result = objectOf(
        await widget.api.get(
          '$base/seasonal-sales?from=${_date(from)}&to=${_date(to)}',
        ),
      );
      if (mounted && epoch == salesEpoch) setState(() => sales = result);
    } catch (e) {
      if (mounted && epoch == salesEpoch) setState(() => salesError = e);
    } finally {
      if (mounted && epoch == salesEpoch) setState(() => salesLoading = false);
    }
  }

  Future<void> loadForecast() async {
    if (forecastLoading) return;
    final epoch = ++forecastEpoch;
    setState(() {
      forecastLoading = true;
      forecastError = null;
      forecast = null;
    });
    try {
      final result = objectOf(
        await widget.api.post('$base/seasonal-forecast', {
          'year': target.year,
          'month': target.month,
          'historyFrom': _date(from),
          'historyTo': _date(to),
        }),
      );
      if (mounted && epoch == forecastEpoch) setState(() => forecast = result);
    } catch (e) {
      if (mounted && epoch == forecastEpoch) setState(() => forecastError = e);
    } finally {
      if (mounted && epoch == forecastEpoch) {
        setState(() => forecastLoading = false);
      }
    }
  }

  void clearForecast() {
    forecastEpoch++;
    forecast = null;
    forecastError = null;
    forecastLoading = false;
  }

  Future<void> pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: from, end: to),
      firstDate: DateTime(2000),
      lastDate: _today(),
      helpText: 'Khoảng ngày thống kê',
      saveText: 'Áp dụng',
    );
    if (range == null || !mounted) return;
    if (range.end.difference(range.start).inDays + 1 > 1096) {
      message(context, 'Chọn khoảng ngày không quá 3 năm.');
      return;
    }
    if (range.start == from && range.end == to) return;
    setState(() {
      from = range.start;
      to = range.end;
      clearForecast();
      if (target.isBefore(minMonth) || target.isAfter(maxMonth)) {
        target = minMonth;
      }
    });
    await loadSales();
  }

  Future<void> pickMonth() async {
    var chosen = target;
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final months =
              [for (var m = 1; m <= 12; m++) DateTime(chosen.year, m)]
                  .where((m) => !m.isBefore(minMonth) && !m.isAfter(maxMonth))
                  .toList();
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tháng dự báo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: ValueKey(chosen.year),
                  initialValue: chosen.year,
                  decoration: const InputDecoration(labelText: 'Năm'),
                  items: [
                    for (var y = minMonth.year; y <= maxMonth.year; y++)
                      DropdownMenuItem(value: y, child: Text('$y')),
                  ],
                  onChanged: (year) {
                    if (year == null) return;
                    update(() {
                      chosen = DateTime(year, chosen.month);
                      if (chosen.isBefore(minMonth)) chosen = minMonth;
                      if (chosen.isAfter(maxMonth)) chosen = maxMonth;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey(chosen),
                  initialValue: chosen.month,
                  decoration: const InputDecoration(labelText: 'Tháng'),
                  items: [
                    for (final m in months)
                      DropdownMenuItem(
                        value: m.month,
                        child: Text('Tháng ${m.month}'),
                      ),
                  ],
                  onChanged: (month) {
                    if (month != null) {
                      update(() => chosen = DateTime(chosen.year, month));
                    }
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context, chosen),
                  child: const Text('Chọn tháng'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (result == null || !mounted || result == target) return;
    setState(() {
      target = result;
      clearForecast();
    });
  }

  Widget card(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget loading() => const SizedBox(
    height: 180,
    child: Center(child: CircularProgressIndicator()),
  );

  Widget failure(Object error, VoidCallback retry) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Text('$error', style: const TextStyle(color: Color(0xFFB42318))),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: retry, child: const Text('Thử lại')),
      ],
    ),
  );

  Widget metric(String label, dynamic value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
        ),
        const SizedBox(height: 5),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: forest,
          ),
        ),
      ],
    ),
  );

  Widget salesView() {
    if (salesLoading) return loading();
    if (salesError != null) return failure(salesError!, loadSales);
    final products = itemsOf(sales?['products'] ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card([
          Row(
            children: [
              metric('Hóa đơn', sales?['totalInvoices'] ?? 0),
              metric('Số bó đã bán', sales?['totalUnits'] ?? 0),
            ],
          ),
        ]),
        if (products.isEmpty)
          card([const Text('Chưa có giao dịch trong khoảng ngày này.')]),
        if (products.isNotEmpty)
          card([
            const Text(
              'Theo mẫu hoa',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            for (final product in products)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valueOf(product, 'name'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${product['totalInvoices'] ?? 0} hóa đơn · ${product['totalUnits'] ?? 0} bó',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF617568),
                      ),
                    ),
                  ],
                ),
              ),
          ]),
      ],
    );
  }

  Widget forecastView() {
    final warnings = (forecast?['warnings'] as List? ?? [])
        .map((w) => forecastWarning('$w'))
        .toSet();
    final products = itemsOf(forecast?['products'] ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card([
          const Text(
            'Tháng dự báo',
            style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickMonth,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(DateFormat('MM/yyyy').format(target)),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: forecastLoading ? null : loadForecast,
                child: const Text('Xem dự báo'),
              ),
            ],
          ),
        ]),
        if (forecastLoading)
          loading()
        else if (forecastError != null)
          failure(forecastError!, loadForecast)
        else if (forecast == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Chọn tháng để xem số bó dự kiến.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF617568)),
            ),
          )
        else ...[
          if (warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        warning,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: Color(0xFF925B0A),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (products.isEmpty)
            card([const Text('Chưa có mẫu hoa để dự báo.')]),
          for (final product in products)
            card([
              StatusHeading(
                title: Text(
                  valueOf(product, 'name'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: forest,
                  ),
                ),
                status: Text(
                  product['forecastUnits'] == null
                      ? 'Chưa đủ dữ liệu'
                      : 'Ước tính',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF925B0A),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (product['forecastUnits'] != null)
                Text(
                  '${NumberFormat('0.##', 'vi').format(product['forecastUnits'])} bó',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: forest,
                  ),
                ),
              Text(
                'Đã bán ${product['observedUnits'] ?? 0} bó · ${product['observedInvoiceCount'] ?? 0} hóa đơn',
                style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
              ),
              if (valueOf(product, 'explanation', '').isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text(
                    'Chi tiết dự báo',
                    style: TextStyle(fontSize: 13, color: forest),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        valueOf(product, 'explanation'),
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],
                ),
            ]),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: tab == 0
        ? loadSales
        : () async {
            if (forecast != null || forecastError != null) await loadForecast();
          },
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        card([
          const Text(
            'Khoảng ngày thống kê',
            style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: pickRange,
            icon: const Icon(Icons.date_range_outlined, size: 18),
            label: Text(
              '${_display(from)} – ${_display(to)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ]),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Doanh số')),
            ButtonSegment(value: 1, label: Text('Dự báo')),
          ],
          selected: {tab},
          showSelectedIcon: false,
          onSelectionChanged: (values) => setState(() => tab = values.first),
        ),
        const SizedBox(height: 14),
        if (tab == 0) salesView() else forecastView(),
      ],
    ),
  );
}
