import 'package:flutter/material.dart';

import 'logging/app_log.dart';
import 'screens/home_screen.dart';
import 'services/deepseek_agent_service.dart';
import 'services/ppio_service.dart';
import 'state/chat_store.dart';
import 'state/generation_store.dart';
import 'state/log_store.dart';
import 'state/request_log_store.dart';
import 'storage/sqlite_chat_storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 打开本地数据库并加载历史数据。
  final storage = await SqliteChatStorage.open();

  // 统一日志框架：绑定后全局 AppLog.x(...) 会落库。
  final appLogStore = AppLogStore(storage);
  await appLogStore.load();
  AppLog.bind(appLogStore);

  final logStore = RequestLogStore(storage);
  await logStore.load();

  // 生成任务：加载历史 + 恢复未完成任务的轮询（App 被杀重启场景）。
  final genStore = GenerationStore(PpioService(), storage);
  await genStore.load();

  // 真实大模型：DeepSeek（Anthropic 兼容端点），配置见 services/agent_config.dart。
  // 想快速离线调 UI，可换回 StubAgentService()（在 services/agent_service.dart）。
  final store = ChatStore(DeepseekAgentService(logStore: logStore), storage);
  await store.load();

  AppLog.i('app', 'CarryMe 启动完成');

  runApp(CarryMeApp(
    store: store,
    logStore: logStore,
    appLogStore: appLogStore,
    genStore: genStore,
  ));
}

class CarryMeApp extends StatefulWidget {
  final ChatStore store;
  final RequestLogStore logStore;
  final AppLogStore appLogStore;
  final GenerationStore genStore;
  const CarryMeApp({
    super.key,
    required this.store,
    required this.logStore,
    required this.appLogStore,
    required this.genStore,
  });

  @override
  State<CarryMeApp> createState() => _CarryMeAppState();
}

class _CarryMeAppState extends State<CarryMeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App 回前台：恢复未完成生成任务的轮询（切出/假死场景）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppLog.i('app', '回到前台，恢复生成任务查询');
      widget.genStore.recover();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CarryMe',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(
        store: widget.store,
        logStore: widget.logStore,
        appLogStore: widget.appLogStore,
        genStore: widget.genStore,
      ),
    );
  }
}
