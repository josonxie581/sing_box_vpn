package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"math/big"
	"net"
	"testing"
	"time"

	quic "github.com/sagernet/quic-go"
)

func TestProbeTCPRequiresRemoteConnect(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	go func() {
		conn, err := listener.Accept()
		if err == nil {
			conn.Close()
		}
	}()
	request := nodeDelayRequest{Type: "vmess", Server: "127.0.0.1", Port: port}
	delay, err := probeNodeDelay(request, time.Second)
	listener.Close()
	if err != nil || delay < 0 {
		t.Fatalf("open TCP: delay=%d error=%v", delay, err)
	}
	if delay, err = probeNodeDelay(request, time.Second); err == nil || delay != -1 {
		t.Fatalf("refused TCP must not report RTT: delay=%d error=%v", delay, err)
	}
}

func TestProbeRejectsFakeIP(t *testing.T) {
	_, err := probeNodeDelay(nodeDelayRequest{Type: "vmess", Server: "198.18.0.2", Port: 443}, time.Second)
	if err == nil {
		t.Fatal("FakeIP must not be measured as a real server")
	}
}

func TestQUICDoesNotFallBackToTCP(t *testing.T) {
	// TCP succeeds on this port, but there is no QUIC listener there.
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	request := nodeDelayRequest{Type: "tuic", Server: "127.0.0.1", Port: listener.Addr().(*net.TCPAddr).Port}
	request.TLS.Insecure = true
	delay, err := probeNodeDelay(request, 150*time.Millisecond)
	if err == nil || delay != -1 {
		t.Fatalf("UDP failure became TCP success: %d %v", delay, err)
	}
}

type delayedPackets struct{ net.PacketConn }

func (c delayedPackets) ReadFrom(p []byte) (int, net.Addr, error) {
	n, addr, err := c.PacketConn.ReadFrom(p)
	if err == nil {
		time.Sleep(30 * time.Millisecond)
	}
	return n, addr, err
}
func (c delayedPackets) WriteTo(p []byte, addr net.Addr) (int, error) {
	time.Sleep(30 * time.Millisecond)
	return c.PacketConn.WriteTo(p, addr)
}

func TestQUICUsesAcknowledgedRTT(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour)}
	cert, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	udp, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer udp.Close()
	server, err := quic.Listen(delayedPackets{udp}, &tls.Config{
		Certificates: []tls.Certificate{{Certificate: [][]byte{cert}, PrivateKey: key}}, NextProtos: []string{"h3"},
	}, &quic.Config{})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	go func() {
		for {
			if _, err := server.Accept(ctx); err != nil {
				return
			}
		}
	}()
	for _, protocol := range []string{"hysteria2", "tuic"} {
		request := nodeDelayRequest{Type: protocol, Server: "127.0.0.1", Port: udp.LocalAddr().(*net.UDPAddr).Port}
		request.TLS.Insecure = true
		started := time.Now()
		delay, err := probeNodeDelay(request, 3*time.Second)
		elapsed := time.Since(started).Milliseconds()
		if err != nil {
			t.Fatal(err)
		}
		if delay < 50 || int64(delay) > elapsed {
			t.Fatalf("%s RTT=%d handshake=%d", protocol, delay, elapsed)
		}
		t.Logf("%s measured RTT=%dms; handshake elapsed=%dms", protocol, delay, elapsed)
	}
}
