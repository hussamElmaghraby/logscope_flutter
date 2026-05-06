import 'package:dio/dio.dart';
import 'package:logscope_flutter/src/debug_log_interceptor.dart';
import 'package:logscope_flutter/src/debug_log_store.dart';

void main() async {
  final interceptor = DebugLogInterceptor();
  final options = RequestOptions(path: '/test', method: 'GET');
  final response = Response(
    requestOptions: options,
    statusCode: 200,
    data: {'hello': 'world'},
    headers: Headers.fromMap({'content-type': ['application/json']}),
  );
  
  interceptor.onResponse(response, ResponseInterceptorHandler());
  print(DebugLogStore.instance.entries.last.metadata);
}
