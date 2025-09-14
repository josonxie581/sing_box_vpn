import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:win32/win32.dart' as w;

/// Windows 系统代理管理
/// - 使用用户级别 IE/WinINET 代理设置 (HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings)
/// - 通过 InternetSetOption 通知系统变更
class WindowsProxyManager {
  // ======= 全局阻断（用户要求：可完全禁止修改系统代理） =======
  // 1. 运行时可通过 WindowsProxyManager.setBlocked(true/false) 切换
  // 2. 构建时可通过 --dart-define=DISABLE_SYSTEM_PROXY=true 强制阻断
  static bool _blocked = const bool.fromEnvironment(
    'DISABLE_SYSTEM_PROXY',
    defaultValue: false,
  );
  static bool get blocked => _blocked;
  static void setBlocked(bool value) {
    _blocked = value;
  }

  static const String _regSubKey =
      r"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

  // InternetSetOptionW constants（避免依赖 win32 常量缺失）
  static const int _INTERNET_OPTION_REFRESH = 37;
  static const int _INTERNET_OPTION_SETTINGS_CHANGED = 39;

  // 绑定 InternetSetOptionW
  late final ffi.DynamicLibrary _wininet = ffi.DynamicLibrary.open(
    'wininet.dll',
  );

  late final int Function(
    ffi.Pointer<ffi.Void>,
    int,
    ffi.Pointer<ffi.Void>,
    int,
  )
  _internetSetOptionW = _wininet
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
        ),
        int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>, int)
      >('InternetSetOptionW');

  bool get isSupported => Platform.isWindows;

  /// 读取当前代理状态（ProxyEnable）
  bool getProxyEnabled() {
    final hKey = _openKeyForRead();
    if (hKey == 0) return false;
    try {
      final v = _getDword(hKey, 'ProxyEnable');
      return v == 1;
    } finally {
      w.RegCloseKey(hKey);
    }
  }

  /// 获取当前 ProxyServer 字符串，例如 "127.0.0.1:7890"
  String getProxyServer() {
    final hKey = _openKeyForRead();
    if (hKey == 0) return '';
    try {
      return _getString(hKey, 'ProxyServer') ?? '';
    } finally {
      w.RegCloseKey(hKey);
    }
  }

  /// 获取当前自动配置脚本 URL
  String getAutoConfigURL() {
    final hKey = _openKeyForRead();
    if (hKey == 0) return '';
    try {
      return _getString(hKey, 'AutoConfigURL') ?? '';
    } finally {
      w.RegCloseKey(hKey);
    }
  }

  /// 获取系统代理的完整状态（用于调试）
  Map<String, dynamic> getProxyStatus() {
    final hKey = _openKeyForRead();
    if (hKey == 0) return {};
    try {
      return {
        'ProxyEnable': _getDword(hKey, 'ProxyEnable'),
        'ProxyServer': _getString(hKey, 'ProxyServer'),
        'AutoConfigURL': _getString(hKey, 'AutoConfigURL'),
        'AutoDetect': _getDword(hKey, 'AutoDetect'),
        'ProxyOverride': _getString(hKey, 'ProxyOverride'),
      };
    } finally {
      w.RegCloseKey(hKey);
    }
  }

  Map<String, dynamic>? _backup; // 备份注册表值

  /// 启用系统代理
  /// [useSimpleFormat] = true 时按图示使用 "127.0.0.1:port" 简单格式（WinINET 会自动用于 http/https)
  /// 为兼容旧行为，可传 false 使用多协议映射字符串
  Future<bool> enableProxy({
    required int port,
    bool useSimpleFormat = true,
  }) async {
    if (_blocked) {
      // 被阻断时直接返回，但仍保持“未修改”语义
      return false;
    }
    if (!isSupported) return false;
    final hKey = _openOrCreateKey();
    if (hKey == 0) return false;
    try {
      await _backupIfNeeded(hKey);

      final server = '127.0.0.1:$port';
      final proxyValue = useSimpleFormat
          ? server // 简单模式
          : 'http=$server;https=$server;socks=$server'; // 旧兼容模式

      // 常见直连网段/域名（顺序不会影响功能）
      const overrideList = [
        '<-loopback>', // WinINET 特殊关键字：loopback + localhost
        'localhost',
        '*.local',
        '127.*',
        '10.*',
        '172.16.*',
        '172.17.*',
        '172.18.*',
        '172.19.*',
        '172.2*', // 覆盖到 172.20-29 (简单写法，严格可枚举)
        '172.30.*',
        '172.31.*',
        '192.168.*',
      ];

      _setDword(hKey, 'ProxyEnable', 1);
      _setString(hKey, 'ProxyServer', proxyValue);
      _setString(hKey, 'ProxyOverride', overrideList.join(';'));
      // 关闭自动检测与 PAC
      _setDword(hKey, 'AutoDetect', 0);
      _deleteValue(hKey, 'AutoConfigURL');

      _notifySettingsChanged();
      return true;
    } finally {
      w.RegCloseKey(hKey);
    }
  }

  /// 启用 PAC 文件代理
  Future<bool> enableProxyWithPac(String pacUrl) async {
    if (_blocked) {
      return false;
    }
    if (!isSupported) return false;
    final hKey = _openOrCreateKey();
    if (hKey == 0) return false;
    try {
      await _backupIfNeeded(hKey);

      print('设置PAC文件代理: $pacUrl');

      // 禁用手动代理
      _setDword(hKey, 'ProxyEnable', 0);
      _deleteValue(hKey, 'ProxyServer');

      // 启用自动配置脚本
      _setString(hKey, 'AutoConfigURL', pacUrl);
      _setDword(hKey, 'AutoDetect', 0); // 禁用自动检测

      // 验证设置是否成功
      final verifyUrl = _getString(hKey, 'AutoConfigURL');
      final verifyEnable = _getDword(hKey, 'ProxyEnable');
      print('验证PAC设置 - URL: $verifyUrl, ProxyEnable: $verifyEnable');

      _notifySettingsChanged();

      // 额外的系统通知
      _internetSetOptionW(
        ffi.nullptr,
        _INTERNET_OPTION_REFRESH,
        ffi.nullptr,
        0,
      );

      return verifyUrl == pacUrl && verifyEnable == 0;
    } finally {
      w.RegCloseKey(hKey);
    }
  }

  /// 禁用系统代理（恢复备份或直接关闭）
  Future<bool> disableProxy() async {
    if (_blocked) {
      return false;
    }
    if (!isSupported) return false;
    final hKey = _openOrCreateKey();
    if (hKey == 0) return false;
    try {
      if (_backup != null) {
        _restoreFromBackup(hKey);
      } else {
        _setDword(hKey, 'ProxyEnable', 0);
        _deleteValue(hKey, 'AutoConfigURL');
      }
      _notifySettingsChanged();
      return true;
    } finally {
      w.RegCloseKey(hKey);
    }
  }

  // --- Registry helpers ---
  int _openKeyForRead() {
    final subKey = _toUtf16(_regSubKey);
    final phKey = pkgffi.calloc<ffi.IntPtr>();
    final result = w.RegOpenKeyEx(
      w.HKEY_CURRENT_USER,
      subKey,
      0,
      w.KEY_QUERY_VALUE,
      phKey,
    );
    final hKey = result == w.ERROR_SUCCESS ? phKey.value : 0;
    pkgffi.calloc.free(subKey);
    pkgffi.calloc.free(phKey);
    return hKey;
  }

  int _openOrCreateKey() {
    final subKey = _toUtf16(_regSubKey);
    final phKey = pkgffi.calloc<ffi.IntPtr>();
    final lpdwDisposition = pkgffi.calloc<ffi.Uint32>();
    final result = w.RegCreateKeyEx(
      w.HKEY_CURRENT_USER,
      subKey,
      0,
      ffi.nullptr,
      w.REG_OPTION_NON_VOLATILE,
      w.KEY_SET_VALUE | w.KEY_QUERY_VALUE,
      ffi.nullptr,
      phKey,
      lpdwDisposition,
    );
    final hKey = result == w.ERROR_SUCCESS ? phKey.value : 0;
    pkgffi.calloc.free(subKey);
    pkgffi.calloc.free(phKey);
    pkgffi.calloc.free(lpdwDisposition);
    return hKey;
  }

  Future<void> _backupIfNeeded(int hKey) async {
    if (_backup != null) return;
    _backup = {
      'ProxyEnable': _getDword(hKey, 'ProxyEnable'),
      'ProxyServer': _getString(hKey, 'ProxyServer'),
      'ProxyOverride': _getString(hKey, 'ProxyOverride'),
      'AutoConfigURL': _getString(hKey, 'AutoConfigURL'),
      'AutoDetect': _getDword(hKey, 'AutoDetect'),
    };
  }

  void _restoreFromBackup(int hKey) {
    if (_backup == null) return;
    final b = _backup!;
    _setMaybeDword(hKey, 'ProxyEnable', b['ProxyEnable']);
    _setMaybeString(hKey, 'ProxyServer', b['ProxyServer']);
    _setMaybeString(hKey, 'ProxyOverride', b['ProxyOverride']);
    _setMaybeString(hKey, 'AutoConfigURL', b['AutoConfigURL']);
    _setMaybeDword(hKey, 'AutoDetect', b['AutoDetect']);
  }

  void _setMaybeDword(int hKey, String name, Object? value) {
    if (value is int) {
      _setDword(hKey, name, value);
    } else {
      _deleteValue(hKey, name);
    }
  }

  void _setMaybeString(int hKey, String name, Object? value) {
    if (value is String && value.isNotEmpty) {
      _setString(hKey, name, value);
    } else {
      _deleteValue(hKey, name);
    }
  }

  int? _getDword(int hKey, String name) {
    final lpType = pkgffi.calloc<ffi.Uint32>();
    final lpcbData = pkgffi.calloc<ffi.Uint32>();
    // First call to get size
    final namePtr = _toUtf16(name);
    var result = w.RegQueryValueEx(
      hKey,
      namePtr,
      ffi.nullptr,
      lpType,
      ffi.nullptr,
      lpcbData,
    );
    if (result != w.ERROR_SUCCESS ||
        lpType.value != w.REG_DWORD ||
        lpcbData.value != 4) {
      pkgffi.calloc.free(lpType);
      pkgffi.calloc.free(lpcbData);
      pkgffi.calloc.free(namePtr);
      return null;
    }
    final data = pkgffi.calloc<ffi.Uint32>();
    result = w.RegQueryValueEx(
      hKey,
      namePtr,
      ffi.nullptr,
      lpType,
      data.cast<ffi.Uint8>(),
      lpcbData,
    );
    final value = result == w.ERROR_SUCCESS ? data.value : null;
    pkgffi.calloc.free(lpType);
    pkgffi.calloc.free(lpcbData);
    pkgffi.calloc.free(namePtr);
    pkgffi.calloc.free(data);
    return value;
  }

  String? _getString(int hKey, String name) {
    final lpType = pkgffi.calloc<ffi.Uint32>();
    final lpcbData = pkgffi.calloc<ffi.Uint32>();
    final namePtr = _toUtf16(name);
    // First call to get size
    var result = w.RegQueryValueEx(
      hKey,
      namePtr,
      ffi.nullptr,
      lpType,
      ffi.nullptr,
      lpcbData,
    );
    if (result != w.ERROR_SUCCESS ||
        (lpType.value != w.REG_SZ && lpType.value != w.REG_EXPAND_SZ)) {
      pkgffi.calloc.free(lpType);
      pkgffi.calloc.free(lpcbData);
      pkgffi.calloc.free(namePtr);
      return null;
    }
    final buffer = pkgffi.calloc<ffi.Uint8>(lpcbData.value);
    result = w.RegQueryValueEx(
      hKey,
      namePtr,
      ffi.nullptr,
      lpType,
      buffer,
      lpcbData,
    );
    String? value;
    if (result == w.ERROR_SUCCESS) {
      final uint16View = buffer.cast<ffi.Uint16>();
      final codeUnits = uint16View.asTypedList(lpcbData.value ~/ 2);
      // Remove trailing nulls
      int len = codeUnits.length;
      while (len > 0 && codeUnits[len - 1] == 0) {
        len--;
      }
      value = String.fromCharCodes(codeUnits.sublist(0, len));
    }
    pkgffi.calloc.free(lpType);
    pkgffi.calloc.free(lpcbData);
    pkgffi.calloc.free(namePtr);
    pkgffi.calloc.free(buffer);
    return value;
  }

  void _setDword(int hKey, String name, int value) {
    final namePtr = _toUtf16(name);
    final data = pkgffi.calloc<ffi.Uint32>();
    data.value = value;
    w.RegSetValueEx(hKey, namePtr, 0, w.REG_DWORD, data.cast<ffi.Uint8>(), 4);
    pkgffi.calloc.free(namePtr);
    pkgffi.calloc.free(data);
  }

  void _setString(int hKey, String name, String value) {
    final namePtr = _toUtf16(name);
    final utf16 = _toUtf16(value);
    // Size in bytes including null terminator
    final byteLen = (value.length + 1) * 2;
    w.RegSetValueEx(
      hKey,
      namePtr,
      0,
      w.REG_SZ,
      utf16.cast<ffi.Uint8>(),
      byteLen,
    );
    pkgffi.calloc.free(namePtr);
    pkgffi.calloc.free(utf16);
  }

  void _deleteValue(int hKey, String name) {
    final namePtr = _toUtf16(name);
    w.RegDeleteValue(hKey, namePtr);
    pkgffi.calloc.free(namePtr);
  }

  void _notifySettingsChanged() {
    _internetSetOptionW(
      ffi.nullptr,
      _INTERNET_OPTION_SETTINGS_CHANGED,
      ffi.nullptr,
      0,
    );
    _internetSetOptionW(ffi.nullptr, _INTERNET_OPTION_REFRESH, ffi.nullptr, 0);
  }

  ffi.Pointer<pkgffi.Utf16> _toUtf16(String s) =>
      s.toNativeUtf16(allocator: pkgffi.calloc);
}
