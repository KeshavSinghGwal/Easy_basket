// Conditional import - exports the right implementation based on platform
// dart.library.html = web browser, dart.library.io = native (mobile/desktop)
export 'notification_service_mobile.dart' if (dart.library.html) 'notification_service_web_stub.dart';

