/// 关注标签的名字规则：内置标签名、长度上限与校验。
/// 移动端标签管理、局域网同步、WebDAV 备份都按同一套规则走，
/// 避免各处各自判断导致同名标签反复生成。
class FollowTagRules {
  FollowTagRules._();

  /// 内置标签名（UI 固定展示，不可作为自定义标签名）
  static const List<String> reservedNames = ["全部", "直播中", "未开播"];

  /// 自定义标签名长度上限
  static const int maxNameLength = 12;

  static String normalize(String raw) => raw.trim();

  /// 返回不合法的原因，合法时返回 null，便于 UI 直接提示
  static String? invalidReason(String raw) {
    var name = normalize(raw);
    if (name.isEmpty) {
      return "标签名不能为空";
    }
    if (name.length > maxNameLength) {
      return "标签名最多 $maxNameLength 个字";
    }
    if (reservedNames.contains(name)) {
      return "「$name」是内置标签，请换一个名字";
    }
    return null;
  }

  static bool isValid(String raw) => invalidReason(raw) == null;
}
