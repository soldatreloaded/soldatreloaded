package hud

import res "../../../core/resources"

// What the game says in a match, in the words of the text part worn (res.Strings: the
// chosen mod's strings.json over Classic's): worn with the mod (texts_wear), and said by
// key with `text`, which fills its placeholders.

@(private = "file")
worn_texts: res.Strings

// The lines of the text part `mod` wears, from now on.
texts_wear :: proc(mod: res.Mod) {
	res.strings_destroy(&worn_texts)
	worn_texts = res.strings_load(mod)
}

texts_forget :: proc() {
	res.strings_destroy(&worn_texts)
}

// The line `id` as the text part worn says it, its placeholders filled with `args`: with
// the temp allocator.
text :: proc(id: res.String_Id, args: ..any) -> string {
	return res.strings_text(&worn_texts, id, ..args)
}
