import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'api.dart';

class ChatLive with WidgetsBindingObserver {
  ChatLive(this.api, this.onChange);
  final ApiClient api;
  final VoidCallback onChange;
  HubConnection? _hub;
  Timer? _retry;
  bool _closed = false;
  bool _disposed = false;
  int _epoch = 0;
  bool _connecting = false;
  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_closed ||
        _disposed ||
        _connecting ||
        _hub?.state == HubConnectionState.Connected) {
      return;
    }
    final epoch = _epoch;
    _connecting = true;
    try {
      final hub = HubConnectionBuilder()
          .withUrl(
            api.base.resolve('/hub/chat').toString(),
            options: HttpConnectionOptions(
              accessTokenFactory: () async {
                await api.get('/api/auth/me');
                return api.accessToken ?? '';
              },
            ),
          )
          .build();
      _hub = hub;
      hub.on('ChatMessageReceived', (_) => onChange());
      hub.on('ChatMessagesRead', (_) => onChange());
      hub.onclose(({error}) {
        if (!_closed && !_disposed && epoch == _epoch) _schedule();
      });
      await hub.start();
      if (_closed || _disposed || epoch != _epoch) {
        await hub.stop();
      } else {
        onChange();
      }
    } catch (_) {
      if (!_closed && !_disposed && epoch == _epoch) _schedule();
    } finally {
      _connecting = false;
      if (!_closed && !_disposed && epoch != _epoch) _schedule();
    }
  }

  void _schedule() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 10), () => unawaited(_connect()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      _closed = false;
      unawaited(_connect());
    } else {
      _epoch++;
      _closed = true;
      _retry?.cancel();
      unawaited(_hub?.stop());
      _hub = null;
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
    _closed = true;
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_hub?.stop());
    _hub = null;
  }
}
