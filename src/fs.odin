package pasteme

import "base:runtime"
import "core:encoding/ansi"
import "core:fmt"
import "core:os"
import "core:strings"
import sp "deps:subprocess.odin"


list_git :: proc(
    dirpath: string,
    alloc := context.allocator,
) -> (
    files: []os.File_Info,
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)

    old_dir := os.get_current_directory(context.temp_allocator)
    chdir(dirpath) or_return

    git, git_err := sp.command_make("git")
    if git_err == sp.General_Error.Program_Not_Found {
        fmt.eprintfln("`git` is not found")
        return
    } else if git_err != nil {
        sp.unwrap(git_err) or_return
    }
    defer sp.command_destroy(&git)

    git.opts.output = .Capture
    sp.command_append(&git, "ls-tree", "--name-only", "--full-tree", "HEAD")
    result := sp.unwrap(sp.command_run(git), "Could not run `git`") or_return
    defer sp.result_destroy(&result)
    if !sp.result_success(result) {
        fmt.eprintln("`git` exited with:", result.exit)
        return
    }

    file_names := strings.split_lines(trim_nl(string(result.stdout)), context.temp_allocator)
    files = make([]os.File_Info, len(file_names), alloc)
    defer if !ok {
        os.file_info_slice_delete(files, alloc)
        delete(files, alloc)
    }
    for x, i in file_names {
        if x == ".gitignore" {
            continue
        }
        err: os.Error
        files[i], err = os.stat(x, alloc)
        if err != nil {
            fmt.eprintfln("Failed to stat `%s`: %v", x, err)
            return
        }
    }

    chdir(old_dir) or_return

    return files, true
}

list_dir :: proc(
    dirpath: string,
    hidden: bool = false,
    alloc := context.allocator,
) -> (
    files: []os.File_Info,
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)

    dir, dir_err := os.open(dirpath)
    if dir_err != nil {
        fmt.eprintfln("Failed to open `%s`: %v", dirpath, dir_err)
        return
    }
    defer fmt.assertf(os.close(dir) == nil, "Could not close `%s`", dirpath)

    files_all, files_err := os.read_dir(dir, 0, alloc)
    if files_err != nil {
        fmt.eprintfln("Failed to read `%s`: %v", dirpath, files_err)
        return
    }
    defer os.file_info_slice_delete(files_all, alloc)

    files_buf := make([dynamic]os.File_Info, 0, len(files_all), alloc)
    defer if !ok {
        delete(files_buf)
    }
    for file in files_all {
        if !hidden && strings.has_prefix(file.name, ".") {
            continue
        }
        append(&files_buf, file_info_clone(file, alloc))
    }

    return files_buf[:], true
}

// Allocates if `return_contents`
// The job of reading each directory is handled here to prevent reading directories twice
list_dirs :: proc(
    files: []os.File_Info,
    return_contents: bool = false,
    alloc := context.allocator,
) -> (
    dirs_contents: Maybe([][]os.File_Info),
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)

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
                os.file_info_slice_delete(contents, alloc)
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

