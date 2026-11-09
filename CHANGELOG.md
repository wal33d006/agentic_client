## Unreleased

* **Breaking:** Move from `genui` to the A2UI Dart SDKs, `a2ui_core` and
  `a2ui_flutter`, since `genui` will be deprecated. Apps depend on
  `a2ui_flutter` instead of `genui`.
  * `AguiChat.catalog` takes an `a2ui_flutter` `CatalogImplementation` instead
    of a genui `Catalog`, such as `basicCatalog().derive(...)` from
    `package:a2ui_flutter/v0_9/basic_catalog.dart`. Custom widgets are
    `ComponentImplementation`s instead of `CatalogItem`s.
  * `AgUiTransport` no longer implements genui's `Transport`. `sendRequest`
    takes the user's text as a `String` instead of a `ChatMessage`, and the new
    `sendAction` sends a UI action as `forwarded_props.pending_action`, with
    its `timestamp` in UTC.
  * `AgUiTransport.incomingMessages` emits `a2ui_core`
    `AgentToRendererMessage`s instead of `A2uiMessage`s.
* Surfaces check each A2UI op before applying it. An op is rejected, and
  logged with `debugPrint`, when its `catalogId` is not the catalog's `id`,
  when it updates a surface that does not exist yet, or when a component in it
  does not match its schema. Components of unknown types render nothing.
* Update the example app to `a2ui_flutter`.

## 1.0.0

* Stable version

## 0.0.13

* Add custom event for approval step

## 0.0.12

* Add gif example to readme

## 0.0.11

* Collapsed non-user AGUI events in a dropdown

## 0.0.10

* Removed unused import

## 0.0.9

* Removed unnecessary tags, update examples

## 0.0.8

* Update docs

## 0.0.7

* Added support for shared state between agent and UI

## 0.0.6

* Added inline AGUI events to UI

## 0.0.5

* Added support for standard AGUI backends

## 0.0.4

* Updated design

## 0.0.3

* Updated dart sdk version

## 0.0.2

* Updated readme

## 0.0.1

* Dart chat client for rendering Flutter widgets over A2UI protocol leveraging AGUI streaming  
