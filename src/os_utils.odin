package pasteme

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import fp "core:path/filepath"
import "core:strings"
import "core:sys/posix"


@(require_results)
chdir :: proc(path: string, loc := #caller_location) -> (ok: bool) {
    if err := os.set_current_directory(path); err != nil {
        eprintf("Could not change directory to `%s`: %v", path, err, loc = loc)
        return
    }
    return true
}

@(require_results)
open :: proc(
    path: string,
    flags: int = os.O_RDONLY,
    mode: int = 0o000,
    loc := #caller_location,
) -> (
    fd: os.Handle,
    ok: bool,
) {
    err: os.Error
    fd, err = os.open(path, flags, mode)
    if err != nil {
        eprintf("Failed to open `%s`: %v", path, err, loc = loc)
        return
    }
    return fd, true
}

close :: proc(fd: ^os.Handle) {
    if fd^ == {} {return}
    if err := os.close(fd^); err != nil {
        fmt.assertf(false, "Failed to close `%s`: %v", path_from_handle(fd^), err)
    }
    fd^ = {}
}

@(require_results)
read :: proc(fd: os.Handle, buf: []byte, loc := #caller_location) -> (n: int, ok: bool) {
    err: os.Error
    n, err = os.read(fd, buf)
    if err != nil {
        eprintf("Failed to read from `%s`: %v", path_from_handle(fd), err, loc = loc)
        return
    }
    return n, true
}

@(require_results)
write :: proc(fd: os.Handle, data: []byte, loc := #caller_location) -> (ok: bool) {
    n, err := os.write(fd, data)
    if err != nil {
        eprintf("Failed to write to `%s`: %v", path_from_handle(fd), err, loc = loc)
        return
    } else if len(data) != n {
        eprintf("Failed to write to `%s`: Corrupted write", path_from_handle(fd), loc = loc)
        return
    }
    return true
}

@(require_results)
path_from_handle :: proc(fd: os.Handle) -> string {
    return os.absolute_path_from_handle(fd) or_else "<handle>"
}

@(require_results)
file_info_clone :: proc(self: os.File_Info, alloc := context.allocator) -> os.File_Info {
    res := self
    res.fullpath = strings.clone(self.fullpath, alloc)
    return res
}

file_info_delete_slices_many :: proc(selves_many: [][]os.File_Info, alloc := context.allocator) {
    for x in selves_many {
        os.file_info_slice_delete(x, alloc)
    }
    delete(selves_many, alloc)
}

@(require_results)
mkdir_if_not_exist :: proc(path: string, loc := #caller_location) -> (ok: bool) {
    if !os.exists(path) {
        if err := os.make_directory(path); err != nil {
            eprintf("Unable to create directory in `%s`: %v", path, err, loc = loc)
            return false
        }
    } else {
        if !os.is_dir(path) {
            eprintf("`%s` already exists but it's not a directory", path, loc = loc)
            return false
        }
    }
    return true
}

@(require_results)
stat :: proc(
    name: string,
    follow_link: bool = false,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    fi: os.File_Info,
    ok: bool,
) {
    err: os.Error
    if follow_link {
        fi, err = os.stat(name, alloc)
    } else {
        fi, err = os.lstat(name, alloc)
    }
    if err != nil {
        eprintf("Failed to stat `%s`: %v", name, err, loc = loc)
        return
    }
    return fi, true
}

@(require_results)
copy_file :: proc(path: string, target_path: string, loc := #caller_location) -> (ok: bool) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    mkdir_if_not_exist(target_path, loc) or_return

    unix_mode: int
    unix_is_link: bool
    when ODIN_OS in UNIX_OS {
        s: posix.stat_t
        if posix.lstat(strings.clone_to_cstring(path, context.temp_allocator), &s) == .FAIL {
            eprintf("[UNIX] Failed to stat `%s`: %v", path, posix.errno(), loc = loc)
            return
        }
        unix_mode = int(transmute(posix._mode_t)s.st_mode)
        unix_is_link = posix.S_ISLNK(s.st_mode)
    }

    target_filepath := fp.join({target_path, fp.base(path)}, context.temp_allocator)
    if g_prog.verbose {
        fmt.printfln("Copying `%s` to `%s`", path, target_filepath)
    }

    if unix_is_link {
        link_target := make([]byte, posix.PATH_MAX, context.temp_allocator)
        n := posix.readlink(
            strings.clone_to_cstring(path, context.temp_allocator),
            raw_data(link_target),
            len(link_target) - 1,
        )
        if n < 0 {
            eprintf("[UNIX] Failed to read link `%s`: %v", path, posix.errno(), loc = loc)
            return
        }
        link_target[n] = '\x00'

        posix.symlink(
            cstring(raw_data(link_target)),
            strings.clone_to_cstring(target_filepath, context.temp_allocator),
        )
    } else {
        source_file := open(path, os.O_RDONLY, loc = loc) or_return
        defer close(&source_file)
        target_file := open(
            target_filepath,
            os.O_CREATE | os.O_WRONLY | os.O_TRUNC,
            unix_mode,
            loc,
        ) or_return
        defer close(&target_file)
        for {
            buf: [1 * mem.Kilobyte]byte
            n := read(source_file, buf[:], loc) or_return
            if n <= 0 {
                break
            }
            write(target_file, buf[:n], loc) or_return
        }
    }

    return true
}

