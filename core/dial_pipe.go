//go:build windows && !cgo

package main

import (
	"io"
	"net"
	"strings"

	"github.com/Microsoft/go-winio"
)

func dial(address string) (io.ReadWriteCloser, error) {
	// If it looks like a TCP address (host:port), use TCP
	if strings.Contains(address, ":") {
		return net.Dial("tcp", address)
	}
	// Otherwise treat as a named pipe path
	return winio.DialPipe(address, nil)
}
