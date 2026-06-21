/// Example app for `agentic_client`.
///
/// Drops [AguiChat] into a Material shell, wired up with a small catalog of
/// custom widgets defined in `catalog.dart`. Point the app at any AG-UI
/// compatible backend with `--dart-define=AGENT_URL=…`; defaults to
/// `http://localhost:8123`.
library;

import 'dart:convert';

import 'package:agentic_client/agentic_client.dart';
import 'package:flutter/material.dart';

import 'catalog.dart';

const _backendUrl = String.fromEnvironment('AGENT_URL', defaultValue: 'http://localhost:8123');

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

class _ChatScreen extends StatefulWidget {
  const _ChatScreen();

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  Map<String, dynamic> _agentState = const {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _StateStrip(state: _agentState),
          Expanded(
            child: AguiChat(
              baseUrl: _backendUrl,
              catalog: buildExampleCatalog(),
              emptyStateTitle: 'What would you like to build?',
              emptyStateSendButtonLabel: 'Create',
              hintText: 'Show me some products and tell me about the weather',
              sendButtonLabel: 'Send',
              onStateChanged: (s) => setState(() => _agentState = s),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin debug strip that shows the agent's shared state mirror.
///
/// Hidden when the mirror has nothing interesting to show. The conversation
/// `messages` array and CopilotKit/AG-UI bookkeeping are filtered out: the
/// chat itself already shows the conversation, and dumping it as JSON
/// would overflow the screen.
class _StateStrip extends StatelessWidget {
  const _StateStrip({required this.state});

  final Map<String, dynamic> state;

  /// Top-level keys that are bookkeeping rather than application state.
  /// `messages` is the LangGraph conversation log (duplicates the chat);
  /// `copilotkit` / `ag-ui` are protocol-level scaffolding.
  static const _hiddenKeys = <String>{'messages', 'copilotkit', 'ag-ui'};

  @override
  Widget build(BuildContext context) {
    final visible = <String, dynamic>{
      for (final entry in state.entries)
        if (!_hiddenKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (visible.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final json = const JsonEncoder.withIndent('  ').convert(visible);

    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        // Cap the height so a fat state doesn't push the chat off screen;
        // overflow scrolls inside the strip.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.storage, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    json,
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
