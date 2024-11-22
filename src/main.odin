package pasteme

// TODO: Support for other than Linux
// TODO: Search UI like fzf

import "base:runtime"
import "core:c/libc"
import "core:encoding/ansi"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
_ :: mem

PROG_NAME :: #config(PROG_NAME, "")
PROG_VERSION :: #config(PROG_VERSION, "")

OS_Set :: bit_set[runtime.Odin_OS_Type]
UNIX_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD}

start :: proc() -> (ok: bool) {
    userdata_dirname: string
    defer delete(userdata_dirname)
    when ODIN_OS in UNIX_OS {
        config_home := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
        if config_home == "" {
            home := os.get_env("HOME", context.temp_allocator)
            assert(home != "")
            config_home = filepath.join({home, ".config"})
        }
        userdata_dirname = filepath.join({config_home, "pasteme"})
    } else when ODIN_OS == .Windows {
        appdata := os.get_env("APPDATA", context.temp_allocator)
        assert(appdata != "")
        userdata_dirname = filepath.join({appdata, "pasteme"})
    } else {
        #panic("Unsupported operating system: " + ODIN_OS)
    }

    if !os.exists(userdata_dirname) {
        if err := os.make_directory(userdata_dirname); err != nil {
            fmt.eprintfln("Unable to create directory in `%s`: %v", userdata_dirname, err)
            return false
        }
    } else {
        if !os.is_dir(userdata_dirname) {
            fmt.eprintfln("`%s` already exists but it's not a directory", userdata_dirname)
            return false
        }
    }

    files := read_userdata_dir(userdata_dirname) or_return
    defer delete_file_infos(files)
    dirs_contents := list_dir(files, true) or_return
    defer {
        for x in dirs_contents.? {
            delete_file_infos(x)
        }
        delete(dirs_contents.?)
    }
    copy_chosen(ask(files, dirs_contents.?) or_return) or_return

    return true
}

read_userdata_dir :: proc(userdata_dirname: string) -> (files: []os.File_Info, ok: bool) {
    userdata_dir, userdata_dir_err := os.open(userdata_dirname)
    if userdata_dir_err != nil {
        fmt.eprintfln("Failed to open `%s`: %v", userdata_dirname, userdata_dir_err)
        ok = false
        return
    }
    defer assert(os.close(userdata_dir) == nil)

    files_err: os.Error
    files, files_err = os.read_dir(userdata_dir, 0)
    if files_err != nil {
        fmt.eprintfln("Failed to read `%s`: %v", userdata_dirname, files_err)
        ok = false
        return
    }
    defer if !ok {
        delete_file_infos(files)
    }

    for &file in files {
        if strings.has_prefix(file.name, ".") {
            delete(file.fullpath)
            file = {}
        }
    }

    ok = true
    return
}

delete_file_infos :: proc(files: []os.File_Info, alloc := context.allocator) {
    for x in files {
        delete(x.fullpath, alloc)
    }
    delete(files, alloc)
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
        list_dir(dir_contents.?) or_return
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
    pwd := os.get_current_directory()
    defer delete(pwd)

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

