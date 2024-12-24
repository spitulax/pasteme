package pasteme

import "core:fmt"
import "core:os"
import "core:strings"


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

