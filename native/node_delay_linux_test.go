//go:build linux && !android

package main

import (
	"context"
	"errors"
	"net"
	"testing"

	"golang.org/x/sys/unix"
)

func TestLinuxProbeBindsPhysicalInterface(t *testing.T) {
	bind, err := physicalProbeControl()
	if err != nil {
		t.Fatal(err)
	}
	listener := net.ListenConfig{Control: bind}
	conn, err := listener.ListenPacket(context.Background(), "udp4", "0.0.0.0:0")
	if errors.Is(err, unix.EPERM) || errors.Is(err, unix.EACCES) {
		t.Skip("physical interface binding requires CAP_NET_RAW on this kernel")
	}
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	raw, err := conn.(*net.UDPConn).SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	var device string
	var socketErr error
	err = raw.Control(func(fd uintptr) {
		device, socketErr = unix.GetsockoptString(int(fd), unix.SOL_SOCKET, unix.SO_BINDTODEVICE)
	})
	if err != nil || socketErr != nil || device == "" || device == "gsou-tun" {
		t.Fatalf("missing physical binding: %q %v %v", device, err, socketErr)
	}
}
