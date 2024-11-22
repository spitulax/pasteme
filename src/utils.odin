package pasteme

import "core:encoding/ansi"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

todo :: proc "contextless" (loc := #caller_location) {
    panic_contextless("Unimplemented", loc)
}

ansi_reset :: proc() {
    fmt.print(ansi.CSI + ansi.RESET + ansi.SGR)
}

ansi_graphic :: proc(options: ..string) {
    fmt.print(
        ansi.CSI,
        concat_string_sep(options, ";", context.temp_allocator),
        ansi.SGR,
        sep = "",
    )
}

scan :: proc(alloc := context.allocator) -> (input: string, ok: bool) {
    buf: [1024]byte
    read_n, read_err := os.read(os.stdin, buf[:])
    if read_err != nil {
        fmt.eprintfln("Failed to read user input: %v", read_err)
        ok = false
        return
    }
    return strings.clone(string(buf[:read_n - 1]), alloc), true // -1 because of newline
}

concat_string_sep :: proc(strs: []string, sep: string, alloc := context.allocator) -> string {
    sb: strings.Builder
    strings.builder_init(&sb)
    defer strings.builder_destroy(&sb)
    for str, i in strs {
        if i > 0 {
            fmt.sbprint(&sb, sep)
        }
        fmt.sbprint(&sb, str)
    }
    return strings.clone(strings.to_string(sb), alloc)
}

// metric = multiple of 1000 instead of 1024
human_readable_size :: proc(
    bytes: i64,
    metric: bool = false,
    alloc := context.allocator,
) -> string {
    MAX_UNIT :: 5
    units: [MAX_UNIT]string
    if metric {
        units = {"B", "kB", "MB", "GB", "TB"}
    } else {
        units = {"B", "KiB", "MiB", "GiB", "TiB"}
    }
    multiple := 1000 if metric else 1024
    order: int

    for i in 0 ..< MAX_UNIT {
        if f32(bytes) < math.pow(f32(multiple), f32(i + 1)) {
            order = i
            break
        }
    }

    return fmt.aprintf(
        "%.3v %v",
        f32(bytes) / f32(math.pow(f32(multiple), f32(order))),
        units[order],
        allocator = alloc,
    )
}


// allocates if `return_contents`
list_dir :: proc(
    files: []os.File_Info,
    return_contents: bool = false,
    alloc := context.allocator,
) -> (
    dirs_contents: Maybe([][]os.File_Info),
    ok: bool,
) {
    if return_contents {
        dirs_contents = make([][]os.File_Info, len(files), alloc)
    }

    for x, i in files {
        if x.name == "" {continue}

        ansi_graphic(ansi.FG_GREEN)
        fmt.printf("%d)", i + 1)
        ansi_reset()
        if x.is_dir {
            ansi_graphic(ansi.BOLD, ansi.FG_BLUE)
        }
        fmt.printf(" %s", x.fullpath)
        if x.is_dir {
            dir, dir_err := os.open(x.fullpath)
            if dir_err != nil {
                fmt.eprintfln("Failed to open `%s`: %v", x.fullpath, dir_err)
                ok = false
                return
            }
            defer assert(os.close(dir) == nil)

            contents, contents_err := os.read_dir(dir, 0, alloc)
            if contents_err != nil {
                fmt.eprintfln("Failed to read `%s`: %v", x.fullpath, contents_err)
                ok = false
                return
            }
            defer if !return_contents {
                delete_file_infos(contents, alloc)
            }
            if return_contents {
                dirs_contents.?[i] = contents
            }

            fmt.printf(" [%v]", len(contents))
        } else {
            fmt.printf(" [%v]", human_readable_size(x.size, alloc = context.temp_allocator))
        }
        fmt.print("\n")
        ansi_reset()
    }

    ok = true
    return
}

