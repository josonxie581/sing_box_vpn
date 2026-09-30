/// 无需用户配置的 OpenAI / Anthropic 代理规则。
/// 域名清单核对日期：2026-09-30。
/// https://help.openai.com/en/articles/9247338-network-recommendations-for-chatgpt-errors-on-web-and-apps
/// https://code.claude.com/docs/en/network-config
/// https://github.com/v2fly/domain-list-community/tree/master/data
class BuiltinProxyRules {
  // 后缀同时匹配根域名和所有子域名。
  static const domainSuffixes = <String>[
    'openai.com',
    'chatgpt.com',
    'chat.com',
    'sora.com',
    'oaistatic.com',
    'oaiusercontent.com',
    'oaistatsig.com',
    'openaimerge.com',
    'openai.com.cdn.cloudflare.net',
    'anthropic.com',
    'claude.ai',
    'claude.com',
    'clau.de',
    'claudeusercontent.com',
    'claudemcpclient.com',
    'claudemcpcontent.com',
    'chatgpt.livekit.cloud',
    'host.livekit.cloud',
    'turn.livekit.cloud',
    'ct.sendgrid.net',
    'intercom.io',
    'intercomcdn.com',
  ];

  // 共享 CDN、登录、支付及遥测只匹配服务使用的主机，避免代理整个云平台。
  static const domains = <String>[
    'challenges.cloudflare.com',
    'cdn.workos.com',
    'forwarder.workos.com',
    'setup.workos.com',
    'images.workoscdn.com',
    'workos.imgix.net',
    'humb.apple.com',
    'js.stripe.com',
    'o207216.ingest.sentry.io',
    'o33249.ingest.sentry.io',
    'rum.browser-intake-datadoghq.com',
    'browser-intake-datadoghq.com',
    'http-intake.logs.us5.datadoghq.com',
    'browser-intake-us5-datadoghq.com',
    'openai.qualtrics.com',
    'openaiapi-site.azureedge.net',
    'openaiassets.blob.core.windows.net',
    'openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net',
    'openaicom.imgix.net',
    'openaicomproductionae4b.blob.core.windows.net',
    'production-openaicom-storage.azureedge.net',
    'servd-anthropic-website.b-cdn.net',
    'cdnjs.cloudflare.com',
    'cdn.jsdelivr.net',
    'cdn.tailwindcss.com',
    'code.jquery.com',
    'unpkg.com',
    'fonts.googleapis.com',
    'fonts.gstatic.com',
  ];

  static const domainRegexes = <String>[
    r'^chatgpt-async-webps-prod-\S+-\d+\.webpubsub\.azure\.com$',
  ];

  // Anthropic 发布的 API / Console 入站地址，不能使用其出站工具地址替代。
  // https://platform.claude.com/docs/en/api/ip-addresses
  static const anthropicIpCidrs = <String>['160.79.104.0/23', '2607:6bc0::/48'];

  // ChatGPT Voice 的 UDP/3478 地址，来自官方清单；仅匹配语音端口。
  // https://openai.com/chatgpt-voice.json
  static const voiceIpCidrs = <String>[
    '102.37.57.54/32',
    '13.71.25.29/32',
    '135.220.40.201/32',
    '172.203.39.49/32',
    '172.207.173.200/32',
    '172.214.226.198/32',
    '191.233.251.27/32',
    '20.162.96.163/32',
    '20.168.48.117/32',
    '20.184.36.134/32',
    '20.203.144.245/32',
    '20.74.221.21/32',
    '4.151.200.38/32',
    '4.155.146.196/32',
    '4.197.172.116/32',
    '4.217.235.100/32',
    '4.245.198.13/32',
    '40.118.236.137/32',
    '51.4.112.173/32',
    '52.143.181.161/32',
    '68.155.152.41/32',
    '72.146.20.246/32',
    '74.248.148.7/32',
  ];

  static Map<String, dynamic> domainMatcher() => {
    'domain_suffix': domainSuffixes.toList(),
    'domain': domains.toList(),
    'domain_regex': domainRegexes.toList(),
  };

  static List<Map<String, dynamic>> routeRules() => [
    {...domainMatcher(), 'outbound': 'proxy'},
    {'ip_cidr': anthropicIpCidrs.toList(), 'outbound': 'proxy'},
    {
      'network': 'udp',
      'port': 3478,
      'ip_cidr': voiceIpCidrs.toList(),
      'outbound': 'proxy',
    },
  ];
}
