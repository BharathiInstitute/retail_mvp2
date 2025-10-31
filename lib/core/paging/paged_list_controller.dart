import 'package:flutter/foundation.dart';

class PageState<T> {
  final List<T> items;
  final bool loading;
  final Object? error;
  final bool endReached;
  const PageState({
    this.items = const [],
    this.loading = false,
    this.error,
    this.endReached = false,
  });
}

/// A generic, ChangeNotifier-based paged list controller.
class PagedListController<T> extends ChangeNotifier {
  final Future<(List<T> page, Object? nextCursor)> Function(Object? cursor) loadPage;
  final int pageSize;
  Object? _cursor;
  bool _loading = false;
  bool _end = false;
  Object? _error;
  final List<T> _items = [];

  PagedListController({required this.loadPage, this.pageSize = 25});

  PageState<T> get state => PageState(
        items: List.unmodifiable(_items),
        loading: _loading,
        error: _error,
        endReached: _end,
      );

  Future<void> resetAndLoad() async {
    _items.clear();
    _cursor = null;
    _end = false;
    _error = null;
    notifyListeners();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_loading || _end) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final (page, next) = await loadPage(_cursor);
      _items.addAll(page);
      _cursor = next;
      _end = page.length < pageSize;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
