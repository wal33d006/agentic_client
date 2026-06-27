# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`agentic_client` is a **published Flutter package** (pub.dev, currently `0.0.12`). It exposes a single drop-in chat widget, `AguiChat`, that talks to any [AG-UI](https://docs.ag-ui.com)-compatible agent backend over HTTP and renders the agent's generative-UI surfaces ([A2UI v0.9](https://a2ui.org)) inline, using a [genui](https://pub.dev/packages/genui) `Catalog` of Flutter widgets the host app supplies.

It is a library, not an app — the runnable demo lives in `/example`.

## Commands

```sh
flutter pub get                 # install deps (run in repo root and in example/)
flutter analyze                 # lint (flutter_lints via analysis_options.yaml)
dart format .                   # format (note: lines are formatted to ~120 cols)
flutter test                    # run package tests (test/ — currently a stub)
flutter test test/agentic_client_test.dart --plain-name 'name of test'   # single test

# Run the example app against a backend (defaults to http://localhost:8123):
cd example && flutter run --dart-define=AGENT_URL=http://localhost:8123
```

Releasing: bump `version` in `pubspec.yaml` and add a matching `## x.y.z` entry to `CHANGELOG.md` (these are the two files touched on every release; see git history).

## Architecture

The whole package is two source files plus a barrel (`lib/agentic_client.dart`, which exports only `AguiChat` and `AgUiTransport`).

### `lib/src/agui_chat.dart` — `AguiChat` widget (the public surface)

A `StatefulWidget` that owns, for its lifetime, the three genui objects that make generative UI work:

- `SurfaceController(catalogs: [catalog])` — builds/updates A2UI `Surface`s.
- `AgUiTransport` — the transport (see below).
- `Conversation(controller, transport)` — genui's glue between the two.

It keeps a flat `List<_ChatItem>` log (`_UserBubble` / `_AssistantBubble` / `_SurfaceItem` / `_EventGroup` / `_InterruptItem`) and renders it as a `ListView`. Key non-obvious details:

- **Waiting state comes from `_conversation.state` (a notifier), NOT from events.** A click that only triggers `updateDataModel` ops emits no `ConversationComponentsUpdated`, so relying on events alone leaves the loader spinning forever. The notifier is authoritative.
- Agent events (when `showAgentEvents: true`) are coalesced into the trailing `_EventGroup` so each batch renders as one collapsible row, not a wall of grey lines.
- **Interrupts bypass `Conversation`.** A backend `interrupt(...)` arrives on `_transport.interrupts`, adds an `_InterruptItem`, and is answered via `_transport.resume(...)` directly. Because that path doesn't go through `Conversation.sendRequest`, the widget manages `_waiting` itself around the resume call (the conversation notifier won't flip for it).
- All visuals read from `Theme.of(context)` — no package-side color opinions; drop it in any themed `MaterialApp`.

### `lib/src/agui_transport.dart` — `AgUiTransport implements genui Transport`

This is where the protocol lives. It wraps `ag_ui`'s `AgUiClient`, POSTs each turn to `"$baseUrl/"` (trailing slash is deliberate — the backend mounts the graph at root), and consumes the AG-UI event stream, translating it into genui's `Transport` interface (`incomingText`, `incomingMessages`). Things to know before editing:

- **The backend is stateless across requests.** `_history` (the full list of `ag_ui.Message`s) is replayed on every turn, and the mirrored `state` is round-tripped back as `SimpleRunAgentInput.state`. Never mutate `_state` locally — the backend is the source of truth.
- **A2UI ops have two ingest paths** (both land in `_emitA2uiOpsFromJsonString`):
  1. **Tool-result envelope** (always on): ops arrive in `TOOL_CALL_RESULT.content` under an `a2ui_operations` array (the CopilotKit convention).
  2. **Ghost tool-call args** (`uiRenderToolNames`): for those tool names, the `TOOL_CALL_ARGS` JSON *is* the A2UI payload; the client emits it and synthesizes a `ToolMessage` back into `_history` so the next turn sees the call as resolved. `_consumedToolCallIds` dedupes so a later `TOOL_CALL_RESULT` for the same call isn't rendered twice.
- **Shared state** is mirrored via `STATE_SNAPSHOT` (full reset) and `STATE_DELTA` (RFC 6902 JSON Patch). The JSON Patch applier (`_applyJsonPatch` and the `_setAt`/`_removeAt`/`_getAt` JSON-Pointer helpers) is a small hand-rolled implementation inside this file — no external dependency.
- **UI interactions are out-of-band, not chat messages.** When a user taps a catalog `Button`, genui delivers a `ChatMessage` carrying a `UiInteractionPart`. `_extractPendingAction` pulls the action out and the transport packs it into `forwarded_props.pending_action` instead of appending it to `_history`. The backend's pre-LLM node reads `state["pending_action"]`.
- **Human-in-the-loop interrupts.** When the backend graph calls LangGraph's `interrupt(value)` the run pauses and `ag_ui_langgraph` emits a `CUSTOM` AG-UI event named `on_interrupt`. The transport's `custom` case pushes that payload onto the `interrupts` stream; `resume(decision)` continues the paused graph by POSTing `forwarded_props.command.resume` (NOT a new chat message). Both `sendRequest` and `resume` funnel through the shared `_consumeRun(input)` loop. The widget renders an approval card from the payload and calls `resume({'approved': true|false})`.
- `_diagnoseBadOp` surfaces the agent's three most common A2UI mistakes (using `type` instead of `component`, nesting props under `props`, snake_case component names) as chat bubbles — keep it in sync if the wire format changes.
- Extensive `debugPrint('[agui] …')` tracing throughout — the main observability tool when debugging a backend conversation.

### The contract with the agent backend

The agent must know the exact A2UI wire format. `catalogDescription` (passed by the host app) is shipped to the agent on every request via the AG-UI `context` field, and the backend writes it to `state.copilotkit.context`. **`example/lib/catalog.dart` (`exampleCatalogDescription`) is the canonical, fully-worked spec of that wire format** — component shapes, `pending_action` names, path bindings, and the counter/cart/restaurant interaction flows. Read it to understand what the backend and the catalog widgets must agree on. The custom catalog items there (`ProductCard`, `WeatherTile`, `Stat`, plus cart/restaurant flows) are the reference for how host apps wire `CatalogItem`s with `BoundString`/path bindings.

## Dependencies

Built directly on `ag_ui` (AG-UI transport/event types), `genui` (A2UI surfaces, `SurfaceController`, `Conversation`, `Catalog`, `Transport`), and `genai_primitives` (`ChatMessage`, parts). Changes to A2UI op handling almost always involve reading the genui API for `A2uiMessage` and `Surface`.
