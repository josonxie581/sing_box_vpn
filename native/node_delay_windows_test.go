package main

import (
	"context"
	"net"
	"syscall"
	"testing"
)

func TestProbeBindsPhysicalInterface(t *testing.T) {
	bind, err := physicalProbeControl()
	if err != nil {
		t.Fatal(err)
	}
	listener := net.ListenConfig{Control: bind}
	conn, err := listener.ListenPacket(context.Background(), "udp4", "0.0.0.0:0")
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	raw, err := conn.(*net.UDPConn).SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	var boundInterface int
	var optionErr error
	err = raw.Control(func(fd uintptr) {
		// The actual WinSock socket must carry IP_UNICAST_IF, even with TUN up.
		boundInterface, optionErr = syscall.GetsockoptInt(syscall.Handle(fd), syscall.IPPROTO_IP, 31)
	})
	if err != nil || optionErr != nil || boundInterface == 0 {
		t.Fatalf("physical interface binding missing: %d %v %v", boundInterface, err, optionErr)
	}
}
