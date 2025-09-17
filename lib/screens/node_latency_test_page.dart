import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/node_delay_tester.dart';
import '../services/config_manager.dart';
import '../models/vpn_config.dart';

/// 节点延时测试页面
class NodeLatencyTestPage extends StatefulWidget {
  const NodeLatencyTestPage({Key? key}) : super(key: key);

  @override
  State<NodeLatencyTestPage> createState() => _NodeLatencyTestPageState();
}

class _NodeLatencyTestPageState extends State<NodeLatencyTestPage> {
  final ConfigManager _configManager = ConfigManager();
  NodeDelayTester? _delayTester;

  List<VPNConfig> _allNodes = [];
  List<VPNConfig> _selectedNodes = [];
  List<NodeDelayResult> _testResults = [];

  bool _isLoading = false;
  bool _isTesting = false;
  int _completedTests = 0;
  int _totalTests = 0;
  String _statusMessage = '准备就绪';

  // 测试选项
  int _timeout = 10000;
  int _maxConcurrency = 3;
  bool _enableSpeedTest = false;
  bool _enableIpInfo = true;
  String _testUrl = 'https://cloudflare.com/cdn-cgi/trace';

  // 排序选项
  String _sortBy = 'delay'; // delay, name, type, server
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  @override
  void dispose() {
    _delayTester?.cancel();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _configManager.loadConfigs();
      final configs = _configManager.configs;
      setState(() {
        _allNodes = configs;
        _selectedNodes = List<VPNConfig>.from(configs);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '加载配置失败: $e';
      });
    }
  }

  /// 开始测试
  Future<void> _startTest() async {
    if (_selectedNodes.isEmpty) {
      _showSnackBar('请至少选择一个节点进行测试');
      return;
    }

    setState(() {
      _isTesting = true;
      _completedTests = 0;
      _totalTests = _selectedNodes.length;
      _testResults.clear();
      _statusMessage = '正在测试...';
    });

    _delayTester = NodeDelayTester(
      timeout: _timeout,
      maxConcurrency: _maxConcurrency,
      enableIpInfo: _enableIpInfo,
      latencyMode: LatencyTestMode.systemOnly,
      onProgress: (completed, total) {
        setState(() {
          _completedTests = completed;
          _totalTests = total;
          _statusMessage = '测试进度: $completed / $total';
        });
      },
    );

    try {
      // 始终使用quickTestMultiple避免VPN代理干扰
      // quickTestMultiple使用直连TCP测试，能够准确测量到VPN服务器的延时
      final results = await _delayTester!.quickTestMultiple(_selectedNodes);

      setState(() {
        _testResults = results;
        _sortResults();
        _isTesting = false;
        _statusMessage = '测试完成';
      });

      _showTestSummary(results);
    } catch (e) {
      setState(() {
        _isTesting = false;
        _statusMessage = '测试失败: $e';
      });
      _showSnackBar('测试失败: $e');
    }
  }

  /// 停止测试
  void _stopTest() {
    _delayTester?.cancel();
    setState(() {
      _isTesting = false;
      _statusMessage = '测试已取消';
    });
  }

  /// 测试单个节点
  Future<void> _testSingleNode(VPNConfig node) async {
    setState(() {
      _isTesting = true;
      _statusMessage = '正在测试 ${node.name}...';
    });

    _delayTester = NodeDelayTester(
      timeout: _timeout,
      enableIpInfo: _enableIpInfo,
      latencyMode: LatencyTestMode.systemOnly,
    );

    try {
      // 始终使用quickTest避免VPN代理干扰，quickTest使用直连TCP测试
      // 能够准确测量到VPN服务器的延时，而不是经过VPN后的网络延时
      final result = await _delayTester!.quickTest(node);

      // 更新或添加结果
      final existingIndex = _testResults.indexWhere((r) => r.nodeId == node.id);
      setState(() {
        if (existingIndex >= 0) {
          _testResults[existingIndex] = result;
        } else {
          _testResults.add(result);
        }
        _sortResults();
        _isTesting = false;
        _statusMessage = '测试完成';
      });

      _showSingleTestResult(result);
    } catch (e) {
      setState(() {
        _isTesting = false;
        _statusMessage = '测试失败: $e';
      });
      _showSnackBar('测试失败: $e');
    }
  }

  /// 排序结果
  void _sortResults() {
    _testResults.sort((a, b) {
      int compare = 0;

      switch (_sortBy) {
        case 'delay':
          // 成功的在前，按延时排序
          if (a.isSuccess && !b.isSuccess) return -1;
          if (!a.isSuccess && b.isSuccess) return 1;
          if (a.isSuccess && b.isSuccess) {
            compare = a.delay.compareTo(b.delay);
          }
          break;
        case 'name':
          compare = a.nodeName.compareTo(b.nodeName);
          break;
        case 'type':
          compare = a.nodeType.compareTo(b.nodeType);
          break;
        case 'server':
          compare = a.nodeServer.compareTo(b.nodeServer);
          break;
      }

      return _sortAscending ? compare : -compare;
    });
  }

  /// 显示测试摘要
  void _showTestSummary(List<NodeDelayResult> results) {
    final successCount = results.where((r) => r.isSuccess).length;
    final failedCount = results.length - successCount;

    if (successCount > 0) {
      final avgLatency =
          results
              .where((r) => r.isSuccess && r.delay >= 0)
              .map((r) => r.delay)
              .reduce((a, b) => a + b) ~/
          successCount;

      final bestNode = results.firstWhere((r) => r.isSuccess);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('测试完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('成功: $successCount 个节点'),
              Text('失败: $failedCount 个节点'),
              SizedBox(height: 8),
              Text('平均延时: $avgLatency ms'),
              Text('最佳节点: ${bestNode.nodeName}'),
              Text('最佳延时: ${bestNode.delay} ms'),
              if (bestNode.ipLocation != null)
                Text('位置: ${bestNode.ipLocation}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('确定'),
            ),
          ],
        ),
      );
    } else {
      _showSnackBar('所有节点测试失败');
    }
  }

  /// 显示单个测试结果
  void _showSingleTestResult(NodeDelayResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('测试结果 - ${result.nodeName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('服务器: ${result.nodeServer}:${result.nodePort}'),
            Text('协议类型: ${result.nodeType}'),
            Divider(),
            if (result.isSuccess) ...[
              Text('延时: ${result.delay} ms'),
              if (result.httpStatusCode != null)
                Text('HTTP 状态码: ${result.httpStatusCode}'),
              if (result.realIpAddress != null)
                Text('IP 地址: ${result.realIpAddress}'),
              if (result.ipLocation != null) Text('位置: ${result.ipLocation}'),
              // 注意：NodeDelayResult 不包含速度测试信息
            ] else ...[
              Text('状态: 失败', style: TextStyle(color: Colors.red)),
              if (result.errorMessage != null)
                Text('错误: ${result.errorMessage}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 复制节点信息
  void _copyNodeInfo(NodeDelayResult result) {
    final info = StringBuffer();
    info.writeln('节点: ${result.nodeName}');
    info.writeln('服务器: ${result.nodeServer}:${result.nodePort}');
    info.writeln('协议: ${result.nodeType}');
    if (result.isSuccess) {
      info.writeln('延时: ${result.delay} ms');
      if (result.realIpAddress != null) {
        info.writeln('IP: ${result.realIpAddress}');
      }
      if (result.ipLocation != null) {
        info.writeln('位置: ${result.ipLocation}');
      }
    } else {
      info.writeln('状态: 失败');
      if (result.errorMessage != null) {
        info.writeln('错误: ${result.errorMessage}');
      }
    }

    Clipboard.setData(ClipboardData(text: info.toString()));
    _showSnackBar('已复制到剪贴板');
  }

  /// 导出测试结果
  void _exportResults() {
    if (_testResults.isEmpty) {
      _showSnackBar('没有测试结果可导出');
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('节点延时测试结果');
    buffer.writeln('测试时间: ${DateTime.now()}');
    buffer.writeln('=' * 50);

    for (final result in _testResults) {
      buffer.writeln('节点: ${result.nodeName}');
      buffer.writeln('服务器: ${result.nodeServer}:${result.nodePort}');
      buffer.writeln('协议: ${result.nodeType}');
      if (result.isSuccess) {
        buffer.writeln('延时: ${result.delay} ms');
        if (result.ipLocation != null) {
          buffer.writeln('位置: ${result.ipLocation}');
        }
      } else {
        buffer.writeln('状态: 失败');
      }
      buffer.writeln('-' * 30);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _showSnackBar('测试结果已复制到剪贴板');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('节点延时测试'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: '测试设置',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadConfigs,
            tooltip: '刷新节点',
          ),
          if (_testResults.isNotEmpty)
            IconButton(
              icon: Icon(Icons.download),
              onPressed: _exportResults,
              tooltip: '导出结果',
            ),
        ],
      ),
      body: Column(
        children: [
          // 状态栏
          _buildStatusBar(),

          // 工具栏
          _buildToolBar(),

          // 主内容区
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _buildMainContent(),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: EdgeInsets.all(12),
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Row(
        children: [
          Text(_statusMessage),
          Spacer(),
          if (_isTesting) ...[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('$_completedTests / $_totalTests'),
          ],
          if (!_isTesting && _testResults.isNotEmpty)
            Text('共 ${_testResults.length} 个结果'),
        ],
      ),
    );
  }

  Widget _buildToolBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 排序选项
          Text('排序:'),
          SizedBox(width: 8),
          DropdownButton<String>(
            value: _sortBy,
            items: [
              DropdownMenuItem(value: 'delay', child: Text('延时')),
              DropdownMenuItem(value: 'name', child: Text('名称')),
              DropdownMenuItem(value: 'type', child: Text('类型')),
              DropdownMenuItem(value: 'server', child: Text('服务器')),
            ],
            onChanged: (value) {
              setState(() {
                _sortBy = value!;
                _sortResults();
              });
            },
          ),
          IconButton(
            icon: Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            ),
            onPressed: () {
              setState(() {
                _sortAscending = !_sortAscending;
                _sortResults();
              });
            },
          ),
          Spacer(),

          // 节点选择
          TextButton.icon(
            icon: Icon(Icons.select_all),
            label: Text('全选'),
            onPressed: () {
              setState(() {
                _selectedNodes = List<VPNConfig>.from(_allNodes);
              });
            },
          ),
          TextButton.icon(
            icon: Icon(Icons.deselect),
            label: Text('清空'),
            onPressed: () {
              setState(() {
                _selectedNodes.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_testResults.isNotEmpty) {
      // 显示测试结果
      return ListView.builder(
        itemCount: _testResults.length,
        itemBuilder: (context, index) {
          final result = _testResults[index];
          return _buildResultTile(result);
        },
      );
    } else {
      // 显示节点列表
      return ListView.builder(
        itemCount: _allNodes.length,
        itemBuilder: (context, index) {
          final node = _allNodes[index];
          final isSelected = _selectedNodes.contains(node);

          return CheckboxListTile(
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value!) {
                  _selectedNodes.add(node);
                } else {
                  _selectedNodes.remove(node);
                }
              });
            },
            title: Text(node.name),
            subtitle: Text('${node.type} - ${node.server}:${node.port}'),
            secondary: IconButton(
              icon: Icon(Icons.speed),
              onPressed: _isTesting ? null : () => _testSingleNode(node),
              tooltip: '测试此节点',
            ),
          );
        },
      );
    }
  }

  Widget _buildResultTile(NodeDelayResult result) {
    final node = _allNodes.firstWhere(
      (n) => n.id == result.nodeId,
      orElse: () => VPNConfig(
        name: result.nodeName,
        type: result.nodeType,
        server: result.nodeServer,
        port: result.nodePort,
        settings: {},
      ),
    );

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: result.isSuccess ? Colors.green : Colors.red,
          child: result.isSuccess
              ? Text(
                  '${result.delay}',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                )
              : Icon(Icons.error, color: Colors.white),
        ),
        title: Text(result.nodeName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${result.nodeType} - ${result.nodeServer}:${result.nodePort}',
            ),
            if (result.isSuccess) ...[
              if (result.ipLocation != null)
                Text(
                  '位置: ${result.ipLocation}',
                  style: TextStyle(fontSize: 12),
                ),
              // 注意：NodeDelayResult 不包含速度测试信息
            ] else if (result.errorMessage != null)
              Text(
                result.errorMessage!,
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _isTesting ? null : () => _testSingleNode(node),
              tooltip: '重新测试',
            ),
            IconButton(
              icon: Icon(Icons.copy),
              onPressed: () => _copyNodeInfo(result),
              tooltip: '复制信息',
            ),
          ],
        ),
        onTap: () => _showSingleTestResult(result),
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    if (_testResults.isNotEmpty) {
      return FloatingActionButton.extended(
        onPressed: () {
          setState(() {
            _testResults.clear();
          });
        },
        icon: Icon(Icons.clear_all),
        label: Text('清空结果'),
      );
    } else if (_isTesting) {
      return FloatingActionButton.extended(
        onPressed: _stopTest,
        icon: Icon(Icons.stop),
        label: Text('停止测试'),
        backgroundColor: Colors.red,
      );
    } else {
      return FloatingActionButton.extended(
        onPressed: _selectedNodes.isEmpty ? null : _startTest,
        icon: Icon(Icons.play_arrow),
        label: Text('开始测试 (${_selectedNodes.length})'),
      );
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('测试设置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: '超时时间 (毫秒)',
                  hintText: '默认 10000',
                ),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: _timeout.toString()),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    _timeout = parsed;
                  }
                },
              ),
              SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  labelText: '最大并发数',
                  hintText: '默认 3',
                ),
                keyboardType: TextInputType.number,
                controller: TextEditingController(
                  text: _maxConcurrency.toString(),
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    _maxConcurrency = parsed;
                  }
                },
              ),
              SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  labelText: '测试 URL',
                  hintText: _testUrl,
                ),
                controller: TextEditingController(text: _testUrl),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    _testUrl = value;
                  }
                },
              ),
              SizedBox(height: 16),
              SwitchListTile(
                title: Text('启用速度测试'),
                subtitle: Text('测试下载和上传速度（耗时较长）'),
                value: _enableSpeedTest,
                onChanged: (value) {
                  setState(() {
                    _enableSpeedTest = value;
                  });
                },
              ),
              SwitchListTile(
                title: Text('获取 IP 信息'),
                subtitle: Text('获取真实 IP 和位置信息'),
                value: _enableIpInfo,
                onChanged: (value) {
                  setState(() {
                    _enableIpInfo = value;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }
}
