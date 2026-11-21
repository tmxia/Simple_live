/// 线路名称里的 CDN 节点展示（App / TV 共用）
///
/// 弹层里只写"线路1/2/3"时分不清哪条是哪条，排障时要来回试。
/// 这里从 URL 主机名里取一个短标签：
/// - 普通 CDN：主机名第一段，把 `d1--ov-gotcha03` 这类前缀剥成 `ov-gotcha03`；
/// - PCDN：`*.mcdn.*` 节点名是随机串，统一显示 `mcdn`；
/// - 本机中转（将来的 HLS relay）：不显示。
class StreamLineLabel {
  StreamLineLabel._();

  /// 节点名，取不到时返回空串（调用方保持原样即可）
  static String node(String url) {
    final host = Uri.tryParse(url)?.host ?? "";
    if (host.isEmpty || host == "127.0.0.1" || host == "localhost") {
      return "";
    }
    if (host.contains(".mcdn.")) {
      return "mcdn";
    }
    var label = host.split(".").first;
    final dash = label.indexOf("--");
    if (dash >= 0 && dash + 2 < label.length) {
      label = label.substring(dash + 2);
    }
    return label.length > 20 ? label.substring(0, 20) : label;
  }

  /// `线路3 · ov-gotcha03`；节点名为空时退化成 [prefix]
  static String withNode(String prefix, String url) {
    final name = node(url);
    return name.isEmpty ? prefix : "$prefix · $name";
  }
}
