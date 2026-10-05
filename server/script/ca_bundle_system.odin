#+build windows, darwin
package script

// Curl trusts what the system trusts here (Schannel, Secure Transport): no bundle of
// its own to find.
@(private)
ca_bundle :: proc() -> cstring {
	return nil
}
