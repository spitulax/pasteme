package pasteme

import "base:runtime"
import "core:encoding/ansi"
import "core:fmt"
import "core:os"
import path "core:path/filepath"
import "core:strconv"
import "core:strings"


setup_userdata :: proc(alloc := context.allocator) -> (ok: bool) {
    when ODIN_OS in UNIX_OS {
        config_home := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
        if config_home == "" {
            home := os.get_env("HOME", context.temp_allocator)
            assert(home != "", "$HOME is not defined")
            config_home = path.join({home, ".config"}, context.temp_allocator)
        }
        g_userdata_path = path.join({config_home, "pasteme"}, alloc)
    } else when ODIN_OS == .Windows {
        appdata := os.get_env("APPDATA", context.temp_allocator)
        assert(appdata != "", "%APPDATA% is not defined")
        g_userdata_path = path.join({appdata, "pasteme"}, alloc)
    } else {
        #panic("Unsupported operating system: " + ODIN_OS)
    }
    defer if !ok {
        delete(g_userdata_path)
    }

    mkdir_if_not_exist(g_userdata_path) or_return

    g_userdata_is_git = is_git_dir(g_userdata_path) or_return

    return true
}

read_userdata_dir :: proc(alloc := context.allocator) -> (files: []os.File_Info, ok: bool) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)

    if g_userdata_is_git {
        files = list_git(g_userdata_path, alloc) or_return
    } else {
        files = list_dir(g_userdata_path, false, alloc) or_return
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
    dir_contents: Maybe([]os.File_Info),
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    choice: int
    for {
        ansi_graphic(ansi.BOLD, ansi.FG_CYAN)
        fmt.print("Choose file or directory to copy: ")
        ansi_reset()

        input := scan(context.temp_allocator) or_return
        if !strings.ends_with(input, NL) {
            fmt.println()
        }
        if len(input) == 0 {
            continue
        }

        choice_ok: bool
        choice, choice_ok = strconv.parse_int(trim_nl(input))
        if !choice_ok || choice == 0 || choice > len(files) {
            fmt.eprintfln("`%s` is invalid", trim_nl(input))
            continue
        }
        break
    }

    choice_zero_index := choice - 1 // this is funny
    chosen_file := files[choice_zero_index]

    if chosen_file.is_dir {
        dir_contents = dirs_contents[choice_zero_index]
    }
    fullpath = chosen_file.fullpath
    ok = true
    return
}

copy_chosen :: proc(fullpath: string, dir_contents: Maybe([]os.File_Info) = nil) -> (ok: bool) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    pwd := os.get_current_directory(context.temp_allocator)
    is_dir := dir_contents != nil
    copy_inside: bool

    if is_dir {
        ansi_graphic(ansi.BOLD, ansi.FG_CYAN)
        fmt.println("Directory contents: ")
        ansi_reset()
        list_dirs(dir_contents.?) or_return

        ansi_graphic(ansi.BOLD, ansi.FG_RED)
        fmt.printf(
            "Do you want to copy the contents inside (%d files) [y/N]? ",
            len(dir_contents.?),
        )
        ansi_reset()

        input := trim_nl(scan(context.temp_allocator) or_return)
        switch input {
        case "y", "Y":
            copy_inside = true
        case:
            copy_inside = false
        }
    } else {
        copy_inside = true
    }

    out_path :=
        pwd if copy_inside else path.join({pwd, path.base(fullpath)}, context.temp_allocator)

    if is_dir {
        copy_dir_rec(fullpath, out_path) or_return
    } else {
        copy_file(fullpath, out_path) or_return
    }

    ansi_graphic(ansi.BOLD, ansi.FG_BLUE)
    fmt.printfln("Successfully copied `%s` into `%s`", fullpath, pwd)
    ansi_reset()
    if is_dir && copy_inside {
        for x in dir_contents.? {
            rel_path, rel_path_err := path.rel(fullpath, x.fullpath, context.temp_allocator)
            if rel_path_err != nil {
                fmt.eprintfln(
                    "Failed to compute relative path of `%s` from `%s`",
                    x.fullpath,
                    fullpath,
                )
                return false
            }
            fmt.printfln("Copied `%v%s`", rel_path, ("/" if x.is_dir else ""))
        }
    }

    return true
}

