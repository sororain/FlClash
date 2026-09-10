//go:build windows && !(android && cgo)

package main

import (
	"net"
	"strings"

	"github.com/Microsoft/go-winio"
)

func dial(address string) (net.Conn, error) {
	// The Flutter host binds a TCP listener and passes "host:port" on Windows;
	// a colon therefore selects TCP, anything else is a named pipe path.
	if strings.Contains(address, ":") {
		return net.Dial("tcp", address)
	}
	return winio.DialPipe(address, nil)
}
