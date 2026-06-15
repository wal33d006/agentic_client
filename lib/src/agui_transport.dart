/// Bridges the AG-UI event stream from our backend into genui's [Transport]
/// interface. The backend emits standard AG-UI events; A2UI ops travel inside
/// `TOOL_CALL_RESULT.content` under the `a2ui_operations` envelope (the
/// CopilotKit convention used by `a2ui.render(...)` on the Python side).
///
/// This adapter:
///   • posts each user message to `${baseUrl}/` via AgUiClient
///   • forwards completed assistant text bubbles to `incomingText`
///   • unwraps `a2ui_operations`, parses each op into an `A2uiMessage`, and
///     pushes them to `incomingMessages` — which genui's SurfaceController
///     consumes to build/update Surfaces
library;

import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart' as agui;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:genai_primitives/genai_primitives.dart' as gp;
import 'package:genui/genui.dart';

class AgUiTransport implements Transport {
  AgUiTransport({
    required this.baseUrl,
    this.catalogDescription,
    this.uiRenderToolNames = const {},
    this.markdownA2uiLangTag,
  }) : _client = agui.AgUiClient(config: agui.AgUiClientConfig(baseUrl: baseUrl));

  /// e.g. `http://localhost:8123`. We POST to `$baseUrl/` (trailing slash
  /// — the backend mounts the graph at root).
  final String baseUrl;

  /// Optional free-text description of the catalog we expose to the agent.
  /// The backend's `generate_a2ui` tool reads this from `state.copilotkit.context`
  /// to know which Flutter widgets it can pick. Leave null for fixed-schema
  /// tools (search_flights), which carry their own schema on the backend.
  final String? catalogDescription;

  /// Tool names whose ARGS carry an A2UI payload (the "ghost tool call"
  /// pattern). On TOOL_CALL_END for one of these, the accumulated args JSON
  /// is parsed as A2UI and a synthesized ToolMessage is appended to history
  /// so the next turn sees the call as resolved.
  final Set<String> uiRenderToolNames;

  /// Fenced code-block language tag to intercept inside assistant text. When
  /// non-null (e.g. `'a2ui'`), blocks tagged ```<tag> ... ``` are stripped
  /// from the chat bubble and parsed as A2UI ops. Null disables this path.
  final String? markdownA2uiLangTag;

  final agui.AgUiClient _client;
  final _textCtrl = StreamController<String>.broadcast();
  final _msgCtrl = StreamController<A2uiMessage>.broadcast();

  /// Stable per-conversation IDs — keeps the backend's checkpointer happy.
  final String _threadId = 'thread_${DateTime.now().millisecondsSinceEpoch}';

  /// Conversation history — every prior user/assistant turn must be replayed
  /// because the backend agent is stateless across requests (the checkpointer
  /// only persists state, not message history outside the run).
  final List<agui.Message> _history = [];

  /// Tool-call IDs whose A2UI payload was already emitted via the args path,
  /// so we don't re-emit if a TOOL_CALL_RESULT later arrives for them.
  final Set<String> _consumedToolCallIds = {};

  @override
  Stream<String> get incomingText => _textCtrl.stream;

  @override
  Stream<A2uiMessage> get incomingMessages => _msgCtrl.stream;

  @override
  Future<void> sendRequest(gp.ChatMessage message) async {
    final userText = message.text;
    if (userText.isEmpty) return;

    _history.add(agui.UserMessage(id: 'msg_${DateTime.now().millisecondsSinceEpoch}', content: userText));

    final runId = 'run_${DateTime.now().millisecondsSinceEpoch}';
    final input = agui.SimpleRunAgentInput(
      threadId: _threadId,
      runId: runId,
      messages: List<agui.Message>.from(_history),
      state: const <String, dynamic>{},
      tools: const [],
      context: _buildContext(),
      forwardedProps: const <String, dynamic>{},
    );

    debugPrint(
      '[agui] → POST $baseUrl/ thread=$_threadId run=$runId '
      'history=${_history.length} user="${_trunc(userText)}"',
    );

    final assistantText = StringBuffer();
    String? assistantMsgId;
    final toolArgsById = <String, StringBuffer>{};
    final toolNamesById = <String, String>{};

    // Full URL bypasses the package's `${baseUrl}/${endpoint}` concatenation,
    // so we POST to "$baseUrl/" exactly — see backend serve.py:90.
    await for (final event in _client.runAgent('$baseUrl/', input)) {
      switch (event.eventType) {
        case agui.EventType.textMessageStart:
          assistantText.clear();
          final e = event as agui.TextMessageStartEvent;
          assistantMsgId = e.messageId;
        case agui.EventType.textMessageContent:
          final e = event as agui.TextMessageContentEvent;
          assistantText.write(e.delta);
        case agui.EventType.textMessageChunk:
          final e = event as agui.TextMessageChunkEvent;
          if (e.delta != null) assistantText.write(e.delta);
        case agui.EventType.textMessageEnd:
          var text = assistantText.toString();
          debugPrint('[agui] ← text: "${_trunc(text)}"');
          // Markdown-intercept path: pull any fenced A2UI blocks out of the
          // text and queue them, then emit text first (so the bubble shows
          // above the surface) and the ops after.
          final fencedJsonBlocks = <String>[];
          if (markdownA2uiLangTag != null) {
            text = _stripA2uiFences(text, into: fencedJsonBlocks);
            if (fencedJsonBlocks.isNotEmpty) {
              debugPrint(
                '[agui] markdown-fence intercept: '
                '${fencedJsonBlocks.length} block(s) extracted',
              );
            }
          }
          if (text.isNotEmpty) {
            _textCtrl.add(text);
            _history.add(
              agui.AssistantMessage(
                id: assistantMsgId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
                content: text,
              ),
            );
          }
          for (final json in fencedJsonBlocks) {
            _emitA2uiOpsFromJsonString(json, source: 'markdown');
          }

        case agui.EventType.toolCallStart:
          final e = event as agui.ToolCallStartEvent;
          toolNamesById[e.toolCallId] = e.toolCallName;
          toolArgsById[e.toolCallId] = StringBuffer();
          debugPrint('[agui] ← tool-call start: ${e.toolCallName} id=${e.toolCallId}');
        case agui.EventType.toolCallArgs:
          final e = event as agui.ToolCallArgsEvent;
          toolArgsById.putIfAbsent(e.toolCallId, StringBuffer.new).write(e.delta);
        case agui.EventType.toolCallChunk:
          final e = event as agui.ToolCallChunkEvent;
          if (e.toolCallId != null && e.delta != null) {
            toolArgsById.putIfAbsent(e.toolCallId!, StringBuffer.new).write(e.delta);
          }
        case agui.EventType.toolCallEnd:
          // Out-of-band path: if the call's name is in `uiRenderToolNames`,
          // the args ARE the A2UI payload. Emit them, then synthesize a
          // ToolMessage so the agent treats the call as resolved next turn.
          final e = event as agui.ToolCallEndEvent;
          final name = toolNamesById[e.toolCallId];
          final args = toolArgsById[e.toolCallId]?.toString() ?? '';
          debugPrint(
            '[agui] ← tool-call end: $name id=${e.toolCallId} '
            'args="${_trunc(args)}"',
          );
          if (name != null && uiRenderToolNames.contains(name)) {
            _emitA2uiOpsFromJsonString(args, source: 'tool-args');
            _history.add(
              agui.ToolMessage(
                id: 'msg_tool_${DateTime.now().millisecondsSinceEpoch}',
                toolCallId: e.toolCallId,
                content: '{"status":"rendered"}',
              ),
            );
            _consumedToolCallIds.add(e.toolCallId);
          }

        case agui.EventType.toolCallResult:
          final e = event as agui.ToolCallResultEvent;
          debugPrint(
            '[agui] ← tool-call result: id=${e.toolCallId} '
            'content="${_trunc(e.content)}"',
          );
          // Skip the tool-result envelope if the args path already handled
          // this call — otherwise we'd render the same surface twice.
          if (_consumedToolCallIds.remove(e.toolCallId)) {
            debugPrint('[agui]   (skipped — already emitted via tool-args)');
            break;
          }
          _emitA2uiOpsFromJsonString(e.content, source: 'tool-result');
          // Record the tool call + result in history so follow-up turns can
          // see what the assistant did.
          _history.add(
            agui.ToolMessage(
              id: 'msg_tool_${DateTime.now().millisecondsSinceEpoch}',
              toolCallId: e.toolCallId,
              content: e.content,
            ),
          );

        case agui.EventType.runError:
          final e = event as agui.RunErrorEvent;
          debugPrint('[agui] ← run error: ${e.message}');
          _textCtrl.add('⚠️ ${e.message}');

        default:
          // RUN_STARTED / RUN_FINISHED / STATE_* / STEP_* / etc.
          // Add handlers here when we need them (e.g. STATE_DELTA for the
          // todos pattern).
          break;
      }
    }
  }

  /// Parses a JSON string and emits A2UI ops from it. Accepts either:
  ///   • the CopilotKit envelope `{ "a2ui_operations": [op, op, ...] }`, or
  ///   • a bare op like `{ "createSurface": {...} }` /
  ///     `{ "updateComponents": {...} }` (used by the args / markdown paths).
  ///
  /// [source] is purely for logging — identifies which path picked this up
  /// (`tool-result`, `tool-args`, or `markdown`).
  void _emitA2uiOpsFromJsonString(String content, {required String source}) {
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return; // not JSON → not A2UI
    }
    if (decoded is! Map<String, dynamic>) return;

    final envelope = decoded['a2ui_operations'];
    if (envelope is List) {
      debugPrint('[agui] A2UI ops via $source: envelope, ${envelope.length} op(s)');
      for (final op in envelope) {
        if (op is Map<String, dynamic>) _emitSingleOp(op, source: source);
      }
      return;
    }
    if (_looksLikeOp(decoded)) {
      debugPrint('[agui] A2UI op via $source: bare ${_opKind(decoded)}');
      _emitSingleOp(decoded, source: source);
    }
  }

  void _emitSingleOp(Map<String, dynamic> op, {required String source}) {
    debugPrint('[agui]   op[$source] ${_opKind(op)} ${_opSummary(op)}');
    // A2UI v0.9 ops are tagged with `version: "v0.9"` at the top level.
    final tagged = {'version': 'v0.9', ...op};
    try {
      _msgCtrl.add(A2uiMessage.fromJson(tagged));
    } catch (err, st) {
      // Surface validation errors as a chat bubble so they're visible.
      // Continue with the rest of the ops — one malformed component
      // shouldn't drop the whole surface.
      final hint = _diagnoseBadOp(op);
      _textCtrl.add('⚠️ A2UI parse error: $err${hint == null ? "" : "\n$hint"}');
      debugPrint('[agui] A2UI parse failed for op $op\n$st');
    }
  }

  String _opKind(Map<String, dynamic> op) {
    for (final k in const ['createSurface', 'updateComponents', 'deleteSurface', 'updateData']) {
      if (op.containsKey(k)) return k;
    }
    return '<unknown>';
  }

  String _opSummary(Map<String, dynamic> op) {
    final body = op[_opKind(op)];
    if (body is! Map) return '';
    final surfaceId = body['surfaceId'];
    final catalogId = body['catalogId'];
    final components = body['components'];
    final parts = <String>[
      if (surfaceId != null) 'surfaceId=$surfaceId',
      if (catalogId != null) 'catalogId=$catalogId',
      if (components is List) 'components=${components.length}',
    ];
    return parts.join(' ');
  }

  static String _trunc(String s, [int n = 200]) => s.length <= n ? s : '${s.substring(0, n)}…(+${s.length - n})';

  bool _looksLikeOp(Map<String, dynamic> m) =>
      m.containsKey('createSurface') ||
      m.containsKey('updateComponents') ||
      m.containsKey('deleteSurface') ||
      m.containsKey('updateData');

  /// Extracts ```<tag> ... ``` blocks from [text], appends each block's body
  /// to [into] as a raw JSON string, and returns the text with the blocks
  /// removed.
  String _stripA2uiFences(String text, {required List<String> into}) {
    final tag = RegExp.escape(markdownA2uiLangTag!);
    // `(.*?)` is non-greedy so each block is matched independently when the
    // text contains more than one fence.
    final pattern = RegExp('```$tag\\s*(.*?)\\s*```', dotAll: true);
    final cleaned = text.replaceAllMapped(pattern, (m) {
      into.add(m.group(1) ?? '');
      return '';
    });
    return cleaned.trim();
  }

  /// Best-effort hint about why an op was rejected. The agent's most common
  /// mistakes: uses `type` instead of `component`, wraps properties in `props`,
  /// or invents snake_case component names.
  String? _diagnoseBadOp(Map<String, dynamic> op) {
    final body = op['updateComponents'];
    if (body is! Map) return null;
    final components = body['components'];
    if (components is! List) return null;
    final issues = <String>{};
    for (final c in components) {
      if (c is! Map) continue;
      if (c.containsKey('type') && !c.containsKey('component')) {
        issues.add('uses "type" — must be "component"');
      }
      if (c.containsKey('props')) {
        issues.add('wraps properties under "props" — must be flat');
      }
      final name = (c['component'] ?? c['type']) as Object?;
      if (name is String && name.contains('_')) {
        issues.add('snake_case name "$name" — must be PascalCase');
      }
    }
    return issues.isEmpty ? null : 'hint: ${issues.join("; ")}';
  }

  /// Builds the AG-UI `context` array shipped on each request.
  ///
  /// `LangGraphAGUIAgent.langgraph_default_merge_state` on the backend reads
  /// the top-level AG-UI `context` field and writes it to
  /// `state.copilotkit.context`. That's what the demo agent's `generate_a2ui`
  /// tool reads to learn which Flutter widgets it can emit.
  List<agui.Context> _buildContext() {
    if (catalogDescription == null) return const [];
    return [agui.Context(description: 'Available A2UI components on this Flutter client.', value: catalogDescription!)];
  }

  @override
  void dispose() {
    _textCtrl.close();
    _msgCtrl.close();
    _client.close();
  }
}
