"""Small, credential-free vocabulary for the two existing VPS exits."""
import copy
import ipaddress
import re

AU_TAG = "au-residential-ai"
CLAUDE_DOMAINS = ["anthropic.com", "claude.ai", "claude.com", "claude.app", "clau.de", "claudeusercontent.com", "claudemcpclient.com", "claudemcpcontent.com"]
CLAUDE_EXACT = ["servd-anthropic-website.b-cdn.net"]
CLAUDE_CIDRS = ["160.79.104.0/23", "2607:6bc0::/48"]
OPENAI_DOMAINS = ["openai.com", "chatgpt.com", "chat.com", "sora.com", "oaistatic.com", "oaiusercontent.com", "oaistatsig.com", "openaimerge.com", "openai.com.cdn.cloudflare.net"]
DEFAULT_POLICY = {"default": "direct", "claude": "au", "openai": "direct", "australia_domains": [], "direct_domains": []}


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


def normalize(payload):
    if not isinstance(payload, dict) or set(payload) != set(DEFAULT_POLICY):
        raise ValueError("规则字段不完整或包含不支持的设置")
    result = {}
    for key in ("default", "claude", "openai"):
        if payload[key] not in ("direct", "au"):
            raise ValueError("出口必须选择日本 DMIT 或澳洲住宅 IP")
        result[key] = payload[key]
    for key in ("australia_domains", "direct_domains"):
        values = payload[key]
        if not isinstance(values, list) or len(values) > 80:
            raise ValueError("每个出口最多填写 80 个自定义域名")
        result[key] = sorted({domain(value) for value in values})
    for a in result["australia_domains"]:
        for b in result["direct_domains"]:
            if matches(a, b) or matches(b, a):
                raise ValueError("两个出口包含重叠域名，请移除冲突规则")
    return result


def matches(host, suffix):
    return host == suffix or host.endswith("." + suffix)


def select(policy, host):
    for key, exit_name in (("direct_domains", "direct"), ("australia_domains", "au")):
        if any(matches(host, suffix) for suffix in policy[key]):
            return exit_name
    if any(matches(host, suffix) for suffix in CLAUDE_DOMAINS) or host in CLAUDE_EXACT:
        return policy["claude"]
    if any(matches(host, suffix) for suffix in OPENAI_DOMAINS):
        return policy["openai"]
    return policy["default"]


def build(config, payload):
    policy = normalize(payload)
    tags = {item.get("tag") for item in config.get("outbounds", [])}
    if not {"direct", AU_TAG}.issubset(tags):
        raise ValueError("VPS 缺少已配置的出口，请联系管理员")
    candidate = copy.deepcopy(config)
    rules = [{"port": [80, 443, 8443], "action": "sniff", "sniffer": ["http", "tls", "quic"], "timeout": "300ms"}]
    for key, target in (("direct_domains", "direct"), ("australia_domains", "au")):
        if policy[key]:
            rules.append({"domain_suffix": policy[key], "action": "route", "outbound": AU_TAG if target == "au" else "direct"})
    for name, suffixes in (("claude", CLAUDE_DOMAINS), ("openai", OPENAI_DOMAINS)):
        if policy[name] == policy["default"]:
            continue
        target = AU_TAG if policy[name] == "au" else "direct"
        rule = {"domain_suffix": suffixes, "action": "route", "outbound": target}
        if name == "claude":
            rule = {"domain_suffix": suffixes, "domain": CLAUDE_EXACT, "action": "route", "outbound": target}
        rules.append(rule)
        if name == "claude":
            rules.append({"ip_cidr": CLAUDE_CIDRS, "action": "route", "outbound": target})
    candidate.setdefault("route", {}).update(final=AU_TAG if policy["default"] == "au" else "direct", rules=rules)
    for server in candidate.get("dns", {}).get("servers", []):
        if server.get("tag") == "google-dns":
            server.pop("detour", None)
    return candidate


def infer(config):
    """Import the existing Claude-only policy; mark other configurations explicitly."""
    final = config.get("route", {}).get("final")
    policy = copy.deepcopy(DEFAULT_POLICY)
    policy["default"] = "au" if final == AU_TAG else "direct"
    policy["claude"] = policy["openai"] = policy["default"]
    unsupported = final not in ("direct", AU_TAG)
    for rule in config.get("route", {}).get("rules", []):
        if rule.get("action") == "sniff":
            continue
        target = rule.get("outbound")
        if rule.get("action") != "route" or target not in ("direct", AU_TAG):
            unsupported = True
            continue
        value = "au" if target == AU_TAG else "direct"
        suffixes = rule.get("domain_suffix", [])
        if set(suffixes) == set(CLAUDE_DOMAINS) or set(rule.get("ip_cidr", [])) == set(CLAUDE_CIDRS):
            policy["claude"] = value
        elif set(suffixes) == set(OPENAI_DOMAINS):
            policy["openai"] = value
        elif suffixes and set(rule).issubset({"domain_suffix", "action", "outbound"}):
            policy["australia_domains" if value == "au" else "direct_domains"].extend(suffixes)
        else:
            unsupported = True
    return normalize(policy), unsupported
