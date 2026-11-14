package main

import (
	"context"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

func TestAndroidProbeUsesVpnExcludedAppSockets(t *testing.T) {
	bind, err := physicalProbeControl()
	if err != nil || bind != nil {
		t.Fatalf("Android must use the app's VPN-excluded sockets: %v", err)
	}
}

func TestAndroidModernOutboundStartup(t *testing.T) {
	for _, outbound := range []string{
		`{"type":"naive","tag":"proxy","server":"127.0.0.1","server_port":443,"username":"test","password":"test","tls":{"enabled":true,"server_name":"example.com"}}`,
		`{"type":"naive","tag":"proxy","server":"127.0.0.1","server_port":443,"username":"test","password":"test","quic":true,"tls":{"enabled":true,"server_name":"example.com"}}`,
		`{"type":"snell","tag":"proxy","server":"127.0.0.1","server_port":443,"version":6,"psk":"android-test-password"}`,
		`{"type":"hysteria2","tag":"proxy","server":"127.0.0.1","server_port":443,"password":"test","obfs":{"type":"salamander","password":"test"},"tls":{"enabled":true,"server_name":"example.com"}}`,
	} {
		ctx := include.Context(context.Background())
		var options option.Options
		if err := sjson.UnmarshalContext(ctx, []byte(`{"log":{"disabled":true},"outbounds":[`+outbound+`],"route":{"final":"proxy"}}`), &options); err != nil {
			t.Fatal(err)
		}
		instance, err := box.New(box.Options{Context: ctx, Options: options})
		if err != nil {
			t.Fatal(err)
		}
		if err = instance.Start(); err != nil {
			instance.Close()
			t.Fatal(err)
		}
		if err = instance.Close(); err != nil {
			t.Fatal(err)
		}
	}
}
