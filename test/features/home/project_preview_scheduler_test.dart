import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/home/presentation/widgets/project_preview_gate.dart';
import 'package:varian/features/home/presentation/widgets/project_preview_load_scheduler.dart';

void main() {
  test('serializes preview loads so document parsing cannot overlap', () async {
    final scheduler = ProjectPreviewLoadScheduler();
    var activeLoads = 0;
    var maximumActiveLoads = 0;

    Future<int> load(int value) async {
      activeLoads += 1;
      maximumActiveLoads = maximumActiveLoads > activeLoads
          ? maximumActiveLoads
          : activeLoads;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      activeLoads -= 1;
      return value;
    }

    final results = await Future.wait([
      scheduler.schedule(() => load(1)),
      scheduler.schedule(() => load(2)),
      scheduler.schedule(() => load(3)),
    ]);

    expect(results, [1, 2, 3]);
    expect(maximumActiveLoads, 1);
  });

  test('serializes the full asynchronous document load operation', () async {
    final scheduler = ProjectPreviewLoadScheduler();
    var activeLoads = 0;
    var maximumActiveLoads = 0;

    Future<String> load(String projectId) async {
      activeLoads += 1;
      maximumActiveLoads = maximumActiveLoads > activeLoads
          ? maximumActiveLoads
          : activeLoads;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      activeLoads -= 1;
      return projectId;
    }

    final results = await Future.wait([
      scheduler.schedule(() => load('project-a')),
      scheduler.schedule(() => load('project-b')),
      scheduler.schedule(() => load('project-c')),
    ]);

    expect(results, ['project-a', 'project-b', 'project-c']);
    expect(maximumActiveLoads, 1);
  });

  test('defers only Android previews so Web and desktop stay unchanged', () {
    expect(shouldDeferProjectPreview(isAndroid: true, isWeb: false), isTrue);
    expect(shouldDeferProjectPreview(isAndroid: true, isWeb: true), isFalse);
    expect(shouldDeferProjectPreview(isAndroid: false, isWeb: false), isFalse);
  });
}
