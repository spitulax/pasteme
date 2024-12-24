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

