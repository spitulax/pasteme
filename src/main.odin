package pasteme

// TODO: Search UI like fzf
// TODO: Custom userdata path
// TODO: Copy into temp dir first

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
_ :: mem
_ :: fmt


PROG_NAME :: #config(PROG_NAME, "")
PROG_VERSION :: #config(PROG_VERSION, "")


OS_Set :: bit_set[runtime.Odin_OS_Type]
UNIX_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD}


g_prog: Prog


start :: proc() -> (ok: bool) {
    if terminate, args_ok := parse_args(); !args_ok {
        usage()
        return
    } else if terminate {
        return true
    }

    prog_init()
    defer prog_destroy()

    files := read_vault() or_return
    defer os.file_info_slice_delete(files)
    dirs_contents := list_dirs(files, true) or_return
    defer file_info_delete_slices_many(dirs_contents.?)
    copy_chosen(ask(files, dirs_contents.?) or_return) or_return

    return true
}

parse_args :: proc() -> (terminate: bool, ok: bool) {
    next_args :: proc(args: ^[]string) -> (arg: string, ok: bool) {
        if len(args) <= 0 {
            ok = false
            return
        }
        arg = args[0]
        args^ = args[1:]
        ok = true
        return
    }

    args := os.args
    _ = next_args(&args) or_return

    for i := 0; len(args) > 0; i += 1 {
        arg := next_args(&args) or_return

        if i == 0 {
            switch arg {
            case "--help":
                usage()
                terminate = true
                ok = true
                return
            case "--version":
                fmt.printfln("%s version %s", PROG_NAME, PROG_VERSION)
                terminate = true
                ok = true
                return
            }
        }

        switch arg {
        case "--no-git":
            g_prog.no_git = true
        case "--vault":
            path := next_args(&args) or_return
            g_prog.vault_path = path
        }
    }

    ok = true
    return
}

usage :: proc() {
    fmt.printf(
        `Usage:
%s [options...]

Options:
    --no-git            Ignore Git.
    --vault <PATH>      Custom vault.
`,
        PROG_NAME,
    )
}

main :: proc() {
    ok: bool
    defer os.exit(!ok)
    defer free_all(context.temp_allocator)
    when ODIN_DEBUG {
        mem_track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&mem_track, context.allocator)
        context.allocator = mem.tracking_allocator(&mem_track)
        defer {
            fmt.print("\033[1;31m")
            if len(mem_track.allocation_map) > 0 {
                fmt.eprintfln("### %v unfreed allocations ###", len(mem_track.allocation_map))
                for _, v in mem_track.allocation_map {
                    fmt.eprintfln(" -> %v bytes from %v", v.size, v.location)
                }
            }
            if len(mem_track.bad_free_array) > 0 {
                fmt.eprintfln("### %v bad frees ###", len(mem_track.bad_free_array))
                for x in mem_track.bad_free_array {
                    fmt.eprintfln(" -> %p from %v", x.memory, x.location)
                }
            }
            fmt.print("\033[0m")
            mem.tracking_allocator_destroy(&mem_track)
        }
    }

    ok = start()
}

