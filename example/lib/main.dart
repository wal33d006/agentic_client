/// Example app for `agentic_client`.
///
/// Drops [AguiChat] into a Material shell, wired up with a small catalog of
/// custom widgets defined in `catalog.dart`. Point the app at any AG-UI
/// compatible backend with `--dart-define=AGENT_URL=…`; defaults to
/// `http://localhost:8123`.
library;

import 'package:agentic_client/agentic_client.dart';
import 'package:flutter/material.dart';

import 'catalog.dart';

const _backendUrl = String.fromEnvironment(
  'AGENT_URL',
  defaultValue: 'https://cardiac-pork-physical-medium.trycloudflare.com',
);

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      ),
      home: const _ChatScreen(),
    );
  }
}

class _ChatScreen extends StatelessWidget {
  const _ChatScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AguiChat(
        baseUrl: _backendUrl,
        catalog: buildExampleCatalog(),
        catalogDescription: exampleCatalogDescription,
        emptyStateTitle: 'What would you like to build?',
        emptyStateSendButtonLabel: 'Create',
        hintText: 'Build me 3 fast food vendor cards',
        sendButtonLabel: 'Send',
      ),
    );
  }
}
