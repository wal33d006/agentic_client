/// AG-UI chat for Flutter.
///
/// A drop-in chat widget that talks to any AG-UI-compatible agent backend
/// and renders the agent's generative-UI surfaces (A2UI v0.9) using an
/// `a2ui_flutter` catalog of Flutter widgets you provide.
///
/// Typical usage:
///
/// ```dart
/// import 'package:a2ui_flutter/v0_9/basic_catalog.dart';
/// import 'package:flutter/material.dart';
/// import 'agui_chat/agui_chat.dart';
///
/// Scaffold(
///   appBar: AppBar(title: const Text('Chat')),
///   body: AguiChat(
///     baseUrl: 'http://localhost:8123',
///     catalog: basicCatalog().derive(
///       catalogId: 'my-app.catalog',
///       components: ['Text', 'Column', /* ... */],
///     ),
///     catalogDescription: '... optional A2UI prompt context ...',
///   ),
/// );
/// ```
///
/// See [AguiChat] for the widget API and [AgUiTransport] for the low-level
/// transport if you want to compose the chat yourself.
library;

export 'src/agui_chat.dart' show AguiChat;
export 'src/agui_transport.dart' show AgUiTransport;
