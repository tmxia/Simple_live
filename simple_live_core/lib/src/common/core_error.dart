class CoreError extends Error {
  /// 错误码
  final int statusCode;

  /// 错误信息
  final String message;

  CoreError(this.message, {this.statusCode = 0});
  @override
  String toString() {
    if (statusCode != 0) {
      // 旧实现有状态码时直接丢掉 message，只剩「连接服务器失败(412)」这类
      // 泛化文案；把接口原始原因拼在后面，既保留可读提示又不丢排查线索。
      var desc = statusCodeToString(statusCode);
      var origin = message.trim();
      if (origin.isEmpty || desc.contains(origin)) {
        return desc;
      }
      return "$desc · $origin";
    }

    return message;
  }

  String statusCodeToString(int statusCode) {
    switch (statusCode) {
      case 400:
        return "错误的请求(400)";
      case 401:
        return "无权限访问资源(401)";
      case 403:
        return "无权限访问资源(403)";
      case 404:
        return "服务器找不到请求的资源(404)";
      case 405:
        return "请求方法不被允许(405)";
      case 407:
        return "需要代理身份验证(407)";
      case 412:
        return "请求被服务端风控拦截(412)，请检查 Cookie 或稍后再试";
      case 444:
        return "抖音访问过于频繁或触发风控限制(444)，请稍后再试，避免连续刷新或重复进入直播间";
      case 500:
        return "服务器出现错误(500)";
      case 502:
        return "服务器出现错误(502)";
      case 503:
        return "服务器出现错误(503)";
      default:
        return "连接服务器失败，请稍后再试($statusCode)";
    }
  }
}
