import 'package:dio/dio.dart';

import '../http_error.dart';
import 'custom_log_interceptor.dart';

class HttpClient {
  static HttpClient? _httpUtil;

  static HttpClient get instance {
    _httpUtil ??= HttpClient();
    return _httpUtil!;
  }

  late Dio dio;
  HttpClient() {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(CustomLogInterceptor());
  }

  /// 统一的错误归一：HTTP 状态错误保留状态码，超时单独给文案，其余归为 [fallback]。
  HttpError _normalize(Object error, String fallback) {
    if (error is HttpError) {
      return error;
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.badResponse) {
        return HttpError(
          error.message ?? "",
          statusCode: error.response?.statusCode ?? 0,
        );
      }
      if (_isTimeout(error.type)) {
        return HttpError("请求超时，请检查网络后重试");
      }
    }
    return HttpError(fallback);
  }

  bool _isTimeout(DioExceptionType type) {
    return type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout;
  }

  Future<T> _guard<T>(Future<T> Function() request, String fallback) async {
    try {
      return await request();
    } catch (e) {
      throw _normalize(e, fallback);
    }
  }

  /// 需要读取响应头的接口：状态码错误时把响应原样返回，交给调用方判断。
  Future<Response<T>> _guardResponse<T>(
    Future<Response<T>> Function() request,
    String fallback,
  ) async {
    try {
      return await request();
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        return e.response! as Response<T>;
      }
      throw _normalize(e, fallback);
    }
  }

  /// Get请求，返回String
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<String> getText(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) {
    return _guard<String>(
      () async {
        var result = await dio.get(
          url,
          queryParameters: queryParameters ?? {},
          options: Options(
            responseType: ResponseType.plain,
            headers: header ?? {},
          ),
          cancelToken: cancel,
        );
        return result.data as String;
      },
      "发送GET请求失败",
    );
  }

  /// Get请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<dynamic> getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) {
    return _guard<dynamic>(
      () async {
        var result = await dio.get(
          url,
          queryParameters: queryParameters ?? {},
          options: Options(
            responseType: ResponseType.json,
            headers: header ?? {},
          ),
          cancelToken: cancel,
        );
        return result.data;
      },
      "发送GET请求失败",
    );
  }

  /// Post请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [data] 内容
  /// * [cancel] 任务取消Token
  Future<dynamic> postJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? header,
    bool formUrlEncoded = false,
    CancelToken? cancel,
  }) {
    return _guard<dynamic>(
      () async {
        var result = await dio.post(
          url,
          queryParameters: queryParameters ?? {},
          data: data ?? {},
          options: Options(
            responseType: ResponseType.json,
            headers: header ?? {},
            contentType:
                formUrlEncoded ? Headers.formUrlEncodedContentType : null,
          ),
          cancelToken: cancel,
        );
        return result.data;
      },
      "发送POST请求失败",
    );
  }

  /// Head请求，返回Response
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<Response> head(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) {
    return _guardResponse<dynamic>(
      () => dio.head(
        url,
        queryParameters: queryParameters ?? {},
        options: Options(
          headers: header ?? {},
          receiveDataWhenStatusError: true,
        ),
        cancelToken: cancel,
      ),
      "发送HEAD请求失败",
    );
  }

  /// Get请求，返回Response（用于需要读取响应头的场景）
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<Response> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) {
    return _guardResponse<dynamic>(
      () => dio.get(
        url,
        queryParameters: queryParameters ?? {},
        options: Options(
          headers: header ?? {},
          receiveDataWhenStatusError: true,
        ),
        cancelToken: cancel,
      ),
      "发送GET请求失败",
    );
  }

  /// Post请求，返回Response（用于需要读取响应头的场景）
  /// * [url] 请求链接
  /// * [data] 内容
  /// * [cancel] 任务取消Token
  Future<Response> post(
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) {
    return _guardResponse<dynamic>(
      () => dio.post(
        url,
        queryParameters: queryParameters ?? {},
        data: data ?? {},
        options: Options(
          headers: header ?? {},
          receiveDataWhenStatusError: true,
        ),
        cancelToken: cancel,
      ),
      "发送POST请求失败",
    );
  }
}
