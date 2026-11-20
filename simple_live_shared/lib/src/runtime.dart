/// 共享层向宿主 App 借用的运行时信息与日志出口。
///
/// shared 包不直接依赖任何一端的 Log / Utils，改用这里的钩子，
/// 由各端 main.dart 启动时注入，行为与原来各自实现保持一致。
library;

typedef SharedErrorLogFn = void Function(String message, StackTrace? stackTrace);

class SharedRuntime {
  SharedRuntime._();

  /// 应用名（signalr 上报用），如 "Simple Live" / "Simple Live TV"
  static String appName = "Simple Live";

  /// 平台标识，如 "android" / "tv"
  static String platformName = "";

  /// 应用版本号
  static String appVersion = "";

  static void Function(String message)? onDebug;
  static void Function(String message)? onInfo;
  static SharedErrorLogFn? onError;

  static void d(String message) => onDebug?.call(message);

  static void i(String message) => onInfo?.call(message);

  static void e(String message, [StackTrace? stackTrace]) =>
      onError?.call(message, stackTrace);
}
