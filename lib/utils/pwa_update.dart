import 'pwa_update_stub.dart'
    if (dart.library.html) 'pwa_update_web.dart' as impl;

export 'app_build_info.dart';

Future<String?> fetchRemoteBuildId() => impl.fetchRemoteBuildId();

Future<void> applyPwaUpdate() => impl.applyPwaUpdate();

Future<void> requestServiceWorkerUpdate() => impl.requestServiceWorkerUpdate();
