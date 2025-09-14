import 'package:flutter/material.dart';
import '../utils/navigation.dart';
import '../services/dns_manager.dart';
import '../theme/app_theme.dart';

/// 静态IP映射管理页面
class StaticIpMappingPage extends StatefulWidget {
  const StaticIpMappingPage({super.key});

  @override
  State<StaticIpMappingPage> createState() => _StaticIpMappingPageState();
}

class _StaticIpMappingPageState extends State<StaticIpMappingPage> {
  final DnsManager _dnsManager = DnsManager();
  final _searchController = TextEditingController();
  List<StaticIpMapping> _filteredMappings = [];

  @override
  void initState() {
    super.initState();
    _refreshMappings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshMappings() {
    final mappings = _dnsManager.staticIpMappings;
    final searchText = _searchController.text.toLowerCase();

    if (searchText.isEmpty) {
      _filteredMappings = List.from(mappings);
    } else {
      _filteredMappings = mappings.where((mapping) =>
        mapping.domain.toLowerCase().contains(searchText) ||
        mapping.ipAddress.contains(searchText) ||
        (mapping.description?.toLowerCase().contains(searchText) ?? false)
      ).toList();
    }

    setState(() {});
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
          '静态IP映射',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primaryNeon),
            onPressed: () => _showAddMappingDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: '搜索域名或IP地址...',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                border: InputBorder.none,
                icon: Icon(Icons.search, color: AppTheme.textSecondary),
              ),
              onChanged: (value) => _refreshMappings(),
            ),
          ),

          // 映射列表
          Expanded(
            child: _filteredMappings.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredMappings.length,
                    itemBuilder: (context, index) {
                      final mapping = _filteredMappings[index];
                      return _buildMappingCard(mapping, index);
                    },
                  ),
          ),
        ],
      ),
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
              Icons.dns_outlined,
              size: 40,
              color: AppTheme.primaryNeon,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '暂无静态IP映射',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击右上角的 + 按钮添加新的映射规则',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建映射卡片
  Widget _buildMappingCard(StaticIpMapping mapping, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: mapping.enabled
              ? AppTheme.primaryNeon.withAlpha(50)
              : AppTheme.borderColor.withAlpha(100),
        ),
      ),
      child: Row(
        children: [
          // 启用/禁用指示器
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: mapping.enabled ? AppTheme.primaryNeon : AppTheme.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),

          // 域名和IP信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mapping.domain,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      mapping.ipAddress,
                      style: const TextStyle(
                        color: AppTheme.primaryNeon,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (mapping.description != null && mapping.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    mapping.description!,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 操作按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 启用/禁用按钮
              Switch(
                value: mapping.enabled,
                onChanged: (value) => _toggleMapping(index),
                thumbColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) => states.contains(WidgetState.selected)
                      ? AppTheme.primaryNeon
                      : null,
                ),
              ),
              const SizedBox(width: 8),

              // 编辑按钮
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: AppTheme.textSecondary),
                onPressed: () => _showEditMappingDialog(mapping, index),
              ),

              // 删除按钮
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: AppTheme.errorRed),
                onPressed: () => _showDeleteConfirmDialog(index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 切换映射启用状态
  void _toggleMapping(int index) {
    final realIndex = _getRealIndex(index);
    if (realIndex == -1) return;

    final mapping = _dnsManager.staticIpMappings[realIndex];
    final updatedMapping = mapping.copyWith(enabled: !mapping.enabled);
    _dnsManager.updateStaticIpMapping(realIndex, updatedMapping);
    _refreshMappings();
  }

  /// 获取在原始列表中的真实索引
  int _getRealIndex(int filteredIndex) {
    if (filteredIndex >= _filteredMappings.length) return -1;
    final mapping = _filteredMappings[filteredIndex];
    return _dnsManager.staticIpMappings.indexOf(mapping);
  }

  /// 显示添加映射对话框
  void _showAddMappingDialog() {
    _showMappingDialog(null, -1);
  }

  /// 显示编辑映射对话框
  void _showEditMappingDialog(StaticIpMapping mapping, int filteredIndex) {
    final realIndex = _getRealIndex(filteredIndex);
    if (realIndex == -1) return;
    _showMappingDialog(mapping, realIndex);
  }

  /// 显示映射编辑对话框
  void _showMappingDialog(StaticIpMapping? mapping, int index) {
    final domainController = TextEditingController(text: mapping?.domain ?? '');
    final ipController = TextEditingController(text: mapping?.ipAddress ?? '');
    final descriptionController = TextEditingController(text: mapping?.description ?? '');
    bool enabled = mapping?.enabled ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(
            mapping == null ? '添加静态IP映射' : '编辑静态IP映射',
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 域名输入
                const Text(
                  '域名',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: domainController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '例如: example.com',
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // IP地址输入
                const Text(
                  'IP地址',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ipController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '例如: 192.168.1.1',
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // 描述输入
                const Text(
                  '描述 (可选)',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '添加备注说明',
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // 启用开关
                Row(
                  children: [
                    const Text(
                      '启用映射',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: enabled,
                      onChanged: (value) => setDialogState(() => enabled = value),
                      thumbColor: WidgetStateProperty.resolveWith<Color?>(
                        (states) => states.contains(WidgetState.selected)
                            ? AppTheme.primaryNeon
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(context),
              child: const Text(
                '取消',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => _saveMappingDialog(
                domainController.text,
                ipController.text,
                descriptionController.text,
                enabled,
                index,
              ),
              child: const Text(
                '保存',
                style: TextStyle(color: AppTheme.primaryNeon),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 保存映射对话框
  void _saveMappingDialog(
    String domain,
    String ipAddress,
    String description,
    bool enabled,
    int index,
  ) {
    // 验证输入
    if (domain.trim().isEmpty) {
      _showErrorSnackBar('请输入域名');
      return;
    }

    if (ipAddress.trim().isEmpty) {
      _showErrorSnackBar('请输入IP地址');
      return;
    }

    // 简单的IP地址格式验证
    final ipRegex = RegExp(
      r'^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    );
    if (!ipRegex.hasMatch(ipAddress.trim())) {
      _showErrorSnackBar('请输入有效的IP地址');
      return;
    }

    final mapping = StaticIpMapping(
      domain: domain.trim(),
      ipAddress: ipAddress.trim(),
      description: description.trim().isEmpty ? null : description.trim(),
      enabled: enabled,
    );

    if (index == -1) {
      // 检查是否已存在相同域名的映射
      final existingIndex = _dnsManager.staticIpMappings.indexWhere(
        (m) => m.domain.toLowerCase() == mapping.domain.toLowerCase()
      );

      if (existingIndex != -1) {
        _showErrorSnackBar('该域名已存在映射规则');
        return;
      }

      _dnsManager.addStaticIpMapping(mapping);
    } else {
      // 检查是否与其他映射冲突
      final conflictIndex = _dnsManager.staticIpMappings.indexWhere(
        (m) => m.domain.toLowerCase() == mapping.domain.toLowerCase() &&
               _dnsManager.staticIpMappings.indexOf(m) != index
      );

      if (conflictIndex != -1) {
        _showErrorSnackBar('该域名已存在映射规则');
        return;
      }

      _dnsManager.updateStaticIpMapping(index, mapping);
    }

    _refreshMappings();
    safePop(context);
    _showSuccessSnackBar(index == -1 ? '映射规则添加成功' : '映射规则更新成功');
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog(int filteredIndex) {
    final realIndex = _getRealIndex(filteredIndex);
    if (realIndex == -1) return;

    final mapping = _dnsManager.staticIpMappings[realIndex];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          '删除映射',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要删除域名 "${mapping.domain}" 的映射规则吗？',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              _dnsManager.removeStaticIpMapping(realIndex);
              _refreshMappings();
              safePop(context);
              _showSuccessSnackBar('映射规则删除成功');
            },
            child: const Text(
              '删除',
              style: TextStyle(color: AppTheme.errorRed),
            ),
          ),
        ],
      ),
    );
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