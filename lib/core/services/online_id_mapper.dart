class OnlineIdMapper {
  OnlineIdMapper._internal();

  static final OnlineIdMapper instance = OnlineIdMapper._internal();

  final Map<String, int> _uuidToLocal = {};
  final Map<int, String> _localToUuid = {};
  int _nextLocalId = -1;

  int localIdFor(String uuid) {
    final cached = _uuidToLocal[uuid];
    if (cached != null) return cached;

    final localId = _nextLocalId--;
    _uuidToLocal[uuid] = localId;
    _localToUuid[localId] = uuid;
    return localId;
  }

  String? uuidFor(int? localId) {
    if (localId == null) return null;
    return _localToUuid[localId];
  }

  void remember({required String uuid, required int localId}) {
    _uuidToLocal[uuid] = localId;
    _localToUuid[localId] = uuid;
  }

  void clear() {
    _uuidToLocal.clear();
    _localToUuid.clear();
    _nextLocalId = -1;
  }
}
