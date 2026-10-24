/* File and directory helpers for the web build. Emscripten's libc talks to
   the preloaded MEMFS, which core:os on js does not. Linked by build_web.sh. */
#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <emscripten.h>

/* int64_t, not long: wasm32 long is 32 bits and the Odin side passes i64. */
void *dr_fopen(const char *path, const char *mode) { return fopen(path, mode); }
int dr_fclose(void *f) { return fclose(f); }
int64_t dr_fread(void *ptr, int64_t n, void *f) { return (int64_t)fread(ptr, 1, (size_t)n, f); }
int64_t dr_fwrite(const void *ptr, int64_t n, void *f) { return (int64_t)fwrite(ptr, 1, (size_t)n, f); }
int dr_fseek(void *f, int64_t off, int whence) { return fseek(f, (long)off, whence); }
int64_t dr_ftell(void *f) { return (int64_t)ftell(f); }
int dr_fflush(void *f) { return fflush(f); }

static int dr_stat(const char *path, struct stat *st) { return stat(path, st); }

int dr_exists(const char *path) {
	struct stat st;
	return dr_stat(path, &st) == 0;
}

int dr_is_dir(const char *path) {
	struct stat st;
	if (dr_stat(path, &st) != 0) return 0;
	return S_ISDIR(st.st_mode);
}

int64_t dr_file_size(const char *path) {
	struct stat st;
	if (dr_stat(path, &st) != 0) return -1;
	return (int64_t)st.st_size;
}

/* NUL-separated names, without "." and "..". Returns the bytes written,
   -1 if the directory cannot be opened, -2 if buf is too small. */
int dr_list_dir(const char *path, char *buf, int buflen) {
	DIR *d = opendir(path);
	if (!d) return -1;
	int used = 0;
	struct dirent *e;
	while ((e = readdir(d)) != NULL) {
		if (e->d_name[0] == '.' && (e->d_name[1] == 0 || (e->d_name[1] == '.' && e->d_name[2] == 0))) continue;
		int n = (int)strlen(e->d_name);
		if (used + n + 1 > buflen) {
			closedir(d);
			return -2;
		}
		memcpy(buf + used, e->d_name, (size_t)n);
		used += n;
		buf[used++] = 0;
	}
	closedir(d);
	return used;
}

/* Copies the /persist mount into IndexedDB. The page sets Module.drSync. */
void dr_persist_sync(void) {
	EM_ASM({ if (typeof Module.drSync === 'function') Module.drSync(false, null); });
}

void dr_persist_sync_reload(void) {
	EM_ASM({
		Module.drPersistFailed = 0;
		var finish = function(err) {
			Module.drPersistFailed = err ? 1 : 0;
			if (!err) location.reload();
		};
		if (typeof Module.drSync === 'function') Module.drSync(false, finish);
		else finish('no sync');
	});
}

int dr_persist_failed(void) {
	return EM_ASM_INT({ return Module.drPersistFailed ? 1 : 0; });
}

void dr_download(const void *ptr, int n, const char *filename) {
	EM_ASM({
		var n = $1;
		var bytes = new Uint8Array(n);
		var heap = Module['HEAPU8'];
		if (n > 0 && heap) bytes.set(heap.subarray($0, $0 + n));
		Module.drLastSave = bytes;
		var blob = new Blob([bytes], {type: 'application/octet-stream'});
		var a = document.createElement('a');
		a.href = URL.createObjectURL(blob);
		a.download = UTF8ToString($2);
		document.body.appendChild(a);
		a.click();
		a.remove();
		setTimeout(function() { URL.revokeObjectURL(a.href); }, 2000);
	}, ptr, n, filename);
}

void dr_upload_open(void) {
	EM_ASM({
		var input = document.getElementById('dr-upload');
		if (!input) {
			input = document.createElement('input');
			input.type = 'file';
			input.id = 'dr-upload';
			input.style.display = 'none';
			input.addEventListener('change', function() {
				var f = input.files && input.files[0];
				if (!f) return;
				var reader = new FileReader();
				reader.onload = function() { Module.drUpload = new Uint8Array(reader.result); };
				reader.readAsArrayBuffer(f);
			});
			document.body.appendChild(input);
		}
		input.click();
	});
}

int dr_upload_len(void) {
	return EM_ASM_INT({
		if (!Module.drUpload) return -1;
		return Module.drUpload.length;
	});
}

int dr_upload_copy(void *dst, int cap) {
	return EM_ASM_INT({
		var u = Module.drUpload;
		if (!u) return -1;
		var n = u.length;
		if (n > $1) {
			Module.drUpload = null;
			return -2;
		}
		var heap = Module['HEAPU8'];
		if (n > 0 && heap) heap.set(u.subarray(0, n), $0);
		Module.drUpload = null;
		return n;
	}, dst, cap);
}

int dr_unlink(const char *path) {
	return remove(path);
}
