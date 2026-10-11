#+build !windows
package resources

// Steam's place is found by its folders alone elsewhere than Windows.
steam_registry :: proc() -> []string {
	return nil
}
