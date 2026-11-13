// ⚠️ 这个文件不要删。
//
// CI 用 `flutter create --platforms=android .` 补全安卓工程时，如果
// test/widget_test.dart 不存在，会生成 Flutter 模板自带的计数器示例——
// 那个文件里写死了 `MyApp()`，而本项目的根组件叫 `ScraperApp`，
// 结果就是 `flutter analyze` 报 `The name 'MyApp' isn't a class` 并让构建失败。
//
// 只要这个文件存在，`flutter create` 就会跳过它，模板那条脏数据也就不会出现。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_scraper/main.dart';

void main() {
  testWidgets('根组件能渲染出首页', (WidgetTester tester) async {
    await tester.pumpWidget(const ScraperApp());
    await tester.pump();

    // 能建出 MaterialApp，说明主题、MaterialApp 装配这条链路是通的
    expect(find.byType(MaterialApp), findsOneWidget);
    // 首页真的挂上去了（不是白屏 / 不是异常占位）
    expect(find.byType(HomePage), findsOneWidget);
  });
}
