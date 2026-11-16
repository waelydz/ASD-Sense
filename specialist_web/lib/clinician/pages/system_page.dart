import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../api_client.dart';
import '../clinic_data.dart';
import '../shell.dart';
import '../widgets.dart';

/// What the models are, how results are routed, and whether the backend has
/// them loaded. The thresholds mirror backend/main.py; keep them in sync.
class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  static const _edgeThreshold = 0.85;
  static const _inconclusiveThreshold = 0.60;

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    final b = data.backend;

    Widget modelRow(String name, String role, bool? loaded) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Dot(loaded == null ? AppColors.textFaint : (loaded ? AppColors.success : AppColors.danger)),
            const SizedBox(width: 10),
            Expanded(child: CellText(name, strong: true, sub: role)),
            Text(
              loaded == null ? 'Unknown' : (loaded ? 'Loaded' : 'Not loaded'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: loaded == true ? AppColors.success : AppColors.textGrey,
              ),
            ),
          ]),
        );

    final online = b?.online;

    return PageBody(children: [
      PageHeader(
        title: 'Models & system',
        subtitle: 'How ASD-Sense produces a result, so you can judge how much weight to give it.',
        actions: [
          Btn.secondary(data.syncing ? 'Checking...' : 'Check again',
              onPressed: data.syncing ? null : () => data.sync()),
        ],
      ),
      ResponsiveColumns(
        breakpoint: 980,
        children: [
          Panel(
            title: 'Backend',
            caption: b == null ? 'Not checked yet' : 'Checked ${fmtAgo(b.checkedAt)}',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KeyValue('Address', ApiClient.baseUrl),
              KeyValue('Status', online == null ? 'Unknown' : (online ? 'Online' : 'Offline (${b!.error ?? ''})')),
              if (data.lastSyncAt != null) KeyValue('Last data sync', fmtDateTime(data.lastSyncAt!)),
              const SizedBox(height: 10),
              const Divider(color: AppColors.border),
              modelRow(
                  'Gesture MobileNetV2', 'Edge model, hand gesture', b?.online == true ? b!.gestureMobileNet : null),
              modelRow('Gesture ViT-B/16', 'Cloud model, hand gesture', b?.online == true ? b!.gestureVit : null),
              modelRow('Facial MobileNetV2', 'Edge model, facial', b?.online == true ? b!.facialMobileNet : null),
              modelRow('Facial ViT-B/16', 'Cloud model, facial', b?.online == true ? b!.facialVit : null),
            ]),
          ),
          Panel(
            title: 'How a result is produced',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _step(
                  '1',
                  'Edge model first',
                  'The image is resized to 224 x 224 and scored by MobileNetV2. The output is the probability '
                      'that the image shows ASD-associated features.'),
              _step(
                  '2',
                  'Escalation',
                  'Confidence is the larger of p and 1 - p. If it is below ${pct(_edgeThreshold)} and the ViT-B/16 '
                      'model is loaded, the image is re-scored by ViT and that score replaces the first one.'),
              _step(
                  '3',
                  'Classification',
                  'If confidence is below ${pct(_inconclusiveThreshold)} the result is "inconclusive" (probability '
                      'between 40% and 60%). Otherwise 50% or more is "autistic" (shown here as Flagged), '
                      'below 50% is "non_autistic" (Not flagged).'),
              _step(
                  '4',
                  'Logging',
                  'Every result is written to Screening_Records with the model name and routing tier, '
                      'whether it came from the guardian app or this portal.'),
              const SizedBox(height: 6),
              const Notice(
                'These models screen one image at a time. They are not validated as diagnostic tools. '
                'Use them alongside history, observation and standard instruments.',
                warning: true,
              ),
            ]),
          ),
        ],
      ),
    ]);
  }

  Widget _step(String n, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.sageBg, borderRadius: BorderRadius.circular(8)),
            child: Text(n, style: const TextStyle(color: AppColors.sage, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Text(body, style: const TextStyle(color: AppColors.textGrey, fontSize: 13, height: 1.45)),
            ]),
          ),
        ]),
      );
}
