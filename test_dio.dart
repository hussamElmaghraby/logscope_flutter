import 'package:dio/dio.dart';
import 'package:logscope_flutter/logscope_flutter.dart';
import 'package:logscope_flutter/src/debug_log_store.dart';

void main() async {
  final dio = Dio();
  dio.interceptors.add(Logscope.dioInterceptor());
  
  try {
    await dio.get(
      'https://jsonplaceholder.typicode.com/users',
      queryParameters: {'role': 'customer', 'status': 'active'},
    );
  } catch (e) {
    print('Error: $e');
  }

  for (final entry in DebugLogStore.instance.entries) {
    print('Entry Metadata: ${entry.metadata}');
  }
}
