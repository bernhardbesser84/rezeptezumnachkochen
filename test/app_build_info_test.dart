import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/utils/app_build_info.dart';

void main() {
  test('Remote-Build gilt als neuer wenn ID anders ist', () {
    expect(
      isRemoteBuildNewer(localBuildId: 'aaa111', remoteBuildId: 'bbb222'),
      isTrue,
    );
    expect(
      isRemoteBuildNewer(localBuildId: 'aaa111', remoteBuildId: 'aaa111'),
      isFalse,
    );
    expect(
      isRemoteBuildNewer(localBuildId: 'aaa111', remoteBuildId: null),
      isFalse,
    );
    expect(
      isRemoteBuildNewer(localBuildId: 'dev', remoteBuildId: 'bbb222'),
      isTrue,
    );
  });
}
