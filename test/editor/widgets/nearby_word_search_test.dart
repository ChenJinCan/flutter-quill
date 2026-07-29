import 'package:flutter_quill/src/editor/widgets/nearby_word_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search offsets stay within text when tap position exceeds its length',
      () {
    final offsets = boundedNearbyWordSearchOffsets(
      positionOffset: 99,
      textLength: 5,
    ).toList();

    expect(offsets, isNotEmpty);
    expect(offsets, everyElement(inInclusiveRange(0, 4)));
    expect(offsets, contains(4));
  });

  test('empty text has no searchable offsets', () {
    expect(
      boundedNearbyWordSearchOffsets(
        positionOffset: 1,
        textLength: 0,
      ),
      isEmpty,
    );
  });
}
