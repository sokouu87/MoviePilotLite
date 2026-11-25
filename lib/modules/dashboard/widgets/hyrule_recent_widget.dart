import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:moviepilot_mobile/modules/dashboard/controllers/dashboard_controller.dart';
import 'package:moviepilot_mobile/modules/dashboard/widgets/dashboard_widget_styles.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/adapters/subtitle_manual_upload_form_controller.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/services/subtitle_manual_upload_service.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/widgets/VueStyle/subtitle_manual_upload/subtitle_manual_upload_widgets.dart';
import 'package:moviepilot_mobile/services/api_client.dart';
import 'package:moviepilot_mobile/services/app_service.dart';
import 'package:moviepilot_mobile/utils/open_url.dart';
import 'package:moviepilot_mobile/utils/toast_util.dart';

class HyruleRecentWidget extends StatefulWidget {
  const HyruleRecentWidget({super.key});

  @override
  State<HyruleRecentWidget> createState() => _HyruleRecentWidgetState();
}

class _HyruleRecentWidgetState extends State<HyruleRecentWidget> {
  final _api = Get.find<ApiClient>();
  final _app = Get.find<AppService>();
  late final _service = SubtitleManualUploadService(_api);
  Map<String, dynamic>? _data;
  Timer? _timer;
  bool _loading = false;
  bool _busy = false;

  String? get _token =>
      _app.loginResponse?.accessToken ??
      _app.latestLoginProfileAccessToken ??
      _api.token;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (TickerMode.of(context)) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null || token.isEmpty || _loading) return;
    _loading = true;
    try {
      final result = await _service.recentMovies(token);
      if (mounted) {
        setState(() {
          _data = SubtitleManualUploadFormController.asMap(result.data);
        });
      }
    } catch (_) {
      // 该用户的服务器可能没有安装海拉鲁。
    } finally {
      _loading = false;
    }
  }

  Future<void> _generate(String id, bool completed) async {
    final token = _token;
    if (token == null || token.isEmpty || _busy) return;
    if (completed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新生成字幕？'),
          content: const Text('将使用当前订阅模型并另存字幕。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('返回'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('生成'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true || _busy) return;
    }
    setState(() => _busy = true);
    try {
      await _service.postJsonAction('ai_submit', {
        'target_ids': [id],
      }, token);
      if (mounted) ToastUtil.success('已提交 AI 字幕任务');
      await _load();
    } catch (error) {
      if (mounted) {
        ToastUtil.error(
          SubtitleManualUploadService.errorMessage(error, '提交任务失败'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final titles = SubtitleManualUploadFormController.asMapList(
      data['rows'],
    ).take(3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DashboardMetricCard(
        padding: const EdgeInsets.fromLTRB(10, 2, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DashboardController.hyruleWidgetName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _action('搜索片库', () {
                  Get.toNamed(
                    '/plugin/dynamic-form/page',
                    arguments: {
                      'id': SubtitleManualUploadService.pluginId,
                      'title': DashboardController.hyruleWidgetName,
                    },
                  );
                }),
              ],
            ),
            if (titles.isEmpty) const Text('暂无最近入库电影'),
            for (final row in titles)
              _row(context, row, data['configured'] == true),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> row, bool configured) {
    final title = '${row['title'] ?? ''}';
    final id = '${row['id'] ?? ''}';
    final uri = Uri.tryParse('${row['search_url'] ?? ''}');
    final task = SubtitleManualUploadFormController.asMap(row['task']);
    final state = task?['state'];
    final running = state == 'queued' || state == 'running';
    final writable = row['available'] == true && id.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        _action(
          'SubHD',
          uri?.scheme == 'https' && uri?.host == 'subhd.tv'
              ? () => WebUtil.open(url: uri.toString(), internal: false)
              : null,
        ),
        _action('上传', writable ? () => openHyruleUpload(context, row) : null),
        if (row['original'] != true)
          _action(
            running ? '处理中' : 'AI 翻译',
            writable && configured && !_busy && !running
                ? () => _generate(id, state == 'done')
                : null,
          ),
      ],
    );
  }

  Widget _action(String label, VoidCallback? onPressed) => TextButton(
    style: TextButton.styleFrom(
      minimumSize: const Size(32, 36),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}
