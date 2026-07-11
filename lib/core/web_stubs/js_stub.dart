class _JsContext {
  dynamic callMethod(String method, [List? args]) => null;
  dynamic operator [](String key) => _JsContext();
  void operator []=(String key, dynamic value) {}
  void deleteProperty(String key) {}
}

final _JsContext context = _JsContext();

dynamic allowInterop(Function fn) => fn;

class JsArray {
  final List _items = const [];
  int get length => _items.length;
  dynamic operator [](int index) => _items[index];
}

class JsObject {
  dynamic operator [](String key) => null;
}