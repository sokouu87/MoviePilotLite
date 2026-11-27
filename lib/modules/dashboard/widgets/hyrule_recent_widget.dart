import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:moviepilot_mobile/modules/dashboard/controllers/dashboard_controller.dart';
import 'package:moviepilot_mobile/modules/dashboard/widgets/dashboard_widget_styles.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/adapters/subtitle_manual_upload_form_controller.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/services/subtitle_manual_upload_service.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/widgets/VueStyle/subtitle_manual_upload/subtitle_manual_upload_widgets.dart';

class HyruleRecentWidget extends StatelessWidget {
  const HyruleRecentWidget({
    super.key,
    required this.library,
    required this.onRefresh,
  });

  final Map<String, dynamic> library;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final rows = SubtitleManualUploadFormController.asMapList(
      library['rows'],
    ).take(3).toList();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DashboardMetricCard(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DashboardController.hyruleWidgetName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('搜索片库'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    await Get.toNamed<void>(
                      '/plugin/dynamic-form/page',
                      arguments: {
                        'id': SubtitleManualUploadService.pluginId,
                        'title': DashboardController.hyruleWidgetName,
                        'focusSearch': true,
                      },
                    );
                    if (context.mounted) await onRefresh();
                  },
                ),
              ],
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('暂无最近入库电影', style: theme.textTheme.bodySmall),
                ),
              ),
            for (final row in rows) ...[
              const Divider(height: 1),
              HyruleSubtitleRow(
                key: ValueKey(row['id']),
                media: row,
                aiAvailable: library['configured'] == true,
                compact: true,
                onChanged: onRefresh,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
