package tests

import "core:bytes"
import "core:testing"

import "dr:game"

@(private = "file")
free_save_files :: proc(files: [dynamic]game.Save_File) {
	for f in files {
		delete(f.name)
		delete(f.data)
	}
	delete(files)
}

@(test)
save_bundle_round_trips_the_games_files :: proc(t: ^testing.T) {
	// A newline and a zero byte in the payload, so the length is what
	// frames the file, not a line ending.
	blob := []byte{'h', 'i', '\n', 0, 'x'}
	files := []game.Save_File{
		{name = "preferences", data = transmute([]byte)string("classic=1\nmusic_volume=99\n")},
		{name = "progress", data = transmute([]byte)string("4")},
		{name = "progress-easy_mode", data = transmute([]byte)string("2")},
		{name = "highscores", data = blob},
		{name = "empty.dat", data = []byte{}},
	}
	packed := game.save_bundle_pack(files)
	defer delete(packed)
	testing.expect(t, len(packed) > 0, "a bundle is never empty")

	got, ok := game.save_bundle_unpack(packed)
	testing.expect(t, ok, "a bundle this package wrote must read back")
	defer free_save_files(got)
	testing.expect_value(t, len(got), len(files))
	if len(got) != len(files) {
		return
	}
	for f, i in files {
		testing.expect_value(t, got[i].name, f.name)
		testing.expect(t, bytes.equal(got[i].data, f.data), "payload")
	}
}

@(test)
save_bundle_accepts_an_empty_list :: proc(t: ^testing.T) {
	packed := game.save_bundle_pack(nil)
	defer delete(packed)
	got, ok := game.save_bundle_unpack(packed)
	testing.expect(t, ok, "zero files is a save with nothing in it")
	defer free_save_files(got)
	testing.expect_value(t, len(got), 0)
}

@(test)
save_bundle_refuses_a_bad_file :: proc(t: ^testing.T) {
	// Each of these must come back as not a bundle, and must not leak
	// the allocations a partial parse made (the test allocator checks).
	cases := []string{
		"",
		"nope\n",
		"deimos-rose-save 1\n",
		"deimos-rose-save 1\n1\n",
		"deimos-rose-save 1\n-1\n",
		"deimos-rose-save 1\n65\n",
		"deimos-rose-save 1\n1\n.\n0\n",
		"deimos-rose-save 1\n1\n..\n0\n",
		"deimos-rose-save 1\n1\n../x\n0\n",
		"deimos-rose-save 1\n1\na/b\n0\n",
		"deimos-rose-save 1\n1\nprog ress\n0\n",
		"deimos-rose-save 1\n1\nprogress\n2\nhiEXTRA",
		"deimos-rose-save 1\n1\nprogress\n1\n4\n",
		"deimos-rose-save 1\n0\n\n",
		"deimos-rose-save 2\n0\n",
	}
	for c in cases {
		got, ok := game.save_bundle_unpack(transmute([]byte)c)
		testing.expectf(t, !ok, "accepted %q", c)
		if ok {
			free_save_files(got)
		}
	}
}
