# LICENSE sha256: c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4

"""Public API for running binaries out of a Bazel-provided rootfs.

`//bin:run` and the `sh_binary_and_test` macro next to it are tied to this
repository's own `//image:rootfs`, which carries one fixed package list. A
consumer that needs a different set of programs cannot use them without
pulling in every package this repository happens to install.

`rootfs_binary` takes the rootfs as an attribute instead, so a consumer can
build a rootfs from its own apt manifest and wrap binaries out of it. The
rootfs location is substituted into the generated script at build time rather
than passed as an argument, so the result works both under `bazel run` and as
a `tools` input to another rule's action, where arguments are not applied.
"""

def _rootfs_binary_impl(ctx):
    rootfs = ctx.file.rootfs
    script = ctx.actions.declare_file("{}_runner.sh".format(ctx.label.name))

    # rlocation wants `<workspace>/<short path>`; under an action there is no
    # runfiles tree, so the exec path is used as a fallback.
    rlocation = "{}/{}".format(ctx.workspace_name, rootfs.short_path)

    ctx.actions.expand_template(
        template = ctx.file._template,
        output = script,
        is_executable = True,
        substitutions = {
            "@@ROOTFS_RLOCATION@@": rlocation,
            "@@ROOTFS_EXECPATH@@": rootfs.path,
            "@@BINARY_PATH@@": ctx.attr.binary_path,
        },
    )

    runfiles = ctx.runfiles(files = [rootfs, script])
    runfiles = runfiles.merge(ctx.attr._runfiles_lib[DefaultInfo].default_runfiles)

    return [DefaultInfo(
        executable = script,
        files = depset([script]),
        runfiles = runfiles,
    )]

rootfs_binary = rule(
    implementation = _rootfs_binary_impl,
    executable = True,
    doc = "Wraps one binary from a rootfs directory as an executable target.",
    attrs = {
        "rootfs": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "A directory produced by the `rootfs` rule in //image:rules.bzl.",
        ),
        "binary_path": attr.string(
            mandatory = True,
            doc = "Absolute path of the binary inside the rootfs, " +
                  "for example \"/usr/bin/drawtiming\".",
        ),
        "_template": attr.label(
            allow_single_file = True,
            default = "//bin:runner.sh.tpl",
        ),
        "_runfiles_lib": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
)
