import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/routing_rule_config.dart';

class AddRoutingRulePage extends StatefulWidget {
  final List<String> availableRulesets;
  final List<RoutingRuleConfig> existingRules;

  const AddRoutingRulePage({
    super.key,
    required this.availableRulesets,
    required this.existingRules,
  });

  @override
  State<AddRoutingRulePage> createState() => _AddRoutingRulePageState();
}

class _AddRoutingRulePageState extends State<AddRoutingRulePage> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priorityController = TextEditingController(text: '650');

  String? _selectedRuleset;
  RuleType _selectedType = RuleType.geosite;
  OutboundAction _selectedOutbound = OutboundAction.proxy;

  @override
  void initState() {
    super.initState();
    _updateAvailableRulesets();
  }

  void _updateAvailableRulesets() {
    final availableForType = widget.availableRulesets
        .where(
          (ruleset) => _selectedType == RuleType.geoip
              ? ruleset.startsWith('geoip-')
              : ruleset.startsWith('geosite-'),
        )
        .toList();

    if (availableForType.isNotEmpty &&
        (_selectedRuleset == null ||
            !availableForType.contains(_selectedRuleset))) {
      _selectedRuleset = availableForType.first;
    }
  }

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty && _selectedRuleset != null;

  void _save() {
    if (!_canSave) return;
    final priority = int.tryParse(_priorityController.text) ?? 650;
    final rule = RoutingRuleConfig(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      type: _selectedType,
      ruleset: _selectedRuleset!,
      outbound: _selectedOutbound,
      priority: priority,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );
    Navigator.of(context).pop(rule);
  }

  @override
  Widget build(BuildContext context) {
    final availableForType = widget.availableRulesets
        .where(
          (ruleset) => _selectedType == RuleType.geoip
              ? ruleset.startsWith('geoip-')
              : ruleset.startsWith('geosite-'),
        )
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '添加分流规则',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: const Text(
              '保存',
              style: TextStyle(color: AppTheme.primaryNeon),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 规则名称
            TextField(
              controller: _nameController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '规则名称',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryNeon),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // 规则类型
            DropdownButtonFormField<RuleType>(
              value: _selectedType,
              dropdownColor: AppTheme.bgCard,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '规则类型',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
              items: RuleType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
                    _updateAvailableRulesets();
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // 规则集
            DropdownButtonFormField<String>(
              value: _selectedRuleset,
              dropdownColor: AppTheme.bgCard,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '规则集',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
              items: availableForType.map((ruleset) {
                return DropdownMenuItem(value: ruleset, child: Text(ruleset));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedRuleset = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // 出站动作
            DropdownButtonFormField<OutboundAction>(
              value: _selectedOutbound,
              dropdownColor: AppTheme.bgCard,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '出站动作',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
              items: OutboundAction.values.map((action) {
                return DropdownMenuItem(
                  value: action,
                  child: Text(action.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedOutbound = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // 优先级
            TextField(
              controller: _priorityController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '优先级 (数字越大优先级越高)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryNeon),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 描述
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '描述 (可选)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryNeon),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
