/// Serializes project preview document loads across the home library.
///
/// Preview documents can be large enough for JSON decoding and hydration to
/// block the first Android frames when every card starts at once. The queue
/// keeps one load active and yields between cards while preserving each card's
/// result and error.
class ProjectPreviewLoadScheduler {
  Future<void> _tail = Future<void>.value();

  Future<T> schedule<T>(Future<T> Function() operation) {
    final next = _tail.then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      return operation();
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
