//go:build windows

package main

import (
	"errors"
	"flag"
	"fmt"
	"os"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wintun"
)

func usage() {
	fmt.Fprintf(os.Stderr, "wintunctl - manage Wintun adapter for gsou\n")
	fmt.Fprintf(os.Stderr, "\nUsage:\n")
	fmt.Fprintf(os.Stderr, "  wintunctl install [-name \"Wintun Gsou\"]\n")
	fmt.Fprintf(os.Stderr, "  wintunctl uninstall [-name \"Wintun Gsou\"]\n")
	fmt.Fprintf(os.Stderr, "\nOptions:\n")
	fmt.Fprintf(os.Stderr, "  -name string\n\tAdapter name to create/delete (default \"Wintun Gsou\")\n")
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	cmd := os.Args[1]
	name := flag.NewFlagSet(cmd, flag.ExitOnError)
	adapterName := name.String("name", "Wintun Gsou", "Adapter name")
	// Parse flags after subcommand
	if err := name.Parse(os.Args[2:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}

	switch cmd {
	case "install":
		if err := install(*adapterName); err != nil {
			fmt.Fprintln(os.Stderr, "install failed:", err)
			os.Exit(1)
		}
		fmt.Println("installed", *adapterName)
	case "uninstall":
		if err := uninstall(*adapterName); err != nil {
			fmt.Fprintln(os.Stderr, "uninstall failed:", err)
			os.Exit(1)
		}
		fmt.Println("uninstalled", *adapterName)
	default:
		usage()
		os.Exit(2)
	}
}

// A stable per-application tunnel type GUID (recommendation from Wintun docs).
var tunnelType = windows.GUID{0xC1E5F705, 0x85D2, 0x4D9F, [8]byte{0x9D, 0x2A, 0x7F, 0x3F, 0x5F, 0x4D, 0x8A, 0x1B}}

func install(adapterName string) error {
	// Try open existing first
	if _, err := wintun.OpenAdapter(adapterName); err == nil {
		return nil // already exists
	}
	_, err := wintun.CreateAdapter(adapterName, &tunnelType)
	return err
}

func uninstall(adapterName string) error {
	ad, err := wintun.OpenAdapter(adapterName)
	if err != nil {
		// not exists
		return nil
	}
	defer ad.Close()
	// Try removing up to a few times
	for i := 0; i < 3; i++ {
		if err := ad.Delete(true); err == nil {
			return nil
		}
	}
	return errors.New("failed to delete adapter, ensure no apps are using it and you have admin rights")
}
