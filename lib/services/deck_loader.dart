/// Reads a room's deck. Decks never change once stored, so one good read is
/// enough. A failed read (for example while the connection is being reset to
/// catch up) is tried again on the room's next update rather than treated as
/// the room ending; the server's catch-up answer can also bring the cards.
class DeckLoader<T> {
  DeckLoader(this._read);

  final Future<T?> Function(String deckId) _read;
  bool _busy = false;
  bool _loaded = false;

  bool get loaded => _loaded;

  /// The cards arrived some other way.
  void markLoaded() => _loaded = true;

  Future<void> load(String deckId, void Function(T cards) onLoaded) async {
    if (_loaded || _busy) return;
    _busy = true;
    try {
      final cards = await _read(deckId);
      if (cards != null && !_loaded) {
        _loaded = true;
        onLoaded(cards);
      }
    } catch (_) {
      // Tried again on the next room update.
    } finally {
      _busy = false;
    }
  }
}
