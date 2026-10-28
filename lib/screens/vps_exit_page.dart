import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/vps_exit_config.dart';
import '../services/vps_exit_controller.dart';
import '../services/vps_exit_service.dart';
import '../theme/app_theme.dart';

class VpsExitPage extends StatefulWidget {
  const VpsExitPage({
    super.key,
    this.serverHost,
    this.controller,
    this.initialProfile,
  });
  final String? serverHost;
  final VpsExitController? controller;
  final VpsExitProfile? initialProfile;
  @override
  State<VpsExitPage> createState() => _VpsExitPageState();
}

class _VpsExitPageState extends State<VpsExitPage> {
  late final VpsExitController _controller;
  final _connectionForm = GlobalKey<FormState>();
  final _host = TextEditingController(),
      _port = TextEditingController(text: '22');
  final _user = TextEditingController(text: 'root');
  final _key = TextEditingController(), _knownHosts = TextEditingController();
  final _auDomains = TextEditingController(),
      _directDomains = TextEditingController();
  VpsExitTarget _claude = VpsExitTarget.australia,
      _openai = VpsExitTarget.direct,
      _default = VpsExitTarget.direct;
  bool _dirty = false, _connectionDirty = false, _connectionOpen = true;
  VpsExitStatus? _seen;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? VpsExitController(VpsExitService());
    _controller.addListener(_changed);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final saved = widget.initialProfile ?? await VpsExitService.loadProfile();
      if (!mounted) return;
      _host.text = saved?.host ?? widget.serverHost ?? '';
      if (saved != null) {
        _port.text = '${saved.port}';
        _user.text = saved.user;
        _key.text = saved.identityFile;
        _knownHosts.text = saved.knownHostsFile;
        setState(() => _connectionDirty = false);
        await _controller.connect(saved);
      }
    } on Object {
      if (mounted) setState(() => _localError = '已保存的 SSH 连接无效，请重新填写');
    }
  }

  void _fill(VpsExitPolicy policy) {
    _claude = policy.claude;
    _openai = policy.openai;
    _default = policy.defaultTarget;
    _auDomains.text = policy.australiaDomains.join('\n');
    _directDomains.text = policy.directDomains.join('\n');
    _dirty = false;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      final current = _controller.status;
      if (current != null && current != _seen) {
        if (!_dirty) _fill(current.policy);
        if (_seen == null) _connectionOpen = false;
        _seen = current;
      }
    });
  }

  VpsExitPolicy _policy() => VpsExitPolicy(
    defaultTarget: _default,
    claude: _claude,
    openai: _openai,
    australiaDomains: _lines(_auDomains.text),
    directDomains: _lines(_directDomains.text),
  ).normalized();
  List<String> _lines(String text) => text
      .split(RegExp(r'\r?\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  bool get _blocked =>
      _controller.busy ||
      _controller.status == null ||
      _controller.status!.externalRules ||
      _connectionDirty;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _localError = null);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _localError = e is FormatException
              ? e.message.toString()
              : '操作未完成，请刷新服务器状态核对',
        );
      }
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _connect() => _run(() async {
    if (!_connectionForm.currentState!.validate()) return;
    final profile = VpsExitProfile(
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? 0,
      user: _user.text.trim(),
      identityFile: _key.text.trim(),
      knownHostsFile: _knownHosts.text.trim(),
    );
    profile.validate();
    await VpsExitService.saveProfile(profile);
    if (!mounted) return;
    setState(() {
      _connectionDirty = false;
      _dirty = false;
      _seen = null;
    });
    await _controller.connect(profile);
  });

  Future<void> _browse(TextEditingController field, String title) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: FileType.any,
      withData: false,
    );
    if (!mounted || result == null || result.files.single.path == null) return;
    setState(() {
      field.text = result.files.single.path!;
      _connectionDirty = true;
    });
  }

  Future<void> _refresh() async {
    if (_dirty && !await _confirm('刷新服务器规则', '放弃尚未应用的修改，读取 VPS 当前生效规则？')) {
      return;
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    await _run(_controller.refresh);
  }

  Future<void> _apply({bool rollback = false}) async {
    if (_blocked) return;
    if (!await _confirm(
      rollback ? '回滚上一版规则' : '应用 VPS 出口规则',
      rollback
          ? '将恢复 ${_controller.profile!.host} 的上一版出口规则。现有连接可能短暂重连，验证失败会自动恢复。'
          : '将修改 ${_controller.profile!.host} 的服务器出口，网页后台也会同步。现有连接可能短暂重连，验证失败会自动恢复。',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(
      () => _controller.apply(
        rollback ? _controller.status!.policy : _policy(),
        rollback: rollback,
      ),
    );
    if (mounted && _controller.error == null && _controller.status != null) {
      setState(() => _fill(_controller.status!.policy));
    }
  }

  Future<void> _deploy() async {
    if (_controller.profile == null || _connectionDirty || _controller.busy) {
      return;
    }
    if (!await _confirm(
      '部署 / 升级出口控制服务',
      '将在 ${_controller.profile!.host} 安装控制服务，并与网页共用规则。现有 sing-box 配置会保留，正在使用的 Gsou 不会重启。服务器须已配置直连与住宅代理出口。',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(_controller.deploy);
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
  Widget _textField(
    TextEditingController controller,
    String label, {
    String? hint,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: !_controller.busy,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
      ),
      validator: (value) =>
          value == null || value.trim().isEmpty ? '请填写$label' : null,
    ),
  );

  Widget _connection() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('SSH 管理连接'),
          subtitle: Text(_controller.profile?.host ?? '使用管理用密钥连接 VPS'),
          trailing: Icon(
            _connectionOpen ? Icons.expand_less : Icons.expand_more,
          ),
          onTap: () => setState(() => _connectionOpen = !_connectionOpen),
        ),
        if (_connectionOpen)
          Form(
            key: _connectionForm,
            onChanged: () => setState(() => _connectionDirty = true),
            child: Column(
              children: [
                _textField(_host, '服务器地址', hint: 'VPS IP 或域名'),
                Row(
                  children: [
                    Expanded(child: _textField(_port, 'SSH 端口')),
                    const SizedBox(width: 12),
                    Expanded(child: _textField(_user, '管理用户名')),
                  ],
                ),
                _textField(
                  _key,
                  '私钥文件',
                  suffix: IconButton(
                    tooltip: '选择私钥文件',
                    onPressed: _controller.busy
                        ? null
                        : () => _browse(_key, '选择 OpenSSH 私钥（只使用路径，不复制密钥）'),
                    icon: const Icon(Icons.folder_open),
                  ),
                ),
                _textField(
                  _knownHosts,
                  'known_hosts 文件',
                  suffix: IconButton(
                    tooltip: '选择可信主机文件',
                    onPressed: _controller.busy
                        ? null
                        : () => _browse(_knownHosts, '选择已核对指纹的 known_hosts 文件'),
                    icon: const Icon(Icons.folder_open),
                  ),
                ),
                const Text(
                  '仅保存连接信息与文件路径；私钥保留在本机。监控用的只读密钥不能用于出口管理。',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _controller.busy ? null : _connect,
                  icon: const Icon(Icons.link),
                  label: const Text('保存连接并读取规则'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed:
              _controller.profile == null ||
                  _connectionDirty ||
                  _controller.busy
              ? null
              : _deploy,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('部署 / 升级控制服务'),
        ),
      ],
    ),
  );

  Widget _target(
    String title,
    VpsExitTarget value,
    ValueChanged<VpsExitTarget> changed,
  ) => DropdownButtonFormField<VpsExitTarget>(
    initialValue: value,
    key: ValueKey('$title-${value.value}'),
    isExpanded: true,
    decoration: InputDecoration(labelText: title),
    items: VpsExitTarget.values
        .map(
          (target) => DropdownMenuItem(
            value: target,
            child: Text(
              _controller.status!.label(target),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: _blocked
        ? null
        : (next) {
            if (next != null) {
              setState(() {
                changed(next);
                _dirty = true;
              });
            }
          },
  );

  Widget _editor(VpsExitStatus status) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '当前管理：${_controller.profile!.host}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '当前生效：Claude → ${status.label(status.policy.claude)}\nOpenAI → ${status.label(status.policy.openai)} · 默认 → ${status.label(status.policy.defaultTarget)}',
        ),
        const SizedBox(height: 8),
        Text(
          '版本 ${status.revision.substring(0, 12)} · 与网页后台共用',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        if (status.externalRules)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              '检测到不支持的外部规则，已阻止覆盖。请通过 SSH 核对。',
              style: TextStyle(color: AppTheme.warningOrange),
            ),
          ),
        if (_connectionDirty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              '连接信息已修改，请先重新连接。',
              style: TextStyle(color: AppTheme.warningOrange),
            ),
          ),
        const SizedBox(height: 22),
        _target('Claude / Anthropic', _claude, (v) => _claude = v),
        const SizedBox(height: 16),
        _target('OpenAI / ChatGPT', _openai, (v) => _openai = v),
        const SizedBox(height: 16),
        _target('其他流量的默认出口', _default, (v) => _default = v),
        const SizedBox(height: 20),
        const Text('自定义域名', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text(
          '每行一个域名，包含子域名。不要填写网址或端口；自定义规则优先于上方预设。',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _auDomains,
          enabled: !_blocked,
          minLines: 3,
          maxLines: 6,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '走住宅代理的域名',
            hintText: 'example.com',
          ),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _directDomains,
          enabled: !_blocked,
          minLines: 3,
          maxLines: 6,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '走 VPS 直连的域名',
            hintText: 'example.org',
          ),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        if (_dirty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              '有尚未应用的修改',
              style: TextStyle(color: AppTheme.warningOrange),
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: _blocked ? null : () => _apply(),
              child: const Text('保存并应用'),
            ),
            OutlinedButton(
              onPressed: _blocked
                  ? null
                  : () => _run(() => _controller.validate(_policy())),
              child: const Text('检查规则'),
            ),
            OutlinedButton(
              onPressed: _blocked
                  ? null
                  : () => setState(() {
                      _fill(const VpsExitPolicy());
                      _dirty = true;
                    }),
              child: const Text('仅 Claude 走澳洲'),
            ),
            OutlinedButton(
              onPressed: _blocked || !status.canRollback
                  ? null
                  : () => _apply(rollback: true),
              child: const Text('回滚上一版'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          '这里修改进入 VPS 后的出口。国内直连仍由 Gsou 规则模式管理。应用可能短暂重连，服务器会先校验并在失败时回滚。',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        if (status.history.isNotEmpty)
          ExpansionTile(
            title: const Text('最近应用记录'),
            children: status.history
                .map(
                  (item) => ListTile(
                    dense: true,
                    title: Text('${item['message'] ?? ''}'),
                    subtitle: Text(
                      item['finished'] is num
                          ? DateTime.fromMillisecondsSinceEpoch(
                              ((item['finished'] as num) * 1000).round(),
                            ).toLocal().toString().split('.').first
                          : '',
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('VPS 出口管控'),
      actions: [
        IconButton(
          tooltip: '刷新服务器规则',
          onPressed:
              _controller.busy ||
                  _connectionDirty ||
                  _controller.profile == null
              ? null
              : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _connection(),
              if (_controller.busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_localError != null ||
                  _controller.error != null ||
                  _controller.message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _localError ?? _controller.error ?? _controller.message!,
                      style: TextStyle(
                        color: _localError != null || _controller.error != null
                            ? AppTheme.errorRed
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              if (_controller.status != null) _editor(_controller.status!),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    for (final field in [
      _host,
      _port,
      _user,
      _key,
      _knownHosts,
      _auDomains,
      _directDomains,
    ]) {
      field.dispose();
    }
    super.dispose();
  }
}
