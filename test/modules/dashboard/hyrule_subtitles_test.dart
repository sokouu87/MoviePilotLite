import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide FormData, Response;
import 'package:moviepilot_mobile/applog/app_log.dart';
import 'package:moviepilot_mobile/modules/dashboard/widgets/dashboard_widget_styles.dart';
import 'package:moviepilot_mobile/modules/dashboard/widgets/hyrule_recent_widget.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/adapters/subtitle_manual_upload_form_controller.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/services/subtitle_manual_upload_service.dart';
import 'package:moviepilot_mobile/modules/dynamic_form/widgets/VueStyle/subtitle_manual_upload/subtitle_manual_upload_widgets.dart';
import 'package:moviepilot_mobile/services/api_client.dart';
import 'package:moviepilot_mobile/services/app_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _id(int number) => number.toString().padLeft(64, '0');

Map<String, dynamic> _movie(int number, {String? title}) => {
  'id': _id(number),
  'kind': 'Movie',
  'title': title ?? '电影 $number',
  'file': 'movie-$number.mkv',
  'available': true,
  'original': number == 3,
  'search_url': 'https://subhd.tv/search/movie-$number',
};

class _TestApi extends GetxController implements ApiClient {
  @override
  String? token = 'mock-session';
  String? submittedId;
  String? query;
  Map<String, dynamic>? applied;
  bool legacy = false;

  Map<String, dynamic> get recent => {
    'configured': true,
    'rows': [
      for (final number in [1, 2, 3, 4])
        {
          ..._movie(number),
          if (number == 2) 'task': {'state': 'done'},
        },
    ],
  };

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    String? token,
    int? timeout,
    Map<String, dynamic>? headers,
    bool skipUnauthorizedHandling = false,
    bool skipV3EnvelopeUnwrap = false,
  }) async {
    switch (path.split('/').last) {
      case 'library_page':
        expect(queryParameters?['order'], 'desc');
        if (legacy) return _response(path, null, status: 404);
        if (queryParameters?['state'] == 'recent') {
          expect(queryParameters?['kind'], 'Movie');
          return _response(path, recent);
        }
        query = queryParameters?['q'] as String?;
        return _response(path, {
          'configured': true,
          'matches': 1,
          'rows': [_movie(5, title: '片库旧片 2018')],
        });
      case 'search':
        expect(legacy, isTrue);
        return _response(path, {
          'medias': [
            {'title': '旧版片源', 'media_type': 'movie', 'text_only': true},
          ],
          'page': 1,
          'total': 1,
        });
      default:
        throw StateError('意外的 GET $path');
    }
  }

  @override
  Future<Response<T>> postJson<T>(
    String path,
    Object? data, {
    Map<String, dynamic>? queryParameters,
    String? token,
    int? timeout,
    Map<String, dynamic>? headers,
  }) async {
    final body = data as Map<String, dynamic>;
    switch (path.split('/').last) {
      case 'ai_submit':
        submittedId = (body['target_ids'] as List).single as String;
        return _response(path, {
          'tasks': [
            {'status': 'pending', 'active': true},
          ],
        });
      case 'apply_upload':
        applied = body;
        return _response(path, {
          'written': [
            {'filename': 'movie-1.zh-Hans.manual.srt'},
          ],
        });
      default:
        throw StateError('意外的 POST $path');
    }
  }

  @override
  Future<Response<T>> postMultipart<T>(
    String path,
    FormData formData, {
    String? token,
    int? timeout,
    Map<String, dynamic>? headers,
  }) async {
    expect(path, '/api/v1/plugin/SubtitleManualUpload/prepare_upload');
    expect(formData.fields.single.value, '["${_id(1)}"]');
    expect(formData.files.single.value.filename, 'SubHD.zip');
    return _response(path, {
      'session_id': 'preview-session',
      'items': [
        for (final number in [1, 2])
          {
            'upload_id': 'member-$number',
            'target_id': _id(1),
            'name': '字幕-$number.srt',
            'ext': '.srt',
            'language_suffix': 'zh-Hans',
            'output_name': 'movie-1.zh-Hans.manual.srt',
            'selected': false,
          },
      ],
    });
  }

  Response<T> _response<T>(String path, Object? data, {int status = 200}) =>
      Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: status,
        data: data as T?,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _TestApi api;

  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    Get.put(AppService());
    Get.put(AppLog());
    api = _TestApi();
    Get.put<ApiClient>(api);
  });

  tearDown(Get.reset);

  Future<void> showCard(
    WidgetTester tester, {
    List<GetPage> pages = const [],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final library = await SubtitleManualUploadService(
      api,
    ).libraryPage(token: api.token!, kind: 'Movie', recentOnly: true);
    await tester.pumpWidget(
      GetMaterialApp(
        getPages: pages,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              HyruleRecentWidget(library: library!, onRefresh: () async {}),
              const Text('其他仪表盘卡片'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('点击海拉鲁字幕标题直达插件主页', (tester) async {
    await showCard(
      tester,
      pages: [
        GetPage<void>(
          name: '/plugin/dynamic-form/page',
          page: () {
            expect(Get.arguments['id'], 'SubtitleManualUpload');
            expect(Get.arguments['focusSearch'], isNull);
            return const Scaffold(body: Text('插件主页'));
          },
        ),
      ],
    );
    await tester.tap(find.text('海拉鲁字幕'));
    await tester.pumpAndSettle();
    expect(find.text('插件主页'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('窄屏显示三部无海报电影，SubHD 直接交给系统浏览器', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    String? launched;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launched = (call.arguments as Map)['url'] as String;
        expect((call.arguments as Map)['useSafariVC'], isFalse);
        expect((call.arguments as Map)['useWebView'], isFalse);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await showCard(tester);

    expect(find.text('电影 4'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('其他仪表盘卡片'), findsOneWidget);
    expect(find.text('SubHD'), findsNWidgets(3));
    expect(
      tester.getSize(find.byType(DashboardMetricCard)).height,
      lessThan(190),
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '原盘请手动上传字幕',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('SubHD').first);
    await tester.pumpAndSettle();
    expect(launched, 'https://subhd.tv/search/movie-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('上传一个 ZIP，预览后只写入最终选择的字幕', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'custom');
      expect((call.arguments as Map)['allowMultipleSelection'], isFalse);
      expect((call.arguments as Map)['allowedExtensions'], [
        'srt',
        'ass',
        'ssa',
        'zip',
      ]);
      return [
        {
          'name': 'SubHD.zip',
          'size': 2,
          'bytes': Uint8List.fromList([1, 2]),
        },
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await showCard(tester);
    await tester.tap(find.byTooltip('上传字幕').first);
    await tester.pumpAndSettle();
    expect(find.text('上传 movie-1.mkv'), findsOneWidget);
    await tester.tap(find.text('选择字幕/压缩包'));
    await tester.pumpAndSettle();
    final confirm = find.text('确认写入');
    final confirmButton = find.ancestor(
      of: confirm,
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);

    for (final title in ['字幕-1.srt', '字幕-2.srt']) {
      final member = find.text(title);
      await tester.ensureVisible(member);
      await tester.tap(member);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.applied?['session_id'], 'preview-session');
    expect(api.applied?['items'], [
      {
        'upload_id': 'member-2',
        'target_id': _id(1),
        'ext': '.srt',
        'language_suffix': 'zh-Hans',
      },
    ]);
    expect(confirm, findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('AI 任务发给当前片源，历史搜索直达无海报结果', (tester) async {
    final controller = SubtitleManualUploadFormController(formMode: false);
    addTearDown(controller.onClose);
    await showCard(
      tester,
      pages: [
        GetPage<void>(
          name: '/plugin/dynamic-form/page',
          page: () {
            expect(Get.arguments['id'], 'SubtitleManualUpload');
            return SubtitleManualUploadRenderer(
              controller: controller,
              formMode: false,
            );
          },
        ),
      ],
    );
    await tester.tap(find.byTooltip('AI 翻译'));
    await tester.pumpAndSettle();
    expect(api.submittedId, _id(1));
    expect(find.byTooltip('AI 字幕处理中'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜索片库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final search = find.byType(EditableText);
    expect(search, findsOneWidget);
    await tester.enterText(search, '旧片');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(search, findsNothing);
    expect(api.query, '旧片');
    expect(find.text('片库旧片 2018'), findsOneWidget);
    expect(find.byTooltip('上传字幕'), findsOneWidget);
    expect(find.byTooltip('AI 翻译'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('旧版没有统一片库接口时继续使用原有搜索', () async {
    api.legacy = true;
    final controller = SubtitleManualUploadFormController(formMode: false);
    addTearDown(controller.onClose);
    await controller.runSearch();
    expect(controller.medias.single['title'], '旧版片源');
  });
}
