import 'package:flutter/material.dart';
import '../models/custom_rule.dart';
import '../services/custom_rules_service.dart';
import '../theme/app_theme.dart';

/// 添加/编辑自定义规则对话框
class AddCustomRuleDialog extends StatefulWidget {
  final CustomRule? editingRule; // 如果不为null，则为编辑模式

  const AddCustomRuleDialog({
    super.key,
    this.editingRule,
  });

  @override
  State<AddCustomRuleDialog> createState() => _AddCustomRuleDialogState();
}

class _AddCustomRuleDialogState extends State<AddCustomRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();

  RuleType _selectedRuleType = RuleType.domain;
  OutboundType _selectedOutbound = OutboundType.proxy;
  bool _enabled = true;
  bool _isLoading = false;

  bool get _isEditing => widget.editingRule != null;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  void _initializeForm() {
    if (_isEditing && widget.editingRule != null) {
      final rule = widget.editingRule!;
      _nameController.text = rule.name;
      _descriptionController.text = rule.description;
      _valueController.text = rule.value;
      _selectedRuleType = rule.type;
      _selectedOutbound = OutboundType.fromValue(rule.outbound);
      _enabled = rule.enabled;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.borderColor, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isEditing ? Icons.edit : Icons.add,
                  color: AppTheme.primaryNeon,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isEditing ? '编辑自定义规则' : '添加自定义规则',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 规则名称
                    _buildTextField(
                        controller: _nameController,
                        label: '规则名称',
                        hint: '输入规则名称',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入规则名称';
                          }

                          final service = CustomRulesService.instance;
                          if (!service.isRuleNameAvailable(
                              value.trim(), excludeId: widget.editingRule?.id)) {
                            return '规则名称已存在';
                          }

                          return null;
                        },
                    ),

                    const SizedBox(height: 16),

                    // 规则描述
                    _buildTextField(
                      controller: _descriptionController,
                      label: '规则描述',
                      hint: '输入规则描述（可选）',
                      maxLines: 2,
                    ),

                    const SizedBox(height: 16),

                    // 规则类型选择
                    _buildRuleTypeSelector(),

                    const SizedBox(height: 16),

                    // 规则值输入
                    _buildRuleValueField(),

                    const SizedBox(height: 16),

                    // 出站选择
                    _buildOutboundSelector(),

                    const SizedBox(height: 16),

                    // 启用开关
                    _buildEnabledSwitch(),

                    const SizedBox(height: 32),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: AppTheme.borderColor),
                              ),
                            ),
                            child: const Text(
                              '取消',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryNeon,
                              foregroundColor: AppTheme.bgDark,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.bgDark),
                                    ),
                                  )
                                : Text(_isEditing ? '保存' : '添加'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.bgDark,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.errorRed),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildRuleTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '规则类型',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.bgDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
          ),
          child: DropdownButton<RuleType>(
            value: _selectedRuleType,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppTheme.bgCard,
            style: const TextStyle(color: AppTheme.textPrimary),
            onChanged: (RuleType? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedRuleType = newValue;
                  // 清空值字段，让用户重新输入
                  _valueController.clear();
                });
              }
            },
            items: RuleType.values.map<DropdownMenuItem<RuleType>>((RuleType type) {
              return DropdownMenuItem<RuleType>(
                value: type,
                child: Row(
                  children: [
                    Text(
                      type.icon,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            type.displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            type.description,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRuleValueField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '规则值',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _valueController,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '请输入规则值';
            }

            if (!_selectedRuleType.isValidValue(value.trim())) {
              return '规则值格式不正确';
            }

            return null;
          },
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: '示例: ${_selectedRuleType.example}',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.bgDark,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.errorRed),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: IconButton(
              icon: const Icon(Icons.help_outline, color: AppTheme.textSecondary, size: 18),
              onPressed: () => _showRuleTypeHelp(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _selectedRuleType.description,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildOutboundSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '出站方式',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.bgDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderColor.withAlpha(100)),
          ),
          child: DropdownButton<OutboundType>(
            value: _selectedOutbound,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppTheme.bgCard,
            style: const TextStyle(color: AppTheme.textPrimary),
            onChanged: (OutboundType? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedOutbound = newValue;
                });
              }
            },
            items: OutboundType.values.map<DropdownMenuItem<OutboundType>>((OutboundType type) {
              final color = Color(int.parse(type.colorValue.substring(1, 7), radix: 16) + 0xFF000000);
              return DropdownMenuItem<OutboundType>(
                value: type,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            type.displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            type.description,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEnabledSwitch() {
    return Row(
      children: [
        const Text(
          '启用规则',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const Spacer(),
        Switch(
          value: _enabled,
          onChanged: (bool value) {
            setState(() {
              _enabled = value;
            });
          },
          activeThumbColor: AppTheme.primaryNeon,
          inactiveThumbColor: AppTheme.textSecondary,
          inactiveTrackColor: AppTheme.bgDark,
        ),
      ],
    );
  }

  void _showRuleTypeHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            Text(_selectedRuleType.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              _selectedRuleType.displayName,
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedRuleType.description,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '示例格式:',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderColor.withAlpha(50)),
              ),
              child: Text(
                _selectedRuleType.example,
                style: const TextStyle(
                  color: AppTheme.primaryNeon,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '了解',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final service = CustomRulesService.instance;
      await service.initialize();

      final rule = CustomRule(
        id: _isEditing
            ? widget.editingRule!.id
            : service.generateRuleId(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        type: _selectedRuleType,
        value: _valueController.text.trim(),
        outbound: _selectedOutbound.value,
        enabled: _enabled,
        createdAt: _isEditing
            ? widget.editingRule!.createdAt
            : DateTime.now(),
        updatedAt: _isEditing ? DateTime.now() : null,
      );

      bool success;
      if (_isEditing) {
        success = await service.updateRule(rule.id, rule);
      } else {
        success = await service.addRule(rule);
      }

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isEditing ? '规则更新成功' : '规则添加成功',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              backgroundColor: AppTheme.successGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop(true); // 返回true表示操作成功
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isEditing ? '规则更新失败' : '规则添加失败',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              backgroundColor: AppTheme.errorRed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '操作失败: $e',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}