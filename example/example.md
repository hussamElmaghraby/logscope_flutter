# logscope_flutter Example

## Quick Start (2 lines)

```dart
import 'package:flutter/material.dart';
import 'package:logscope_flutter/logscope_flutter.dart';

void main() {
  // 1. Initialize
  Logscope.init(
    appName: 'MyApp',
    appVersion: '1.0.0',
    // enabled: true,              // defaults to kDebugMode
    // captureFlutterErrors: true,  // auto-capture unhandled exceptions
    // showErrorToasts: true,       // show overlay on errors
  );

  // 2. Wrap your root widget — adds the draggable debug FAB
  runApp(Logscope.wrap(const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logscope Demo')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Logscope.d('Button pressed', tag: 'UI');
            Logscope.i('Loading data...', tag: 'Repo');
            Logscope.w('Cache expired', tag: 'Cache');
            Logscope.e('Failed to load', tag: 'Repo', error: 'Timeout');
          },
          child: const Text('Generate Logs'),
        ),
      ),
    );
  }
}
```

## Add Dio HTTP Logging

```dart
import 'package:dio/dio.dart';
import 'package:logscope_flutter/logscope_flutter.dart';

final dio = Dio();

void setupDio() {
  // One line — all HTTP traffic is captured with structured cards
  dio.interceptors.add(Logscope.dioInterceptor());
}
```

## Custom Classification Rules

```dart
// Register domain-specific classifiers
Logscope.classifier.addRule(({
  required message,
  required levelName,
  tag,
  metadata,
}) {
  if (message.contains('Firestore')) return IssueLayer.server;
  if (message.contains('Stripe'))   return IssueLayer.server;
  return null; // let built-in rules decide
});
```

## Device Context for Exports

```dart
// Enrich exported log reports with device info
Logscope.setDeviceContext(
  appName: 'MyApp',
  appVersion: '2.3.1',
  buildNumber: '47',
  deviceModel: 'iPhone 14 Pro',
  osVersion: 'iOS 17.4',
  custom: {'environment': 'staging'},
);
```
