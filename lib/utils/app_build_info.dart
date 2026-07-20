/// Build-ID der Web-App (wird beim Vercel-Build gesetzt).
const String kAppBuildId = String.fromEnvironment(
  'APP_BUILD_ID',
  defaultValue: 'dev',
);

/// true, wenn die Server-Version neuer ist als die laufende App.
bool isRemoteBuildNewer({
  required String localBuildId,
  required String? remoteBuildId,
}) {
  final remote = remoteBuildId?.trim() ?? '';
  if (remote.isEmpty) return false;
  final local = localBuildId.trim();
  if (local.isEmpty || local == 'dev') {
    // Dev-Builds sollen Updates anzeigen, sobald eine echte ID kommt.
    return remote != 'dev';
  }
  return remote != local;
}
