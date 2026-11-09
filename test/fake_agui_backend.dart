import 'dart:convert';
import 'dart:io';

/// A local AG-UI backend that answers the first run with [events] as
/// server-sent events, and later runs with no events. It records each
/// request body in [requests].
class FakeAguiBackend {
  FakeAguiBackend._(this._server, this.events) {
    _server.listen((request) async {
      requests.add(jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>);
      request.response.headers.contentType = ContentType('text', 'event-stream');
      for (final event in [
        {'type': 'RUN_STARTED', 'threadId': 't', 'runId': 'r'},
        if (requests.length == 1) ...events,
        {'type': 'RUN_FINISHED', 'threadId': 't', 'runId': 'r'},
      ]) {
        request.response.write('data: ${jsonEncode(event)}\n\n');
      }
      await request.response.close();
    });
  }

  static Future<FakeAguiBackend> start(List<Map<String, Object?>> events) async =>
      FakeAguiBackend._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), events);

  final HttpServer _server;
  final List<Map<String, Object?>> events;
  final List<Map<String, dynamic>> requests = [];

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  Future<void> close() => _server.close(force: true);
}
