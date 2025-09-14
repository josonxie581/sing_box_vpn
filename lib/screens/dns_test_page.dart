import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/navigation.dart';
import '../services/dns_manager.dart';
import '../theme/app_theme.dart';

/// DNS域名测试页面
class DnsTestPage extends StatefulWidget {
  const DnsTestPage({super.key});

  @override
  State<DnsTestPage> createState() => _DnsTestPageState();
}

class _DnsTestPageState extends State<DnsTestPage> {
  final DnsManager _dnsManager = DnsManager();
  final _domainController = TextEditingController();
  final List<DnsTestResult> _testResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _domainController.text = _dnsManager.testDomain;
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => safePop(context),
        ),
        title: const Text(
          'DNS域名测试',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all, color: AppTheme.textSecondary),
            onPressed: _testResults.isNotEmpty ? _clearResults : null,
            tooltip: '清空结果',
          ),
        ],
      ),
      body: Column(
        children: [
          // 测试输入区域
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '测试域名',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                // 域名输入框
                TextField(
                  controller: _domainController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: '输入要测试的域名 (如: google.com)',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.borderColor.withAlpha(100)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.borderColor.withAlpha(100)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.primaryNeon),
                    ),
                    suffixIcon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryNeon),
                              ),
                            ),
                          )
                        : null,
                  ),
                  onSubmitted: (value) => _testDomain(),
                  enabled: !_isLoading,
                ),

                const SizedBox(height: 16),

                // 快速域名选择
                const Text(
                  '快速选择',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildQuickDomainChip('google.com'),
                    _buildQuickDomainChip('github.com'),
                    _buildQuickDomainChip('baidu.com'),
                    _buildQuickDomainChip('qq.com'),
                    _buildQuickDomainChip('cloudflare.com'),
                    _buildQuickDomainChip('openai.com'),
                  ],
                ),

                const SizedBox(height: 16),

                // 测试按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testDomain,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryNeon,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      _isLoading ? '测试中...' : '开始测试',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 测试结果区域
          if (_testResults.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    '测试结果',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '共 ${_testResults.length} 条记录',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 结果列表
          Expanded(
            child: _testResults.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _testResults.length,
                    itemBuilder: (context, index) {
                      final result = _testResults[_testResults.length - 1 - index]; // 倒序显示
                      return _buildResultCard(result);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建快速域名选择按钮
  Widget _buildQuickDomainChip(String domain) {
    return ActionChip(
      label: Text(
        domain,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 12,
        ),
      ),
      backgroundColor: AppTheme.bgDark,
      side: BorderSide(color: AppTheme.borderColor.withAlpha(100)),
      onPressed: _isLoading ? null : () {
        _domainController.text = domain;
      },
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryNeon.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.network_check,
              size: 40,
              color: AppTheme.primaryNeon,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '开始DNS解析测试',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '输入域名后点击测试按钮\n检查DNS解析是否正常工作',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建测试结果卡片
  Widget _buildResultCard(DnsTestResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: result.success
              ? AppTheme.primaryNeon.withAlpha(50)
              : AppTheme.errorRed.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              // 状态指示器
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: result.success ? AppTheme.primaryNeon : AppTheme.errorRed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),

              // 域名
              Expanded(
                child: Text(
                  result.domain,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // 测试时间
              Text(
                _formatTime(result.testTime),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),

              // 复制按钮
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: AppTheme.textSecondary),
                onPressed: () => _copyResult(result),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (result.success) ...[
            // 成功结果
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: AppTheme.primaryNeon,
                ),
                const SizedBox(width: 8),
                Text(
                  '解析成功',
                  style: const TextStyle(
                    color: AppTheme.primaryNeon,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (result.duration != null) ...[
                  const SizedBox(width: 16),
                  Text(
                    '用时: ${result.duration!.inMilliseconds}ms',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),

            if (result.resolvedAddresses.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'IP地址:',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              ...result.resolvedAddresses.map((ip) => Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                child: Row(
                  children: [
                    const Text(
                      '•',
                      style: TextStyle(color: AppTheme.primaryNeon),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ip,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 14, color: AppTheme.textSecondary),
                      onPressed: () => _copyToClipboard(ip),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              )),
            ],
          ] else ...[
            // 失败结果
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error,
                  size: 16,
                  color: AppTheme.errorRed,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '解析失败',
                        style: TextStyle(
                          color: AppTheme.errorRed,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (result.error != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.error!,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 测试域名解析
  Future<void> _testDomain() async {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) {
      _showErrorSnackBar('请输入要测试的域名');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _dnsManager.testDomainResolution(domain);

      setState(() {
        _testResults.add(result);
        _isLoading = false;
      });

      if (result.success) {
        _showSuccessSnackBar('域名解析成功');
      } else {
        _showErrorSnackBar('域名解析失败: ${result.error}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('测试过程中出现错误: $e');
    }
  }

  /// 清空测试结果
  void _clearResults() {
    setState(() {
      _testResults.clear();
    });
    _showSuccessSnackBar('测试结果已清空');
  }

  /// 复制测试结果
  void _copyResult(DnsTestResult result) {
    _copyToClipboard(result.toString());
  }

  /// 复制到剪贴板
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccessSnackBar('已复制到剪贴板');
  }

  /// 格式化时间
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }

  /// 显示错误提示
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 显示成功提示
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.primaryNeon,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}