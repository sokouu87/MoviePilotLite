import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:moviepilot_mobile/applog/app_log.dart';
import 'package:moviepilot_mobile/modules/dashboard/widgets/hyrule_recent_widget.dart';
import 'package:moviepilot_mobile/services/api_client.dart';
import 'package:moviepilot_mobile/services/app_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HyruleApi extends GetxController implements ApiClient {
  @override
  String? token = 'test-session';

  String? submittedId;

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
    expect(path, '/api/v1/plugin/SubtitleManualUpload/library_page');
    expect(queryParameters, {
      'state': 'recent',
      'kind': 'Movie',
      'order': 'desc',
    });
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'configured': true,
                'rows': [
                  for (final index in [1, 2, 3, 4])
                    {
                      'id': 'movie-$index',
                      'title': '电影 $index',
                      'file': 'movie-$index.mkv',
                      'available': true,
                      'original': index == 3,
                      'search_url': 'https://subhd.tv/search/movie-$index',
                      if (submittedId == 'movie-$index')
                        'task': {'state': 'queued'},
                    },
                ],
              }
              as T,
    );
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
    expect(path, '/api/v1/plugin/SubtitleManualUpload/ai_submit');
    final ids = (data as Map)['target_ids'] as List;
    submittedId = ids.single as String;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    Get.put(AppService());
    Get.put(AppLog());
  });
  tearDown(Get.reset);

  testWidgets('紧凑卡片复用电影片源、上传和片库路由', (tester) async {
    final api = Get.put<ApiClient>(_HyruleApi()) as _HyruleApi;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 680);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      GetMaterialApp(
        getPages: [
          GetPage(
            name: '/plugin/dynamic-form/page',
            page: () => Scaffold(body: Text(Get.arguments['id'] as String)),
          ),
        ],
        home: const Scaffold(body: HyruleRecentWidget()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('电影 4'), findsNothing);
    expect(find.text('SubHD'), findsNWidgets(3));
    expect(find.text('上传'), findsNWidgets(3));
    expect(find.text('AI 翻译'), findsNWidgets(2));
    expect(find.byType(Image), findsNothing);
    expect(
      tester.getSize(find.byType(HyruleRecentWidget)).height,
      lessThan(180),
    );

    await tester.tap(find.text('上传').at(1));
    await tester.pumpAndSettle();
    expect(find.text('上传 movie-2.mkv'), findsOneWidget);
    expect(find.text('选择字幕/压缩包'), findsOneWidget);
    Navigator.of(tester.element(find.text('选择字幕/压缩包'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI 翻译').at(1));
    await tester.pumpAndSettle();
    expect(api.submittedId, 'movie-2');
    expect(find.text('处理中'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜索片库'));
    await tester.pumpAndSettle();
    expect(find.text('SubtitleManualUpload'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
