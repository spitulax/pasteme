package pasteme

// TODO: Search UI like fzf
// TODO: Handle ^C and ^D

import "base:runtime"
import "core:c/libc"
import "core:encoding/ansi"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
_ :: mem


PROG_NAME :: #config(PROG_NAME, "")
PROG_VERSION :: #config(PROG_VERSION, "")


OS_Set :: bit_set[runtime.Odin_OS_Type]
UNIX_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD}


start :: proc() -> (ok: bool) {
    userdata_path: string
    defer delete(userdata_path)
    when ODIN_OS in UNIX_OS {
        config_home := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
        if config_home == "" {
            home := os.get_env("HOME", context.temp_allocator)
            assert(home != "", "$HOME is not defined")
            config_home = filepath.join({home, ".config"})
        }
        userdata_path = filepath.join({config_home, "pasteme"})
    } else when ODIN_OS == .Windows {
        appdata := os.get_env("APPDATA", context.temp_allocator)
        assert(appdata != "", "%APPDATA% is not defined")
        userdata_path = filepath.join({appdata, "pasteme"})
    } else {
        #panic("Unsupported operating system: " + ODIN_OS)
    }

    if !os.exists(userdata_path) {
        if err := os.make_directory(userdata_path); err != nil {
            fmt.eprintfln("Unable to create directory in `%s`: %v", userdata_path, err)
            return false
        }
    } else {
        if !os.is_dir(userdata_path) {
            fmt.eprintfln("`%s` already exists but it's not a directory", userdata_path)
            return false
        }
    }

    files := read_userdata_dir(userdata_path) or_return
    defer os.file_info_slice_delete(files)
    dirs_contents := list_dirs(files, true) or_return
    defer file_info_delete_slices_many(dirs_contents.?)
    copy_chosen(ask(files, dirs_contents.?) or_return) or_return

    return true
}

read_userdata_dir :: proc(
    userdata_path: string,
    alloc := context.allocator,
) -> (
    files: []os.File_Info,
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)

    if os.exists(".git") {
        files = list_git(userdata_path, alloc) or_return
    } else {
        files = list_dir(userdata_path, false, alloc) or_return
    }
    defer if !ok {
        os.file_info_slice_delete(files)
    }

    ok = true
    return
}

ask :: proc(
    files: []os.File_Info,
    dirs_contents: [][]os.File_Info,
) -> (
    fullpath: string,
    is_dir: bool,
    dir_contents: Maybe([]os.File_Info),
    ok: bool,
) {
    ansi_graphic(ansi.BOLD, ansi.FG_CYAN)
    fmt.print("Choose file or directory to copy: ")
    ansi_reset()

    input := scan() or_return
    defer delete(input)
    choice, choice_ok := strconv.parse_int(input)
    if !choice_ok || choice == 0 || choice > len(files) {
        fmt.eprintfln("`%s` is invalid", input)
        ok = false
        return
    }

    choice_zero_index := choice - 1 // this is funny
    chosen_file := files[choice_zero_index]

    if chosen_file.is_dir {
        dir_contents = dirs_contents[choice_zero_index]
        is_dir = true

        ansi_graphic(ansi.BOLD, ansi.FG_CYAN)
        fmt.println("Directory contents: ")
        ansi_reset()
        list_dirs(dir_contents.?) or_return
    }

    fullpath = chosen_file.fullpath
    ok = true
    return
}

copy_chosen :: proc(
    fullpath: string,
    is_dir: bool,
    dir_contents: Maybe([]os.File_Info) = nil,
) -> (
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    pwd := os.get_current_directory(context.temp_allocator)

    cmd: cstring
    copy_inside: bool

    if is_dir {
        ansi_graphic(ansi.BOLD, ansi.FG_RED)
        fmt.printf(
            "Do you want to copy the contents inside (%d files) [y/N]? ",
            len(dir_contents.?),
        )
        ansi_reset()

        input := scan() or_return
        defer delete(input)
        switch input {
        case "y", "Y":
            copy_inside = true
        case:
            copy_inside = false
        }

        when ODIN_OS == .Windows {
            target_path := filepath.join({pwd, filepath.base(fullpath)})
        }

        if copy_inside {
            when ODIN_OS in UNIX_OS {
                cmd = fmt.ctprintf("cp -r %[0]s/* %[0]s/.* %[1]s", fullpath, pwd)
            } else when ODIN_OS == .Windows {
                cmd = fmt.ctprintf("xcopy %s %s /s /e /y /q", fullpath, pwd)
            }
        } else {
            when ODIN_OS in UNIX_OS {
                cmd = fmt.ctprintf("cp -r %s %s", fullpath, pwd)
            } else when ODIN_OS == .Windows {
                cmd = fmt.ctprint("xcopy %s %s /s /e /y /q /i", fullpath, target_path)
            }
        }
    } else {
        when ODIN_OS in UNIX_OS {
            cmd = fmt.ctprintf("cp %s %s", fullpath, pwd)
        } else when ODIN_OS == .Windows {
            cmd = fmt.ctprint("copy /y %s %s", fullpath, pwd)
        }
    }

    if libc.system(cmd) != 0 {
        fmt.eprintfln("Failed to copy `%s` into `%s`", fullpath, pwd)
        return false
    }
    ansi_graphic(ansi.BOLD, ansi.FG_BLUE)
    fmt.printfln("Successfully copied `%s` into `%s`", fullpath, pwd)
    ansi_reset()
    if copy_inside {
        for x in dir_contents.? {
            rel_path, rel_path_err := filepath.rel(fullpath, x.fullpath, context.temp_allocator)
            if rel_path_err != nil {
                fmt.eprintfln(
                    "Failed to compute relative path of `%s` from `%s`",
                    x.fullpath,
                    fullpath,
                )
                return false
            }
            fmt.printfln("Copied `%v%s`", rel_path, ("/" if is_dir else ""))
        }
    }

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

