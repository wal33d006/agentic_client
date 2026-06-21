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
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, debugPrint;
import 'package:genai_primitives/genai_primitives.dart' as gp;
import 'package:genui/genui.dart';

class AgUiTransport implements Transport {
  AgUiTransport({required this.baseUrl, this.catalogDescription, this.uiRenderToolNames = const {}})
    : _client = agui.AgUiClient(config: agui.AgUiClientConfig(baseUrl: baseUrl));

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

  final agui.AgUiClient _client;
  final _textCtrl = StreamController<String>.broadcast();
  final _msgCtrl = StreamController<A2uiMessage>.broadcast();
  final _eventCtrl = StreamController<String>.broadcast();

  /// High-level lifecycle events emitted during a turn — one short phrase per
  /// step (tool calls, surface renders, etc.). UIs can subscribe and show
  /// these inline instead of a single loader.
  Stream<String> get agentEvents => _eventCtrl.stream;

  /// Client-side mirror of the agent's shared state. The backend is the
  /// source of truth: it is reset by STATE_SNAPSHOT events and patched by
  /// STATE_DELTA events. The mirror is echoed back as
  /// `SimpleRunAgentInput.state` on the next turn so the agent can continue
  /// from it across requests.
  final ValueNotifier<Map<String, dynamic>> _state = ValueNotifier(<String, dynamic>{});

  /// Read-only listenable mirror of the agent's shared state. Wrap with a
  /// `ValueListenableBuilder` to rebuild widgets when the agent mutates it.
  ValueListenable<Map<String, dynamic>> get state => _state;

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
    // genUI converts catalog button taps into ChatMessages that carry a
    // `UiInteractionPart` (mime: vnd.genui.interaction+json) instead of plain
    // text. We forward those out-of-band via `forwarded_props.pending_action`
    // — they are not chat messages and should not be appended to `_history`.
    final pendingAction = _extractPendingAction(message.parts);

    if (userText.isEmpty && pendingAction == null) return;

    if (userText.isNotEmpty) {
      _history.add(agui.UserMessage(id: 'msg_${DateTime.now().millisecondsSinceEpoch}', content: userText));
    }

    final forwardedProps = <String, dynamic>{if (pendingAction != null) 'pending_action': pendingAction};

    final runId = 'run_${DateTime.now().millisecondsSinceEpoch}';
    final input = agui.SimpleRunAgentInput(
      threadId: _threadId,
      runId: runId,
      messages: List<agui.Message>.from(_history),
      // Round-trip the mirrored state so the agent can resume from it.
      // The backend remains the source of truth; the client never mutates
      // this map locally.
      state: Map<String, dynamic>.from(_state.value),
      tools: const [],
      context: _buildContext(),
      forwardedProps: forwardedProps,
    );

    if (pendingAction != null) {
      debugPrint(
        '[agui] → POST $baseUrl/ thread=$_threadId run=$runId '
        'action=${pendingAction['name']} '
        'source=${pendingAction['sourceComponentId']}',
      );
      _eventCtrl.add('User triggered ${pendingAction['name']}');
    } else {
      debugPrint(
        '[agui] → POST $baseUrl/ thread=$_threadId run=$runId '
        'history=${_history.length} user="${_trunc(userText)}"',
      );
    }

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
          final text = assistantText.toString();
          debugPrint('[agui] ← text: "${_trunc(text)}"');
          if (text.isNotEmpty) {
            _textCtrl.add(text);
            _history.add(
              agui.AssistantMessage(
                id: assistantMsgId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
                content: text,
              ),
            );
          }

        case agui.EventType.toolCallStart:
          final e = event as agui.ToolCallStartEvent;
          toolNamesById[e.toolCallId] = e.toolCallName;
          toolArgsById[e.toolCallId] = StringBuffer();
          debugPrint('[agui] ← tool-call start: ${e.toolCallName} id=${e.toolCallId}');
          _eventCtrl.add('Calling ${e.toolCallName}…');
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

        case agui.EventType.stateSnapshot:
          final e = event as agui.StateSnapshotEvent;
          final snap = e.snapshot;
          if (snap is Map) {
            _state.value = Map<String, dynamic>.from(snap);
            debugPrint('[agui] ← state snapshot: ${_state.value.keys.length} key(s)');
            _eventCtrl.add('State synced');
          } else {
            debugPrint('[agui] ← state snapshot ignored: not a Map ($snap)');
          }

        case agui.EventType.stateDelta:
          final e = event as agui.StateDeltaEvent;
          try {
            final next = _applyJsonPatch(_state.value, e.delta);
            _state.value = next;
            debugPrint('[agui] ← state delta: ${e.delta.length} op(s)');
            _eventCtrl.add('State updated');
          } catch (err) {
            debugPrint('[agui] ← state delta failed: $err');
            _textCtrl.add('⚠️ State patch failed: $err');
          }

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
  ///     `{ "updateComponents": {...} }` (used by the ghost tool-call args
  ///     path).
  ///
  /// [source] is purely for logging — identifies which path picked this up
  /// (`tool-result` or `tool-args`).
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
      _eventCtrl.add(_friendlyOpLabel(op));
    } catch (err, st) {
      // Surface validation errors as a chat bubble so they're visible.
      // Continue with the rest of the ops — one malformed component
      // shouldn't drop the whole surface.
      final hint = _diagnoseBadOp(op);
      _textCtrl.add('⚠️ A2UI parse error: $err${hint == null ? "" : "\n$hint"}');
      _eventCtrl.add('⚠️ A2UI parse error');
      debugPrint('[agui] A2UI parse failed for op $op\n$st');
    }
  }

  String _friendlyOpLabel(Map<String, dynamic> op) {
    switch (_opKind(op)) {
      case 'createSurface':
        return 'Creating surface…';
      case 'updateComponents':
        final body = op['updateComponents'];
        if (body is Map) {
          final components = body['components'];
          if (components is List) {
            return 'Rendering ${components.length} '
                'component${components.length == 1 ? '' : 's'}';
          }
        }
        return 'Rendering UI';
      case 'deleteSurface':
        return 'Removing surface';
      case 'updateDataModel':
        return 'Updating data';
      default:
        return 'Applying UI change';
    }
  }

  String _opKind(Map<String, dynamic> op) {
    for (final k in const ['createSurface', 'updateComponents', 'deleteSurface', 'updateDataModel']) {
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

  // ─── RFC 6902 JSON Patch (small inline impl) ───────────────────────────────

  /// Applies a list of JSON Patch operations to [target] and returns a deep
  /// copy of the resulting map. Supports `add`, `remove`, `replace`, `move`,
  /// `copy`, and `test`. Throws [FormatException] on invalid input.
  static Map<String, dynamic> _applyJsonPatch(Map<String, dynamic> target, List<dynamic> ops) {
    final next = _deepCopy(target) as Map<String, dynamic>;
    for (final raw in ops) {
      if (raw is! Map) {
        throw const FormatException('patch op must be a JSON object');
      }
      final op = raw['op'] as String?;
      final path = raw['path'] as String?;
      if (op == null || path == null) {
        throw FormatException('patch op missing op/path: $raw');
      }
      switch (op) {
        case 'add':
          _setAt(next, path, _deepCopy(raw['value']), insert: true);
        case 'remove':
          _removeAt(next, path);
        case 'replace':
          _setAt(next, path, _deepCopy(raw['value']));
        case 'move':
          final from = raw['from'] as String?;
          if (from == null) throw FormatException('move op missing `from`: $raw');
          final value = _removeAt(next, from);
          _setAt(next, path, value, insert: true);
        case 'copy':
          final from = raw['from'] as String?;
          if (from == null) throw FormatException('copy op missing `from`: $raw');
          _setAt(next, path, _deepCopy(_getAt(next, from)), insert: true);
        case 'test':
          if (!_deepEquals(_getAt(next, path), raw['value'])) {
            throw FormatException('test op failed at $path');
          }
        default:
          throw FormatException('unknown JSON patch op: $op');
      }
    }
    return next;
  }

  /// Splits a JSON Pointer (RFC 6901) into segments, unescaping `~1`→`/` and
  /// `~0`→`~`. The empty pointer "" addresses the whole document.
  static List<String> _splitPointer(String pointer) {
    if (pointer.isEmpty) return const [];
    if (!pointer.startsWith('/')) {
      throw FormatException('invalid JSON pointer (must start with "/"): $pointer');
    }
    return pointer
        .substring(1)
        .split('/')
        .map((s) => s.replaceAll('~1', '/').replaceAll('~0', '~'))
        .toList(growable: false);
  }

  static Object? _getAt(Object? root, String pointer) {
    var current = root;
    for (final segment in _splitPointer(pointer)) {
      if (current is Map) {
        current = current[segment];
      } else if (current is List) {
        current = current[int.parse(segment)];
      } else {
        throw FormatException('cannot traverse "$segment" in $current');
      }
    }
    return current;
  }

  /// Writes [value] at [pointer]. When [insert] is true and the parent is a
  /// list, the value is inserted at the index (matching JSON Patch `add`
  /// semantics); otherwise the existing slot is overwritten.
  static void _setAt(Object root, String pointer, Object? value, {bool insert = false}) {
    final segments = _splitPointer(pointer);
    if (segments.isEmpty) {
      throw const FormatException('cannot set at root pointer ""');
    }
    Object parent = root;
    for (var i = 0; i < segments.length - 1; i++) {
      final s = segments[i];
      if (parent is Map) {
        parent = parent[s] as Object;
      } else if (parent is List) {
        parent = parent[int.parse(s)] as Object;
      } else {
        throw FormatException('cannot traverse "$s" in $parent');
      }
    }
    final last = segments.last;
    if (parent is Map) {
      (parent as Map<String, dynamic>)[last] = value;
    } else if (parent is List) {
      final list = parent;
      if (last == '-') {
        list.add(value);
      } else {
        final idx = int.parse(last);
        if (insert) {
          list.insert(idx, value);
        } else {
          list[idx] = value;
        }
      }
    } else {
      throw FormatException('cannot set on $parent');
    }
  }

  static Object? _removeAt(Object root, String pointer) {
    final segments = _splitPointer(pointer);
    if (segments.isEmpty) {
      throw const FormatException('cannot remove at root pointer ""');
    }
    Object parent = root;
    for (var i = 0; i < segments.length - 1; i++) {
      final s = segments[i];
      if (parent is Map) {
        parent = parent[s] as Object;
      } else if (parent is List) {
        parent = parent[int.parse(s)] as Object;
      } else {
        throw FormatException('cannot traverse "$s" in $parent');
      }
    }
    final last = segments.last;
    if (parent is Map) {
      return (parent as Map<String, dynamic>).remove(last);
    }
    if (parent is List) {
      return (parent).removeAt(int.parse(last));
    }
    throw FormatException('cannot remove on $parent');
  }

  static Object? _deepCopy(Object? value) {
    if (value is Map) {
      return <String, dynamic>{for (final entry in value.entries) entry.key as String: _deepCopy(entry.value)};
    }
    if (value is List) {
      return [for (final v in value) _deepCopy(v)];
    }
    return value;
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  bool _looksLikeOp(Map<String, dynamic> m) =>
      m.containsKey('createSurface') ||
      m.containsKey('updateComponents') ||
      m.containsKey('deleteSurface') ||
      m.containsKey('updateDataModel');

  /// Pulls the latest A2UI `action` payload from any [UiInteractionPart]s in
  /// [parts] (created by genUI's `SurfaceController.handleUiEvent` when the
  /// user interacts with a rendered surface).
  ///
  /// Returns `null` if no interaction parts are present. When multiple
  /// interactions arrive in a single message (rare), the last one wins —
  /// `SurfaceController` ships one per event, so this only matters if a
  /// consumer manually merges messages.
  Map<String, dynamic>? _extractPendingAction(List<gp.StandardPart> parts) {
    final interactions = parts.uiInteractionParts;
    if (interactions.isEmpty) return null;

    Map<String, dynamic>? latest;
    for (final part in interactions) {
      try {
        final decoded = jsonDecode(part.interaction);
        if (decoded is Map<String, dynamic>) {
          // genUI wraps the action under `{version: 'v0.9', action: {...}}`.
          // Unwrap so the backend sees a flat action object.
          final action = decoded['action'];
          if (action is Map<String, dynamic>) {
            latest = action;
          } else if (decoded.containsKey('name')) {
            // Tolerate already-unwrapped payloads.
            latest = decoded;
          }
        }
      } catch (err) {
        debugPrint('[agui] failed to parse UiInteractionPart: $err');
      }
    }
    return latest;
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
    _eventCtrl.close();
    _state.dispose();
    _client.close();
  }
}
