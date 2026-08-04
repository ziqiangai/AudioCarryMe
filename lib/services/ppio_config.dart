import 'secrets.local.dart';

/// PPIO 派欧云接入配置。
///
/// ⚠️ 与 AgentConfig 同理：key 硬编码仅限本地开发，上线前改为后端中转下发。
class PpioConfig {
  /// 国内 base；海外可切 https://api.novita.ai/v3（注意必须带 /v3）。
  static const String baseUrl = 'https://api.ppio.com/v3';

  static const String apiKey = Secrets.ppioKey;

  /// Seedance 2.0 的 bytedance 代理（Ark 协议）——走 PPIO 国内域名，同一把 key。
  static const String bytedanceBaseUrl = '$baseUrl/bytedance';

  /// 轮询间隔与上限（15 分钟兜底）。
  static const Duration pollInterval = Duration(seconds: 3);
  static const int maxPollAttempts = 300;
}
