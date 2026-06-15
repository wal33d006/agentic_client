/// AG-UI chat for Flutter.
///
/// A drop-in chat widget that talks to any AG-UI-compatible agent backend
/// and renders the agent's generative-UI surfaces (A2UI v0.9) using a
/// genui [Catalog] of Flutter widgets you provide.
///
/// Typical usage:
///
/// ```dart
/// import 'package:flutter/material.dart';
/// import 'package:genui/genui.dart';
/// import 'agui_chat/agui_chat.dart';
///
/// Scaffold(
///   appBar: AppBar(title: const Text('Chat')),
///   body: AguiChat(
///     baseUrl: 'http://localhost:8123',
///     catalog: Catalog(
///       [BasicCatalogItems.text, BasicCatalogItems.column, /* ... */],
///       catalogId: 'my-app.catalog',
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
