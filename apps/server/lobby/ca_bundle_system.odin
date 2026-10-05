#+build windows, darwin
package lobby

// Curl trusts what the system trusts here (Schannel, Secure Transport): no bundle of
// its own to find.
ca_bundle :: proc() -> cstring {
	return nil
}
