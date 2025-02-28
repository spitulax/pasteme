package pasteme

import "base:runtime"
import "core:encoding/ansi"
import "core:fmt"
import "core:os"
import fp "core:path/filepath"
import "core:slice"
import "core:strings"
import sp "deps:subprocess.odin"


@(require_results)
is_git_dir :: proc(dirpath: string) -> (git: bool, ok: bool) {
    if !g_prog.git.prog.found {
        return false, true
    }

    old_dir := os.get_current_directory(context.temp_allocator)
    chdir(dirpath) or_return

    sp.command_clear(&g_prog.git)
    sp.command_append(&g_prog.git, "rev-parse")
    result := sp.unwrap(
        sp.command_run(g_prog.git, sp.Exec_Opts{output = .Silent}),
        "Could not run `git rev-parse`",
    ) or_return
    defer sp.result_destroy(&result)

    chdir(old_dir) or_return

    git = sp.result_success(result)
    ok = true
    return
}

@(require_results)
list_git :: proc(
    dirpath: string,
    alloc := context.allocator,
) -> (
    files: []os.File_Info,
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)

    old_dir := os.get_current_directory(context.temp_allocator)
    chdir(g_prog.vault_path) or_return

    sp.command_clear(&g_prog.git)
    sp.command_append(&g_prog.git, "write-tree", "--missing-ok")
    write_tree_res := sp.unwrap(
        sp.command_run(g_prog.git),
        "Could not run `git write-tree`",
    ) or_return
    defer sp.result_destroy(&write_tree_res)
    if !sp.result_success(write_tree_res) {
        eprint("`git write-tree` exited with:", write_tree_res.exit)
        return
    }
    write_tree := trim_nl(string(write_tree_res.stdout))

    sp.command_clear(&g_prog.git)
    sp.command_append(
        &g_prog.git,
        "ls-tree",
        "--name-only",
        "--full-tree",
        write_tree,
        fmt.tprintf("%s%s", dirpath, fp.SEPARATOR_STRING),
    )
    result := sp.unwrap(sp.command_run(g_prog.git), "Could not run `git ls-tree`") or_return
    defer sp.result_destroy(&result)
    if !sp.result_success(result) {
        eprint("`git ls-tree` exited with:", result.exit)
        return
    }

    file_names := strings.split_lines(trim_nl(string(result.stdout)), context.temp_allocator)
    files_buf := make([dynamic]os.File_Info, 0, len(file_names), alloc)
    defer if !ok {
        os.file_info_slice_delete(files, alloc)
    }
    for x in file_names {
        if x == ".gitignore" {
            continue
        }
        append(&files_buf, stat(x, false, alloc) or_return)
    }

    chdir(old_dir) or_return

    slice.sort_by(files_buf[:], proc(i, j: os.File_Info) -> bool {
        if i.is_dir && !j.is_dir {
            return false
        } else if !i.is_dir && j.is_dir {
            return true
        } else {
            return i.name < j.name
        }
    })

    return files_buf[:], true
}

@(require_results)
list_dir :: proc(
    dirpath: string,
    hidden: bool = false,
    alloc := context.allocator,
) -> (
    files: []os.File_Info,
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)

    dir := open(dirpath) or_return
    defer close(&dir)

    files_all, files_err := os.read_dir(dir, 0, alloc)
    if files_err != nil {
        eprintf("Failed to read `%s`: %v", dirpath, files_err)
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

    slice.sort_by(files_buf[:], proc(i, j: os.File_Info) -> bool {
        if i.is_dir && !j.is_dir {
            return false
        } else if !i.is_dir && j.is_dir {
            return true
        } else {
            return i.name < j.name
        }
    })

    return files_buf[:], true
}

// Allocates if `return_contents`
// The job of reading each directory is handled here to prevent reading directories twice
@(require_results)
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
    defer if return_contents && !ok {
        delete(dirs_contents.?, alloc)
    }

    for x, i in files {
        ansi_graphic(ansi.FG_GREEN)
        fmt.printf("%d)", i + 1)
        ansi_reset()
        if x.is_dir {
            ansi_graphic(ansi.BOLD, ansi.FG_BLUE)
        }
        fmt.printf(" %s", x.fullpath)
        if x.is_dir {
            contents: []os.File_Info
            if g_prog.vault_is_git {
                contents = list_git(x.fullpath, alloc) or_return
            } else {
                contents = list_dir(x.fullpath, true, alloc) or_return
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

// If `g_userdata_is_git`, `hidden` doesn't matter
@(require_results)
copy_dir_rec :: proc(dirpath: string, target_path: string, hidden: bool = true) -> (ok: bool) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    mkdir_if_not_exist(target_path) or_return

    process :: proc(
        paths: []string,
        dirpath: string,
        target_path: string,
        hidden: bool,
    ) -> (
        ok: bool,
    ) {
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        files: []os.File_Info
        if g_prog.vault_is_git {
            files = list_git(dirpath) or_return
        } else {
            files = list_dir(dirpath, hidden) or_return
        }
        defer os.file_info_slice_delete(files)
        for x in files {
            if x.is_dir {
                next_paths := make([]string, len(paths) + 1)
                defer delete(next_paths)
                copy(next_paths, paths)
                next_paths[len(next_paths) - 1] = fp.base(x.fullpath)
                process(next_paths, x.fullpath, target_path, hidden) or_return
            } else {
                copy_file(
                    x.fullpath,
                    fp.join(
                        {target_path, fp.join(paths, context.temp_allocator)},
                        context.temp_allocator,
                    ),
                ) or_return
            }
        }
        return true
    }

    process({}, dirpath, target_path, hidden) or_return

    return true
}

