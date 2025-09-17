import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/node_delay_tester.dart';
import '../models/vpn_config.dart';

/// 节点延时测试小部件
class NodeDelayTestWidget extends StatefulWidget {
  final VPNConfig node;
  final Function(NodeDelayResult)? onTestComplete;
  final bool showDetails;

  const NodeDelayTestWidget({
    Key? key,
    required this.node,
    this.onTestComplete,
    this.showDetails = true,
  }) : super(key: key);

  @override
  State<NodeDelayTestWidget> createState() => _NodeDelayTestWidgetState();
}

class _NodeDelayTestWidgetState extends State<NodeDelayTestWidget> {
  NodeDelayTester? _tester;
  NodeDelayResult? _result;
  bool _isTesting = false;

  @override
  void dispose() {
    _tester?.cancel();
    super.dispose();
  }

  Future<void> _testDelay() async {
    setState(() {
      _isTesting = true;
      _result = null;
    });

    _tester = NodeDelayTester(timeout: 8000, enableIpInfo: false);

    try {
      // 使用真实延时测试（带绕行），避免被当前VPN路由影响
      final result = await _tester!.realTest(widget.node);
      setState(() {
        _result = result;
        _isTesting = false;
      });

      widget.onTestComplete?.call(result);
    } catch (e) {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _quickTest() async {
    setState(() {
      _isTesting = true;
      _result = null;
    });

    _tester = NodeDelayTester(timeout: 3000);

    try {
      final result = await _tester!.quickTest(widget.node);
      setState(() {
        _result = result;
        _isTesting = false;
      });

      widget.onTestComplete?.call(result);
    } catch (e) {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Color _getDelayColor(int delay) {
    if (delay < 0) return Colors.red;
    if (delay < 100) return Colors.green;
    if (delay < 300) return Colors.orange;
    if (delay < 500) return Colors.deepOrange;
    return Colors.red;
  }

  String _getDelayText(int delay) {
    if (delay < 0) return '超时';
    return '${delay}ms';
  }

  @override
  Widget build(BuildContext context) {
    if (_isTesting) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).primaryColor,
          ),
        ),
      );
    }

    if (_result != null && !widget.showDetails) {
      // 简单显示模式
      return GestureDetector(
        onTap: _testDelay,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getDelayColor(_result!.delay).withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _getDelayColor(_result!.delay), width: 1),
          ),
          child: Text(
            _getDelayText(_result!.delay),
            style: TextStyle(
              color: _getDelayColor(_result!.delay),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    if (_result != null && widget.showDetails) {
      // 详细显示模式
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _result!.isSuccess ? Icons.check_circle : Icons.error,
                    color: _result!.isSuccess ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    _getDelayText(_result!.delay),
                    style: TextStyle(
                      color: _getDelayColor(_result!.delay),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.refresh, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: _testDelay,
                    tooltip: '重新测试',
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: () {
                      final text =
                          '${widget.node.name}: ${_getDelayText(_result!.delay)}';
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('已复制到剪贴板')));
                    },
                    tooltip: '复制结果',
                  ),
                ],
              ),
              if (_result!.realIpAddress != null) ...[
                SizedBox(height: 4),
                Text(
                  'IP: ${_result!.realIpAddress}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              if (_result!.ipLocation != null) ...[
                Text(
                  '位置: ${_result!.ipLocation}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // 初始状态 - 显示测试按钮
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _testDelay,
          icon: Icon(Icons.speed, size: 16),
          label: Text('测试延时', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size(0, 0),
          ),
        ),
        SizedBox(width: 4),
        TextButton(
          onPressed: _quickTest,
          child: Text('快速测试', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size(0, 0),
          ),
        ),
      ],
    );
  }
}

/// 批量节点延时测试对话框
class BatchDelayTestDialog extends StatefulWidget {
  final List<VPNConfig> nodes;

  const BatchDelayTestDialog({Key? key, required this.nodes}) : super(key: key);

  @override
  State<BatchDelayTestDialog> createState() => _BatchDelayTestDialogState();
}

class _BatchDelayTestDialogState extends State<BatchDelayTestDialog> {
  NodeDelayTester? _tester;
  List<NodeDelayResult> _results = [];
  bool _isTesting = false;
  int _completedCount = 0;
  int _totalCount = 0;
  String _currentNode = '';
  bool _useQuickTest = false;

  @override
  void dispose() {
    _tester?.cancel();
    super.dispose();
  }

  Future<void> _startTest() async {
    setState(() {
      _isTesting = true;
      _results.clear();
      _completedCount = 0;
      _totalCount = widget.nodes.length;
    });

    _tester = NodeDelayTester(
      timeout: _useQuickTest ? 3000 : 5000,
      maxConcurrency: 3,
      enableIpInfo: !_useQuickTest,
      onProgress: (completed, total) {
        setState(() {
          _completedCount = completed;
          _totalCount = total;
        });
      },
    );

    try {
      List<NodeDelayResult> results;
      if (_useQuickTest) {
        results = await _tester!.quickTestMultiple(widget.nodes);
      } else {
        results = await _tester!.testMultipleNodes(widget.nodes);
      }

      setState(() {
        _results = results;
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('测试失败: $e')));
    }
  }

  void _stopTest() {
    _tester?.cancel();
    setState(() {
      _isTesting = false;
    });
  }

  void _exportResults() {
    final buffer = StringBuffer();
    buffer.writeln('节点延时测试结果');
    buffer.writeln('=' * 30);

    for (final result in _results) {
      buffer.writeln(
        '${result.nodeName}: ${result.delay >= 0 ? "${result.delay}ms" : "失败"}',
      );
      if (result.ipLocation != null) {
        buffer.writeln('  位置: ${result.ipLocation}');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('结果已复制到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text('批量延时测试'),
          Spacer(),
          if (_isTesting)
            Text(
              '$_completedCount / $_totalCount',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
        ],
      ),
      content: Container(
        width: 400,
        height: 400,
        child: Column(
          children: [
            // 选项栏
            Row(
              children: [
                Checkbox(
                  value: _useQuickTest,
                  onChanged: _isTesting
                      ? null
                      : (value) {
                          setState(() {
                            _useQuickTest = value!;
                          });
                        },
                ),
                Text('快速测试（仅测试TCP连接）'),
                Spacer(),
                if (_results.isNotEmpty)
                  TextButton.icon(
                    onPressed: _exportResults,
                    icon: Icon(Icons.download, size: 16),
                    label: Text('导出'),
                  ),
              ],
            ),
            Divider(),

            // 进度条
            if (_isTesting)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _totalCount > 0 ? _completedCount / _totalCount : 0,
                  ),
                  SizedBox(height: 8),
                  Text(_currentNode),
                  SizedBox(height: 8),
                ],
              ),

            // 结果列表
            Expanded(
              child: _results.isEmpty && !_isTesting
                  ? Center(
                      child: Text(
                        '点击"开始测试"按钮开始',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            result.isSuccess ? Icons.check_circle : Icons.error,
                            color: result.isSuccess ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          title: Text(result.nodeName),
                          subtitle: result.ipLocation != null
                              ? Text(
                                  result.ipLocation!,
                                  style: TextStyle(fontSize: 12),
                                )
                              : null,
                          trailing: Text(
                            result.delay >= 0 ? '${result.delay}ms' : '失败',
                            style: TextStyle(
                              color: result.delay >= 0
                                  ? (result.delay < 300
                                        ? Colors.green
                                        : Colors.orange)
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_isTesting)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭'),
          ),
        if (_isTesting)
          TextButton(
            onPressed: _stopTest,
            child: Text('停止', style: TextStyle(color: Colors.red)),
          )
        else
          ElevatedButton.icon(
            onPressed: _startTest,
            icon: Icon(Icons.play_arrow),
            label: Text('开始测试'),
          ),
      ],
    );
  }
}
