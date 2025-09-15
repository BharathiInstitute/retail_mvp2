import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  // TODO: Initialize Firebase here when backend is ready.
  runApp(const ProviderScope(child: MyApp()));
}
