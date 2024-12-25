package pasteme

import "base:runtime"
import "core:encoding/ansi"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"


when ODIN_OS == .Windows {
    NL :: "\r\n"
} else {
    NL :: "\n"
}


ansi_reset :: proc() {
    fmt.print(ansi.CSI + ansi.RESET + ansi.SGR)
}

ansi_graphic :: proc(options: ..string) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    fmt.print(
        ansi.CSI,
        concat_string_sep(options, ";", context.temp_allocator),
        ansi.SGR,
        sep = "",
    )
}

@(require_results)
scan :: proc(alloc := context.allocator, loc := #caller_location) -> (input: string, ok: bool) {
    buf: [1024]byte
    read_n, read_err := os.read(os.stdin, buf[:])
    if read_err != nil {
        eprintf("Failed to read user input: %v", read_err, loc = loc)
        ok = false
        return
    }
    return strings.clone(string(buf[:read_n]), alloc), true
}

@(require_results)
concat_string_sep :: proc(strs: []string, sep: string, alloc := context.allocator) -> string {
    sb: strings.Builder
    strings.builder_init(&sb, alloc)
    for str, i in strs {
        if i > 0 {
            fmt.sbprint(&sb, sep)
        }
        fmt.sbprint(&sb, str)
    }
    return strings.to_string(sb)
}

// metric = multiple of 1000 instead of 1024
@(require_results)
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

@(require_results)
trim_nl :: proc(s: string) -> string {
    return strings.trim_suffix(s, NL)
}

delete_strings :: proc(strs: []string, alloc := context.allocator) {
    for str in strs {
        delete(str, alloc)
    }
    delete(strs, alloc)
}

_eprint :: proc(str: string, loc: runtime.Source_Code_Location) {
    fmt.eprintfln("%v:%v:%v(): %s", loc.file_path, loc.line, loc.procedure, str)
}

eprint :: proc(args: ..any, sep: string = " ", loc := #caller_location) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    _eprint(fmt.tprint(..args, sep = sep), loc)
}

eprintf :: proc(f: string, args: ..any, loc := #caller_location) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    _eprint(fmt.tprintf(f, ..args), loc)
}

