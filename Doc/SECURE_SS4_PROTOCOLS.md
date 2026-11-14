# secure_ss4.sh 服务端协议配置

脚本默认使用官方 sing-box **v1.14.4**，与本次 Windows 客户端一致。需要 Bash、Python 3、OpenSSL、curl，以及脚本原有系统工具。官方发布 API 的资产 SHA-256 缺失或不匹配时停止安装，不使用第三方下载镜像。

## 新安装

在 Linux VPS 的目标父目录运行：

```bash
bash secure_ss4.sh
```

默认保留 VMess、TUIC、Hysteria2，并新增 **Snell v6**。Snell 自动选择 TCP 端口，使用随机 PSK；可通过 `SNELL_PORT=20004` 指定端口，或 `ENABLE_SNELL=0` 禁用。新协议端口不得与现有三个端口重复。服务器防火墙及云安全组仍需按输出放行。

Hysteria2 默认不启用混淆，BBR profile 为 `standard`。按需启用：

```bash
HY2_OBFS=salamander HY2_BBR_PROFILE=conservative bash secure_ss4.sh
```

`HY2_OBFS` 支持 `none`、`salamander`、`gecko`；混淆密码默认随机生成。`HY2_BBR_PROFILE` 支持 `standard`、`conservative`、`aggressive`。生成的 Hysteria2 链接包含相同参数，导入更新后的客户端即可。

## 可选 Naive HTTP/2 与 HTTP/3

先准备解析到 VPS 的域名，以及可信 CA 签发的完整证书链和对应私钥。证书文件必须位于安装目录外；脚本检查有效期、域名、系统信任链和密钥匹配，不自动申请或续期证书。

```bash
NAIVE_DOMAIN=proxy.example.com \
NAIVE_PORT=10443 \
NAIVE_CERT_FILE=/etc/letsencrypt/live/proxy.example.com/fullchain.pem \
NAIVE_KEY_FILE=/etc/letsencrypt/live/proxy.example.com/privkey.pem \
bash secure_ss4.sh
```

Naive 同时监听该端口的 TCP 与 UDP，并分别生成 `naive+https://`、`naive+quic://` 两条链接。客户端保持证书验证。默认用户名 `gsou`、密码随机生成；可通过 `NAIVE_USERNAME`、`NAIVE_PASSWORD` 覆盖。证书应由原证书工具续期，更新后需确认代理已加载新证书。

Naive 链接直连服务器 IP，通过 `sni` 指定证书域名，避免域名启用 Cloudflare 代理时把节点流量送到 Cloudflare。

## 文件与现有服务器

- 配置：`sing-box/config.json`；原始链接：`sing-box/web/list.txt`；Base64 订阅：`sing-box/web/v2.log`。这些文件含凭据，权限设为 `600`。
- Snell 分享链接采用本工程支持的格式，不能保证其他客户端均能导入。
- **这是安装/重装脚本，不是原地迁移工具。** 检测到安装时默认返回；选择重装会删除旧安装目录并重新生成节点。现有 VPS 请先备份整个目录，安排停机和重新导入节点，勿直接确认重装。
- HY2/TUIC 延续原有自签证书和跳过验证链接；本次没有把它们自动迁移到可信域名证书。Naive 使用独立证书路径。
- Hysteria2 端口跳跃需要额外配置 UDP 端口转发；Realm 需要外部协调服务。本脚本没有自动部署这两项基础设施，也不生成未配置的跳跃/Realm 链接。
- MASQUE 属于此前单独验证的实验版本，不加入本稳定版安装脚本。
- 本机验证包括 Bash 语法、隔离安装回归、链接与凭据一致性、校验失败拦截，以及 Windows 1.14.4 内核对完整生成配置的检查；不代表已在 Linux VPS 完成公网运行验证。

官方配置参考：[Snell](https://sing-box.sagernet.org/configuration/inbound/snell/)、[Naive](https://sing-box.sagernet.org/configuration/inbound/naive/)、[Hysteria2](https://sing-box.sagernet.org/configuration/inbound/hysteria2/)。

2026-11-15 DMIT 链路排查：Gecko 在连续测试中出现握手/测速失败，同一测试端口切换混淆后 Salamander 表现更稳定；正式节点仅将混淆类型改为 Salamander，保留端口和凭据，随后连续 20 轮 HTTPS 联网与传输 RTT 测试通过（71–100 ms）。这是当前链路上的实测结果，不代表长期无故障保证。既有 Gecko 节点需同步修改客户端混淆类型；AWS 现有节点未在此次排障中修改。
