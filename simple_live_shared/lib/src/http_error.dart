/// 共享层网络错误：直接复用 core 的 [CoreError]。
///
/// 原来 shared 和 core 各写了一份完全相同的状态码映射，两边文案会逐渐走样
/// （例如 core 补充了抖音 444 风控文案，shared 那份没有）。这里改为别名，
/// 保留 `HttpError` 这个名字让已有调用方不用改，语义统一由 core 维护。
library;

import 'package:simple_live_core/simple_live_core.dart';

typedef HttpError = CoreError;
