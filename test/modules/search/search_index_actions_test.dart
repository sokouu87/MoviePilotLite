import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:moviepilot_mobile/applog/app_log.dart';
import 'package:moviepilot_mobile/modules/dashboard/controllers/dashboard_controller.dart';
import 'package:moviepilot_mobile/modules/index.dart';
import 'package:moviepilot_mobile/modules/search/controllers/search_index_controller.dart';
import 'package:moviepilot_mobile/modules/search/models/search_history.dart';
import 'package:moviepilot_mobile/modules/search/pages/search_mid_sheet.dart';
import 'package:moviepilot_mobile/modules/search/repositories/search_history_repository.dart';
import 'package:moviepilot_mobile/modules/search/services/search_keyword_hints_service.dart';
import 'package:moviepilot_mobile/modules/site/controllers/site_controller.dart';
import 'package:moviepilot_mobile/modules/site/models/site_models.dart';
import 'package:moviepilot_mobile/services/api_client.dart';
import 'package:moviepilot_mobile/services/app_service.dart';
import 'package:moviepilot_mobile/services/hive_service.dart';
import 'package:moviepilot_mobile/services/ios_shared_session_service.dart';
import 'package:moviepilot_mobile/services/ios_widget_navigation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends AppService {
  bool allowSiteSearch = true;

  @override
  bool get hasLoggedInSession => true;
  @override
  bool get canSearch => allowSiteSearch;
  @override
  bool get canDiscovery => false;
  @override
  bool get canManage => false;
}

class _Dashboard extends DashboardController {
  @override
  // 仪表盘只用于切换标签，跳过它的后台请求与定时刷新。
  // ignore: must_call_super
  Future<void> onInit() async {}
}

class _History extends SearchHistoryRepository {
  @override
  List<SearchHistoryEntry> load({int limit = 20}) => [];
  @override
  void save(String keyword) {}
}

class _Sites extends SiteController {
  @override
  void onReady() {}

  @override
  Future<List<int>?> loadIcon(SiteModel site) async => null;
}

class _Api extends GetxController implements ApiClient {
  int siteRequests = 0;

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
    expect(path, '/api/v1/site/');
    siteRequests++;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          [
                {'id': 1, 'is_active': true},
                {'id': '2', 'is_active': '1'},
                {'id': 3, 'is_active': false},
              ]
              as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

void main() {
  late _App app;
  late _Api api;
  late SearchIndexController search;
  Finder getEditor() => find.byType(CupertinoTextField);

  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    app = _App();
    api = _Api();
    Get.put<AppService>(app);
    Get.put<ApiClient>(api);
    Get.put(AppLog());
    Get.put(HiveService());
    Get.put(IosSharedSessionService());
    Get.put(IosWidgetNavigationService());
    Get.put(SearchKeywordHintsService());
    Get.put<DashboardController>(_Dashboard());
    search = Get.put(SearchIndexController(historyRepository: _History()));
    Get.put<SiteController>(
      _Sites()
        ..items.assignAll([
          for (final (id, name) in [(1, '站点甲'), (2, '站点乙')])
            SiteItem(
              site: SiteModel(id: id, name: name, domain: 'site.test', url: ''),
              userData: null,
              iconBytes: null,
            ),
        ]),
    );
  });
  tearDown(Get.reset);

  Future<void> showTabs(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Index(initialIndex: 0),
        getPages: [
          GetPage<void>(
            name: '/search-media-result',
            page: () => Scaffold(
              body: Text(
                '站点结果 ${Get.parameters['title']} ${Get.parameters['sites']}',
              ),
            ),
          ),
          GetPage<void>(
            name: '/media-search-list',
            page: () =>
                Scaffold(body: Text('影片结果 ${Get.parameters['keyword']}')),
          ),
        ],
      ),
    );
    await _frames(tester);
    await tester.tap(find.byTooltip('搜索'));
    await _frames(tester);
  }

  testWidgets('第一次点搜索标签即聚焦，回车默认搜索启用站点', (tester) async {
    await showTabs(tester);
    expect(search.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('仪表盘'));
    await _frames(tester);
    expect(search.focusNode.hasFocus, isFalse);
    await tester.tap(find.byTooltip('搜索'));
    await _frames(tester);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.enterText(getEditor(), '  测试影片  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _frames(tester);
    expect(find.text('站点结果 测试影片 1,2'), findsOneWidget);
    expect(api.siteRequests, 1);
  });

  testWidgets('站点按钮只改站点，放大镜搜影片，回车使用所选站点', (tester) async {
    await showTabs(tester);
    final sites = find.byTooltip('选择搜索站点');
    final media = find.byTooltip('搜索影片');
    expect(tester.getCenter(sites).dx, lessThan(tester.getCenter(media).dx));
    await tester.enterText(getEditor(), '测试影片');
    await _frames(tester);

    await tester.tap(sites);
    await _frames(tester);
    expect(find.byType(SiteSelectSheet), findsOneWidget);
    await tester.tap(find.text('站点乙'));
    await tester.tap(find.text('确定'));
    await _frames(tester);
    expect(find.byType(SiteSelectSheet), findsNothing);
    expect(find.textContaining('站点结果'), findsNothing);
    expect(await SiteSelectSheet.readSearchSelection(app), [2]);

    await tester.tap(media);
    await _frames(tester);
    expect(find.text('影片结果 测试影片'), findsOneWidget);
    Get.back<void>();
    await _frames(tester);
    await tester.tap(getEditor());
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _frames(tester);
    expect(find.text('站点结果 测试影片 2'), findsOneWidget);
    expect(api.siteRequests, 0);
  });

  testWidgets('无资源搜索权限的账户仍可按回车搜索影片', (tester) async {
    app.allowSiteSearch = false;
    await showTabs(tester);
    expect(find.byTooltip('选择搜索站点'), findsNothing);
    await tester.enterText(getEditor(), '测试影片');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _frames(tester);
    expect(find.text('影片结果 测试影片'), findsOneWidget);
    expect(api.siteRequests, 0);
  });
}
