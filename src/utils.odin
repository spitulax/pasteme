package pasteme

import "core:encoding/ansi"
import "core:fmt"
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

concat_string_sep :: proc(strs: []string, sep: string, allocator := context.allocator) -> string {
    sb: strings.Builder
    strings.builder_init(&sb)
    defer strings.builder_destroy(&sb)
    for str, i in strs {
        if i > 0 {
            fmt.sbprint(&sb, sep)
        }
        fmt.sbprint(&sb, str)
    }
    return strings.clone(strings.to_string(sb), allocator)
}

