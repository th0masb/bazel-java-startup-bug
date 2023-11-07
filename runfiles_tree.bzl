load("@bazel_skylib//lib:shell.bzl", "shell")
load("@rules_pkg//pkg:providers.bzl", "PackageFilegroupInfo", "PackageFilesInfo", "PackageSymlinkInfo")

def _targets_to_runfiles(ctx, targets):
    return ctx.runfiles(
        transitive_files = depset(transitive = [x[DefaultInfo].files for x in targets]),
    ).merge_all([x[DefaultInfo].default_runfiles for x in targets])

def _path_to_root(file_in_dir):
    """
    Examples:
    a => .
    a/b => ..
    a/b/c => ../..
    a/b/c/d => ../../..
    . => .
    ./a => .
    a//b => ..
    """
    split_dir = [x for x in file_in_dir.split("/") if x and x != "."][:-1]
    return "/".join([".." for x in split_dir]) if split_dir else "."

def _runfiles_tree_impl(ctx):
    name = ctx.attr.name
    all_runfiles = _targets_to_runfiles(ctx = ctx, targets = ctx.attr.binaries)
    map_paths_to_files = {}
    map_paths_to_symlink_content = {}
    empty_file = ctx.actions.declare_file(name + "_empty")
    ctx.actions.write(output = empty_file, content = "", is_executable = False)

    for empty_filename in all_runfiles.empty_filenames.to_list():
        map_paths_to_files[".runfiles/" + ctx.workspace_name + "/" + empty_filename] = empty_file

    for in_file in all_runfiles.files.to_list():
        map_paths_to_files[".runfiles/" + ctx.workspace_name + "/" + in_file.short_path] = in_file

    for root_symlink in all_runfiles.root_symlinks.to_list():
        map_paths_to_symlink_content[".runfiles/" + root_symlink.path] = \
            _path_to_root(root_symlink.path) + "/" + root_symlink.target_file.short_path

    for symlink in all_runfiles.symlinks.to_list():
        map_paths_to_symlink_content[".runfiles/" + ctx.workspace_name + "/" + symlink.path] = \
            _path_to_root(ctx.workspace_name + "/" + symlink.path) + symlink.target_file.short_path

    return [
        DefaultInfo(
            # This is what pkg_files does and seems to be required for pkg_tar
            # to see the actual files it needs to copy into the tar
            files = depset(map_paths_to_files.values()),
        ),
        # Consumed by pkg_tar.src via process_src
        PackageFilegroupInfo(
            pkg_dirs = [],
            pkg_symlinks = [
                (PackageSymlinkInfo(destination = src, target = dest), ctx.label)
                for src, dest in map_paths_to_symlink_content.items()
            ],
            pkg_files = [
                (PackageFilesInfo(dest_src_map = map_paths_to_files), ctx.label),
            ],
        ),
    ]

runfiles_tree = rule(
    _runfiles_tree_impl,
    attrs = {
        "binaries": attr.label_list(),
    },
)
