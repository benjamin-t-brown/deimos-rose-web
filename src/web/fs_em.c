/* File and directory helpers for the web build. Emscripten's libc talks to
   the preloaded MEMFS, which core:os on js does not. Linked by build_web.sh. */
#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

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
