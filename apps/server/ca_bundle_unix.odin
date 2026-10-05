#+build !windows
#+build !darwin
package server

import "core:os"

// The distribution's certificates for curl, which is built on mbedTLS here and knows
// none of its own, as the lobby's requests find them (lobby/): nil if none is
// found, and curl is left to its own.
@(private)
ca_bundle :: proc() -> cstring {
	bundles := [?]cstring {
		"/etc/ssl/certs/ca-certificates.crt",
		"/etc/pki/tls/certs/ca-bundle.crt",
		"/etc/ssl/ca-bundle.pem",
		"/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
		"/etc/ssl/cert.pem",
		"/etc/pki/tls/cacert.pem",
	}
	for bundle in bundles do if os.exists(string(bundle)) do return bundle
	return nil
}
