"""Credential-free policy for Japan direct, Australia and Singapore exits."""
import copy
import ipaddress
import re
from pathlib import Path
import json

AU_TAG = "au-residential-ai"
SG_TAG = "sg-residential-ai"
TARGET_TAGS = {"direct": "direct", "au": AU_TAG, "sg": SG_TAG, "australia": "australia-residential-ai"}
DOMAIN_TARGETS = (("direct_domains", "direct"), ("australia_domains", "au"), ("singapore_domains", "sg"), ("australia_exit_domains", "australia"))
CLAUDE_DOMAINS = ["anthropic.com", "claude.ai", "claude.com", "claude.app", "clau.de", "claudeusercontent.com", "claudemcpclient.com", "claudemcpcontent.com"]
CLAUDE_EXACT = ["servd-anthropic-website.b-cdn.net"]
CLAUDE_CIDRS = ["160.79.104.0/23", "2607:6bc0::/48"]
OPENAI_DOMAINS = ["openai.com", "chatgpt.com", "chat.com", "sora.com", "oaistatic.com", "oaiusercontent.com", "oaistatsig.com", "openaimerge.com", "openai.com.cdn.cloudflare.net"]
DEFAULT_POLICY = {"default": "direct", "claude": "au", "openai": "direct", "australia_domains": [], "direct_domains": [], "singapore_domains": [], "australia_exit_domains": [], "domain_rules": {}}


def domain(value):
    if not isinstance(value, str) or len(value) > 253:
        raise ValueError("域名格式无效")
    value = value.strip().lower().rstrip(".")
    if value.startswith("*."):
        value = value[2:]
    try:
        value = value.encode("idna").decode("ascii")
    except UnicodeError:
        raise ValueError("域名格式无效") from None
    if len(value) > 253 or "." not in value or any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label) for label in value.split(".")):
        raise ValueError("请填写域名，不要包含网址、路径或端口")
    try:
        ipaddress.ip_address(value)
    except ValueError:
        return value
    raise ValueError("自定义规则只接受域名")


def exit_id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}', value):
        raise ValueError('出口 ID 格式无效')
    return value


def target_tags(config):
    """Outbounds define inventory. Legacy names are aliases, never an allowlist."""
    tags = {o.get('tag') for o in config.get('outbounds', []) if o.get('type') in ('direct', 'socks', 'http')}
    result = {key: tag for key, tag in TARGET_TAGS.items() if tag in tags}
    claimed = set(result.values())
    for tag in sorted(tags - claimed):
        result[exit_id(tag)] = tag
    path = Path('/var/lib/shaowei-vpn/exits.json')
    registry = json.loads(path.read_text()) if path.exists() else {}
    for key, info in registry.items():
        tag = info.get('outbound', TARGET_TAGS.get(key, key))
        if tag in tags:
            if key != tag and tag in result and result[tag] == tag:
                del result[tag]
            result[exit_id(key)] = tag
    return result


def domain_groups(policy):
    yield from ((key, policy.get(field, [])) for field, key in DOMAIN_TARGETS)
    yield from policy.get('domain_rules', {}).items()


def normalize(payload):
    if not isinstance(payload, dict):
        raise ValueError('规则字段不完整或包含不支持的设置')
    payload = dict(payload)
    canonical = set(payload) == {'default', 'claude', 'openai', 'domain_rules'}
    if canonical:
        payload = {**copy.deepcopy(DEFAULT_POLICY), **payload}
    else:
        for key, default in [('singapore_domains', []), ('australia_exit_domains', []), ('domain_rules', {})]:
            payload.setdefault(key, default)
    if set(payload) != set(DEFAULT_POLICY):
        raise ValueError('规则字段不完整或包含不支持的设置')
    result = {key: exit_id(payload[key]) for key in ('default', 'claude', 'openai')}
    def clean(values):
        if not isinstance(values, list) or len(values) > 80:
            raise ValueError('每个出口最多填写 80 个自定义域名')
        return sorted({domain(value) for value in values})
    for key, _ in DOMAIN_TARGETS:
        result[key] = clean(payload[key])
    generic = payload['domain_rules']
    if not isinstance(generic, dict) or len(generic) > 128:
        raise ValueError('动态域名规则格式无效')
    result['domain_rules'] = {}
    legacy = {target: field for field, target in DOMAIN_TARGETS}
    for target, values in generic.items():
        exit_id(target)
        values = clean(values)
        if target in legacy:
            if result[legacy[target]]:
                raise ValueError('域名规则重复，请刷新后重试')
            result[legacy[target]] = values
        elif values:
            result['domain_rules'][target] = values
    groups = list(domain_groups(result))
    for index, (_, values) in enumerate(groups):
        for _, other in groups[index + 1:]:
            for a in values:
                for b in other:
                    if matches(a, b) or matches(b, a):
                        raise ValueError('不同出口包含重叠域名，请移除冲突规则')
    return result


def matches(host, suffix):
    return host == suffix or host.endswith("." + suffix)


def select(policy, host):
    for exit_name, domains in domain_groups(policy):
        if any(matches(host, suffix) for suffix in domains):
            return exit_name
    if any(matches(host, suffix) for suffix in CLAUDE_DOMAINS) or host in CLAUDE_EXACT:
        return policy["claude"]
    if any(matches(host, suffix) for suffix in OPENAI_DOMAINS):
        return policy["openai"]
    return policy["default"]


def build(config, payload):
    policy = normalize(payload)
    targets = target_tags(config)
    required = {policy[key] for key in ('default', 'claude', 'openai')}
    required.update(target for target, domains in domain_groups(policy) if domains)
    if not required.issubset(targets):
        raise ValueError("VPS 缺少已配置的出口，请联系管理员")
    candidate = copy.deepcopy(config)
    rules = [{"port": [80, 443, 8443], "action": "sniff", "sniffer": ["http", "tls", "quic"], "timeout": "300ms"}]
    for target, domains in domain_groups(policy):
        if domains:
            rules.append({"domain_suffix": domains, "action": "route", "outbound": targets[target]})
    for name, suffixes in (("claude", CLAUDE_DOMAINS), ("openai", OPENAI_DOMAINS)):
        if policy[name] == policy["default"]:
            continue
        target = targets[policy[name]]
        rule = {"domain_suffix": suffixes, "action": "route", "outbound": target}
        if name == "claude":
            rule = {"domain_suffix": suffixes, "domain": CLAUDE_EXACT, "action": "route", "outbound": target}
        rules.append(rule)
        if name == "claude":
            rules.append({"ip_cidr": CLAUDE_CIDRS, "action": "route", "outbound": target})
    candidate.setdefault("route", {}).update(final=targets[policy["default"]], rules=rules)
    for server in candidate.get("dns", {}).get("servers", []):
        if server.get("tag") == "google-dns":
            server.pop("detour", None)
    return candidate


def infer(config):
    """Infer all supported target/domain combinations without changing secrets."""
    final = config.get("route", {}).get("final")
    policy = copy.deepcopy(DEFAULT_POLICY)
    reverse = {tag: key for key, tag in target_tags(config).items()}
    policy["default"] = reverse.get(final, 'direct')
    policy["claude"] = policy["openai"] = policy["default"]
    unsupported = final not in reverse
    for rule in config.get("route", {}).get("rules", []):
        if rule.get("action") == "sniff":
            continue
        target = rule.get("outbound")
        if rule.get("action") != "route" or target not in reverse:
            unsupported = True
            continue
        value = reverse[target]
        suffixes = rule.get("domain_suffix", [])
        if set(suffixes) == set(CLAUDE_DOMAINS) or set(rule.get("ip_cidr", [])) == set(CLAUDE_CIDRS):
            policy["claude"] = value
        elif set(suffixes) == set(OPENAI_DOMAINS):
            policy["openai"] = value
        elif suffixes and set(rule).issubset({"domain_suffix", "action", "outbound"}):
            key = next((key for key, exit_name in DOMAIN_TARGETS if exit_name == value), None)
            if key:
                policy[key].extend(suffixes)
            else:
                policy['domain_rules'].setdefault(value, []).extend(suffixes)
        else:
            unsupported = True
    return normalize(policy), unsupported
