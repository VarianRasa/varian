import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/ai/domain/ai_workflow_contract.dart';

void main() {
  test('mask editor contract supports add and undo', () {
    const mask = AIMaskDocument(
      width: 100,
      height: 80,
      operation: AIMaskOperation.inpaint,
    );
    final edited = mask.addStroke(const AIMaskStroke(points: [], width: 20));

    expect(edited.strokes, hasLength(1));
    expect(edited.undo().strokes, isEmpty);
  });

  test('variant compare selection is bounded to two outputs', () {
    const variants = AIVariantSet(
      id: 'group-1',
      variants: [
        AIOutputVariant(id: 'a', index: 0),
        AIOutputVariant(id: 'b', index: 1),
        AIOutputVariant(id: 'c', index: 2),
      ],
    );
    final selected = variants
        .toggleCompare('a')
        .toggleCompare('b')
        .toggleCompare('c')
        .compareSelection;

    expect(selected, hasLength(2));
  });

  test('quota and provenance expose user-facing workflow state', () {
    const quota = AIQuotaSnapshot(
      scope: 'workspace',
      used: 3,
      limit: 10,
      unit: 'credits',
    );
    const provenance = AIProvenanceNotice(
      provider: 'local',
      model: 'test-model',
      license: 'CC-BY',
    );

    expect(quota.allows(7), isTrue);
    expect(quota.remaining, 7);
    expect(provenance.disclosure, contains('CC-BY'));
  });
}
