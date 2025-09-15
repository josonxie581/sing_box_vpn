Simple Build

make
Or build and install binary to $GOBIN:


make install
 Custom Build

TAGS="tag_a tag_b" make
or


go build -tags "tag_a tag_b" ./cmd/sing-box
 Build Tags
Build Tag	Enabled by default	Description
with_quic		Build with QUIC support, see QUIC and HTTP3 DNS transports, Naive inbound, Hysteria Inbound, Hysteria Outbound and V2Ray Transport#QUIC.
with_grpc	️	Build with standard gRPC support, see V2Ray Transport#gRPC.
with_dhcp		Build with DHCP support, see DHCP DNS transport.
with_wireguard		Build with WireGuard support, see WireGuard outbound.
with_utls		Build with uTLS support for TLS outbound, see TLS.
with_acme		Build with ACME TLS certificate issuer support, see TLS.
with_clash_api		Build with Clash API support, see Experimental.
with_v2ray_api	️	Build with V2Ray API support, see Experimental.
with_gvisor		Build with gVisor support, see Tun inbound and WireGuard outbound.
with_embedded_tor (CGO required)	️	Build with embedded Tor support, see Tor outbound.
with_tailscale		Build with Tailscale support, see Tailscale endpoint