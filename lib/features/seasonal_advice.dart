import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

class SeasonalAdvicePanel extends StatefulWidget {
  const SeasonalAdvicePanel(this.api, this.path, {super.key});
  final ApiClient api;
  final String path;
  @override
  State<SeasonalAdvicePanel> createState() => _SeasonalAdvicePanelState();
}

class _SeasonalAdvicePanelState extends State<SeasonalAdvicePanel> {
  Future<List<Json>> load() async => itemsOf(await widget.api.get(widget.path));
  late Future<List<Json>> future = load();
  @override
  void didUpdateWidget(SeasonalAdvicePanel old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.api != widget.api) {
      future = load();
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Gợi ý bán theo dịp',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          FutureBuilder<List<Json>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    Text('${snapshot.error}'),
                    TextButton(
                      onPressed: () => setState(() {
                        future = load();
                      }),
                      child: const Text('Thử lại gợi ý'),
                    ),
                  ],
                );
              }
              final rows = snapshot.data ?? <Json>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows.isEmpty) const Text('Chưa có gợi ý cho kỳ đã chọn.'),
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            valueOf(row, 'occasion'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (row['date'] != null)
                            Text(
                              '${row['date']}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          Text(valueOf(row, 'offer')),
                          Text(valueOf(row, 'nextStep')),
                          if ((row['matchingProducts'] as List? ?? [])
                              .isNotEmpty)
                            Text(
                              (row['matchingProducts'] as List).join(' · '),
                              style: const TextStyle(color: forest),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
