package resources

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:log"
import "core:mem"
import "core:reflect"
import "core:strconv"
import "core:strings"

import "../utils"

// The configs as JSON files (client.config.json, server.config.json): each field of the
// struct is a key of its name, in the struct's order, a struct field an object of its
// own, a map's keys sorted. A colour is written "RRGGBB" (a Maybe colour "" for none), an
// enum by its name in lower case ("top_right") and an f32 as short as it reads back
// (0.4), as a person would write them; colours and enums are read without regard to
// case. A field tagged `json:"-"` is not part of the file.
//
// A key the file doesn't hold keeps the setting's default, a key the struct doesn't have
// is passed over, and a file that isn't JSON, or holds a value a setting can't take, is
// logged with where it went wrong and read as none: the defaults stand.

Config_Read :: enum {
	Read,
	Missing, // no file: the config holds its defaults
	Broken,  // a file, but not one to read: logged
}

// The file at `path` over `config`, its strings allocated with `allocator`. A file that
// is Broken may have been read in part: the caller sets the defaults again.
config_read :: proc(path: string, config: ^$T, allocator: mem.Allocator) -> Config_Read {
	if !utils.file_exists(path) do return .Missing
	text, read := utils.read_file(path, context.temp_allocator)
	if !read do return .Broken

	// Checked whole first: the unmarshaling says where a value is wrong, not where the
	// text isn't JSON, and with our own unmarshalers registered it doesn't check it.
	if err, at := not_json(text); err != nil {
		log.errorf("%s:%d:%d: not JSON (%v); the defaults are used, and the file is left as it is", path, at.line, at.column, err)
		return .Broken
	}

	switch err in json.unmarshal(text, config, .JSON, allocator) {
	case nil:
		return .Read
	case json.Unsupported_Type_Error:
		at := err.token.pos
		log.errorf("%s:%d:%d: %s isn't a value this setting takes, %s; the defaults are used, and the file is left as it is", path, at.line, at.column, err.token.text, wanted(err.id))
	case json.Error, json.Unmarshal_Data_Error:
		log.errorf("%s: %v; the defaults are used, and the file is left as it is", path, err)
	}
	return .Broken
}

// JSON that isn't a config's (a manifest, a web service's answer) into `value`, its
// strings and lists made with `allocator`. It is checked to be JSON first, as a config
// is: with the marshalers below registered, the unmarshaling doesn't check it. False if
// it isn't JSON, or isn't a `T`.
read_json :: proc(text: []byte, value: ^$T, allocator := context.allocator) -> bool {
	if err, _ := not_json(text); err != nil do return false
	return json.unmarshal(text, value, .JSON, allocator) == nil
}

// Where `text` stops being JSON, if it does.
@(private = "file")
not_json :: proc(text: []byte) -> (err: json.Error, at: json.Pos) {
	// All of it in the temp allocator, the context's too: on an error the parser frees
	// what it has made with the context's allocator rather than its own.
	context.allocator = context.temp_allocator
	parser := json.make_parser(text, .JSON, parse_integers = true)
	_, err = json.parse_value(&parser)
	if err == nil && parser.curr_token.kind != .EOF do err = .Unexpected_Token // something after the value
	return err, parser.curr_token.pos
}

// What a setting of type `id` takes, said for a person editing the file.
@(private = "file")
wanted :: proc(id: typeid) -> string {
	switch id {
	case utils.Rgba, Maybe(utils.Rgba):
		return `a colour, "RRGGBB"`
	}
	if names := reflect.enum_field_names(id); len(names) > 0 {
		return strings.to_lower(fmt.tprintf("one of %s", strings.join(names, ", ", context.temp_allocator)), context.temp_allocator)
	}
	return fmt.tprintf("a %v", id)
}

// `config` written to `path` whole, pretty-printed. False, with the reason logged, if it
// can't be written.
config_write :: proc(path: string, config: ^$T) -> bool {
	options := json.Marshal_Options {
		pretty           = true,
		use_spaces       = true,
		spaces           = 2,
		sort_maps_by_key = true,
	}
	b := strings.builder_make(context.temp_allocator)
	if err := json.marshal_to_builder(&b, config^, &options); err != nil {
		log.errorf("could not write %s: %v", path, err)
		return false
	}
	strings.write_byte(&b, '\n')
	return utils.write_file(path, b.buf[:])
}

// ---------------------------------------------------------------------------------
// The colours, the enums and the numbers, written as people write them. The JSON
// package takes its own marshalers by type, for the whole program; these are the only
// ones it has.

@(init, private = "file")
config_marshalers_init :: proc "contextless" () {
	context = runtime.default_context()
	json.set_user_marshalers(new(map[typeid]json.User_Marshaler))
	json.set_user_unmarshalers(new(map[typeid]json.User_Unmarshaler))

	register(utils.Rgba, marshal_color, unmarshal_color)
	register(Maybe(utils.Rgba), marshal_maybe_color, unmarshal_maybe_color)
	for id in ([?]typeid{Gostek, Hair_Style, Head_Style, Chain_Style, Weapon, Window_Mode, Typing_Style, Kill_Log_Position}) {
		register(id, marshal_enum, unmarshal_enum)
	}
	register(f32, marshal_f32) // read as the package reads it
	for id in ([?]typeid{[]string, []Admin_Entry, []Ban_Entry, []Mute_Entry}) {
		register(id, marshal_list) // read as the package reads it
	}
}

@(private = "file")
register :: proc(id: typeid, marshal: json.User_Marshaler, unmarshal: json.User_Unmarshaler = nil) {
	json.register_user_marshaler(id, marshal)
	if unmarshal != nil do json.register_user_unmarshaler(id, unmarshal)
}

// The shortest decimal that reads back as the same f32: 0.4, not 0.40000001.
@(private = "file")
marshal_f32 :: proc(w: io.Writer, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	buf: [32]byte
	number := strconv.write_float(buf[:], f64((^f32)(v.data)^), 'f', -1, 32)
	_, err := io.write_string(w, strings.trim_prefix(number, "+")) // it signs every number
	return err
}

// A list as the package writes one, but an empty one as [] rather than its brackets
// a line apart.
@(private = "file")
marshal_list :: proc(w: io.Writer, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	count := reflect.length(v)
	if count == 0 {
		_, err := io.write_string(w, "[]")
		return err
	}
	json.opt_write_start(w, opt, '[') or_return
	for i in 0 ..< count {
		json.opt_write_iteration(w, opt, i == 0) or_return
		json.marshal_to_writer(w, reflect.index(v, i), opt) or_return
	}
	return json.opt_write_end(w, opt, ']')
}

@(private = "file")
marshal_color :: proc(w: io.Writer, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	return json.marshal_to_writer(w, utils.format_hex_color((^utils.Rgba)(v.data)^), opt)
}

@(private = "file")
unmarshal_color :: proc(p: ^json.Parser, v: any) -> json.Unmarshal_Error {
	token := p.curr_token
	text := take_string(p, v) or_return
	color, ok := utils.parse_hex_color(text)
	if !ok do return json.Unsupported_Type_Error{v.id, token}
	(^utils.Rgba)(v.data)^ = color
	return nil
}

@(private = "file")
marshal_maybe_color :: proc(w: io.Writer, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	color, has_color := (^Maybe(utils.Rgba))(v.data)^.?
	return json.marshal_to_writer(w, utils.format_hex_color(color) if has_color else "", opt)
}

// "RRGGBB", or "" (or null) for none.
@(private = "file")
unmarshal_maybe_color :: proc(p: ^json.Parser, v: any) -> json.Unmarshal_Error {
	maybe := (^Maybe(utils.Rgba))(v.data)
	token := p.curr_token
	if token.kind == .Null {
		json.advance_token(p)
		maybe^ = nil
		return nil
	}
	text := take_string(p, v) or_return
	if text == "" {
		maybe^ = nil
		return nil
	}
	color, ok := utils.parse_hex_color(text)
	if !ok do return json.Unsupported_Type_Error{v.id, token}
	maybe^ = color
	return nil
}

@(private = "file")
marshal_enum :: proc(w: io.Writer, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	name, _ := reflect.enum_name_from_value_any(v)
	return json.marshal_to_writer(w, strings.to_lower(name, context.temp_allocator), opt)
}

@(private = "file")
unmarshal_enum :: proc(p: ^json.Parser, v: any) -> json.Unmarshal_Error {
	token := p.curr_token
	name := take_string(p, v) or_return
	info := reflect.type_info_base(type_info_of(v.id)).variant.(reflect.Type_Info_Enum)
	for enum_name, i in info.names {
		if !strings.equal_fold(enum_name, name) do continue
		value := info.values[i]
		switch reflect.size_of_typeid(v.id) {
		case 1: (^u8)(v.data)^ = u8(value)
		case 2: (^u16)(v.data)^ = u16(value)
		case 4: (^u32)(v.data)^ = u32(value)
		case 8: (^u64)(v.data)^ = u64(value)
		}
		return nil
	}
	return json.Unsupported_Type_Error{v.id, token}
}

// The string the parser is at, unquoted into the temp allocator, and the parser past it.
@(private = "file")
take_string :: proc(p: ^json.Parser, v: any) -> (text: string, err: json.Unmarshal_Error) {
	token := p.curr_token
	if token.kind != .String do return "", json.Unsupported_Type_Error{v.id, token}
	json.advance_token(p)
	unquoted, unquote_err := json.unquote_string(token, p.spec, context.temp_allocator)
	if unquote_err != nil do return "", unquote_err
	return unquoted, nil
}
