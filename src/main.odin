package pasteme

// TODO: Search UI like fzf
// TODO: Handle ^C and ^D
// TODO: Custom userdata path

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import sp "deps:subprocess.odin"
_ :: mem
_ :: fmt


PROG_NAME :: #config(PROG_NAME, "")
PROG_VERSION :: #config(PROG_VERSION, "")


OS_Set :: bit_set[runtime.Odin_OS_Type]
UNIX_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD}


g_userdata_path: string
g_userdata_is_git: bool
g_git: sp.Command


start :: proc() -> (ok: bool) {
    git_err: sp.Error
    g_git, git_err = sp.command_make("git")
    if git_err == sp.General_Error.Program_Not_Found {
        fmt.eprintfln("`git` is not found. Some features will be unavailabe")
    } else if git_err != nil {
        sp.unwrap(git_err) or_return
    }
    g_git.opts.output = .Capture
    defer sp.command_destroy(&g_git)

    setup_userdata() or_return
    defer delete(g_userdata_path)

    files := read_userdata_dir() or_return
    defer os.file_info_slice_delete(files)
    dirs_contents := list_dirs(files, true) or_return
    defer file_info_delete_slices_many(dirs_contents.?)
    copy_chosen(ask(files, dirs_contents.?) or_return) or_return

    return true
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

