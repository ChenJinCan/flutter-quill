Iterable<int> boundedNearbyWordSearchOffsets({
  required int positionOffset,
  required int textLength,
  int maxDistance = 10,
}) sync* {
  if (textLength <= 0 || maxDistance < 0) return;

  final anchor = positionOffset.clamp(0, textLength - 1);
  for (var distance = 0; distance <= maxDistance; distance++) {
    final rightOffset = anchor + distance;
    if (rightOffset < textLength) {
      yield rightOffset;
    }

    if (distance == 0) continue;
    final leftOffset = anchor - distance;
    if (leftOffset >= 0) {
      yield leftOffset;
    }
  }
}
