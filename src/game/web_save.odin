#+build js
package game

// Download and upload of the browser save, on the Extras page. The files
// are the same ones desktop writes (prefs.user_data_write); IndexedDB is
// the copy that survives a reload (D89).

import "core:os"
import "core:strings"

import "dr:prefs"

@(default_calling_convention = "c")
foreign {
	dr_download            :: proc(ptr: rawptr, n: i32, name: cstring) ---
	dr_upload_open         :: proc() ---
	dr_upload_len          :: proc() -> i32 ---
	dr_upload_copy         :: proc(dst: rawptr, cap: i32) -> i32 ---
	dr_unlink              :: proc(path: cstring) -> i32 ---
	dr_list_dir            :: proc(path: cstring, buf: rawptr, buflen: i32) -> i32 ---
	dr_persist_sync_reload :: proc() ---
	dr_persist_failed      :: proc() -> i32 ---
}

SAVE_DOWNLOAD_NAME :: "deimos-rose-save.drsave"

@(private)
save_note_set :: proc(text: string) {
	n := min(len(text), len(shared.web.save_note))
	copy(shared.web.save_note[:n], text[:n])
	shared.web.save_note_len = n
}

save_note :: proc() -> string {
	return string(shared.web.save_note[:shared.web.save_note_len])
}

@(private)
save_dir_names :: proc(allocator := context.temp_allocator) -> []string {
	cstr, cerr := strings.clone_to_cstring(prefs.USER_DATA_DIR_WEB, allocator)
	if cerr != nil {
		return nil
	}
	room := 1 << 12
	for room <= 1 << 16 {
		buf := make([]byte, room, allocator)
		n := dr_list_dir(cstr, raw_data(buf), i32(len(buf)))
		if n == -2 {
			room *= 2
			continue
		}
		if n <= 0 {
			return nil
		}
		names := make([dynamic]string, 0, allocator)
		off := 0
		for off < int(n) {
			start := off
			for off < int(n) && buf[off] != 0 {
				off += 1
			}
			if off > start {
				append(&names, strings.clone(string(buf[start:off]), allocator))
			}
			off += 1
		}
		return names[:]
	}
	return nil
}

@(private)
save_collect :: proc(allocator := context.temp_allocator) -> []Save_File {
	names := save_dir_names(allocator)
	files := make([dynamic]Save_File, 0, allocator)
	for name in names {
		if !save_name_ok(name) {
			continue
		}
		path := prefs.user_data_path(name, allocator)
		data, err := os.read_entire_file(path, allocator)
		if err != nil {
			continue
		}
		append(&files, Save_File{name = name, data = data})
	}
	return files[:]
}

save_download :: proc() {
	files := save_collect()
	if len(files) == 0 {
		save_note_set("THERE IS NO SAVE TO DOWNLOAD")
		return
	}
	bytes := save_bundle_pack(files, context.temp_allocator)
	name, nerr := strings.clone_to_cstring(SAVE_DOWNLOAD_NAME, context.temp_allocator)
	if nerr != nil || len(bytes) == 0 {
		save_note_set("THE SAVE COULD NOT BE READ")
		return
	}
	dr_download(raw_data(bytes), i32(len(bytes)), name)
	save_note_set("SAVE FILE DOWNLOADED")
	shared.web.save_reload = false
}

// A file the page has finished reading. Nothing happens until one arrives.
save_take_upload :: proc() {
	n := dr_upload_len()
	if n < 0 {
		return
	}
	if n > 1 << 20 {
		_ = dr_upload_copy(nil, 0)
		save_note_set("THAT FILE IS TOO LARGE")
		return
	}
	buf := make([]byte, int(n), context.temp_allocator)
	got := dr_upload_copy(raw_data(buf), i32(len(buf)))
	if got < 0 {
		save_note_set("THAT FILE COULD NOT BE READ")
		return
	}
	files, ok := save_bundle_unpack(buf[:int(got)], context.temp_allocator)
	if !ok {
		save_note_set("THAT FILE IS NOT A SAVE FILE")
		return
	}
	if !save_replace(files[:]) {
		save_note_set("THE SAVE COULD NOT BE STORED")
		return
	}
	save_note_set("SAVE RESTORED")
	shared.web.save_reload = true
	dr_persist_sync_reload()
}

// Writes every file in the bundle, then removes save files it does not
// name. Names are checked before anything is written.
@(private)
save_replace :: proc(files: []Save_File) -> bool {
	for f in files {
		if !save_name_ok(f.name) {
			return false
		}
	}
	for f in files {
		path := prefs.user_data_path(f.name, context.temp_allocator)
		if os.write_entire_file(path, f.data) != nil {
			return false
		}
	}
	for name in save_dir_names() {
		if !save_name_ok(name) {
			continue
		}
		keep := false
		for f in files {
			if f.name == name {
				keep = true
				break
			}
		}
		if keep {
			continue
		}
		path := prefs.user_data_path(name, context.temp_allocator)
		cstr, cerr := strings.clone_to_cstring(path, context.temp_allocator)
		if cerr == nil {
			_ = dr_unlink(cstr)
		}
	}
	return true
}

// The reload after a good upload happens from the page, once IndexedDB
// has the new files. A failed sync leaves the player on this screen.
save_reload_watch :: proc() {
	if shared.web.save_reload && dr_persist_failed() != 0 {
		shared.web.save_reload = false
		save_note_set("THE SAVE COULD NOT BE STORED")
	}
}
