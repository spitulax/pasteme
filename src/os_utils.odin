package pasteme

import "core:fmt"
import "core:os"
import "core:strings"
import sp "deps:subprocess.odin"


chdir :: proc(path: string) -> (ok: bool) {
    if err := os.set_current_directory(path); err != nil {
        fmt.eprintfln("Could not change directory to `%s`: %v", path, err)
        return
    }
    return true
}

open :: proc(
    path: string,
    flags: int = os.O_RDONLY,
    mode: int = 0o000,
) -> (
    fd: os.Handle,
    ok: bool,
) {
    err: os.Error
    fd, err = os.open(path)
    if err != nil {
        fmt.eprintfln("Failed to open `%s`: %v", path, err)
        return
    }
    return fd, true
}

close :: proc(fd: ^os.Handle) -> (ok: bool) {
    if err := os.close(fd^); err != nil {
        path := os.absolute_path_from_handle(fd^) or_else "<handle>"
        fmt.eprintfln("Failed to close `%s`: %v", path, err)
        return
    }
    fd^ = {}
    return true
}

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

mkdir_if_not_exist :: proc(path: string) -> (ok: bool) {
    if !os.exists(path) {
        if err := os.make_directory(path); err != nil {
            fmt.eprintfln("Unable to create directory in `%s`: %v", path, err)
            return false
        }
    } else {
        if !os.is_dir(path) {
            fmt.eprintfln("`%s` already exists but it's not a directory", path)
            return false
        }
    }
    return true
}

copy_file :: proc(path: string, target_path: string) -> (ok: bool) {
    mkdir_if_not_exist(target_path) or_return

    cmd_sb := strings.builder_make()
    defer strings.builder_destroy(&cmd_sb)

    when ODIN_OS in UNIX_OS {
        fmt.sbprint(&cmd_sb, "cp", "-P", path, target_path)
    } else when ODIN_OS == .Windows {
        // TODO: Implement for Windows
        unimplemented()
    }

    result := sp.unwrap(
        sp.run_shell(strings.to_string(cmd_sb), {output = .Capture}),
        "Failed to run copy command",
    ) or_return
    defer sp.result_destroy(&result)
    if !sp.result_success(result) {
        fmt.eprintfln(
            "Failed to copy `%s` into `%s`: %s",
            path,
            target_path,
            string(result.stderr),
        )
        return false
    }

    return true
}

