/// 代理模式枚举
enum ProxyMode {
  rule('rule', '规则', '按设定的规则跑流量'),
  global('global', '全局', '所有的流量跑代理');

  const ProxyMode(this.value, this.name, this.description);

  final String value;
  final String name;
  final String description;

  static ProxyMode fromString(String value) {
    return ProxyMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => ProxyMode.rule,
    );
  }
}