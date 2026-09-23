import 'package:flutter/material.dart';

import 'api_client.dart';
import 'time_format.dart';

// Opened by tapping a device card: the health score with its per-component
// breakdown, fetched from GET /devices/:id/score (computed on request by
// backend/src/lib/scoring.js). Being upfront about which parts are measured
// and which are placeholders is the point of this screen.
class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.title, required this.device});

  final String title;
  final Map<String, dynamic> device;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  Map<String, dynamic>? _score;
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _summary;
  bool _summaryLoading = false;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final score = await ApiClient.instance.deviceScore(widget.device['id'] as String);
      setState(() => _score = score);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
    // Started after the score is on screen, so the slower model call never
    // holds the score back.
    if (_score != null) _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final summary = await ApiClient.instance.deviceSummary(widget.device['id'] as String);
      setState(() => _summary = summary);
    } catch (e) {
      setState(() => _summaryError = e.toString());
    } finally {
      setState(() => _summaryLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!_loading && _error == null && _score == null)
              const Text('No recent snapshots yet - the score appears after this device syncs.'),
            if (_score != null) ..._scoreView(_score!),
          ],
        ),
      ),
    );
  }

  List<Widget> _scoreView(Map<String, dynamic> score) {
    final theme = Theme.of(context);
    final components = (score['components'] as List).cast<Map<String, dynamic>>();
    final notices = (score['notices'] as List).cast<String>();
    final basedOn = score['basedOn'] as Map<String, dynamic>;
    final includesPlaceholder = score['includesPlaceholder'] == true;

    return [
      Center(
        child: Column(
          children: [
            Text('${score['total'] ?? '-'}', style: theme.textTheme.displayLarge),
            Text('out of 100', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      if (includesPlaceholder) ...[
        const SizedBox(height: 12),
        _banner(
          icon: Icons.info_outline,
          text: 'This score includes a placeholder. Part of it is not measured from your usage yet - see Charging habits below.',
        ),
      ],
      const SizedBox(height: 16),
      _summarySection(),
      const SizedBox(height: 16),
      for (final c in components) _componentTile(c),
      if (notices.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Notes', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final n in notices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• $n', style: theme.textTheme.bodySmall),
          ),
      ],
      const SizedBox(height: 16),
      Text(
        'Based on ${basedOn['snapshotCount']} snapshot${basedOn['snapshotCount'] == 1 ? '' : 's'} from the last 30 days. '
        'Latest: ${formatIst(basedOn['latestSnapshotAt'])}.',
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  // The AI summary. Always labelled as AI-generated, with when it was written.
  Widget _summarySection() {
    final theme = Theme.of(context);
    final summary = _summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Text('AI summary', style: theme.textTheme.titleSmall),
              ],
            ),
            if (_summaryLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('Generating summary...', style: theme.textTheme.bodySmall),
            ] else if (_summaryError != null)
              Text(
                'Could not load the summary. The score above is unaffected. ($_summaryError)',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              )
            else if (summary != null) ...[
              Text('${summary['text']}'),
              const SizedBox(height: 8),
              Text(
                'AI-generated by Claude Haiku 4.5 on Amazon Bedrock, ${formatIst(summary['generatedAt'])}'
                '${summary['stale'] == true ? '. Could not refresh, showing the previous summary' : ''}. '
                'It can be wrong; the numbers below are the source of truth.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Updates automatically next time you open this screen, at least an hour from now.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _componentTile(Map<String, dynamic> c) {
    final theme = Theme.of(context);
    final status = c['status'] as String;
    final score = c['score'] as int?;
    final tag = switch (status) {
      'placeholder' => 'Placeholder, not measured',
      'unavailable' => 'Not reported, left out of total',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${c['name']} (weight ${c['weight']})', style: theme.textTheme.titleSmall),
              Text(score == null ? '-' : '$score'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: score == null ? 0 : score / 100),
          if (tag != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tag,
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.tertiary),
              ),
            ),
          const SizedBox(height: 4),
          Text('${c['note']}', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _banner({required IconData icon, required String text}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
