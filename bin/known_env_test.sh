#!/bin/bash
# LICENSE sha256: c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4
#
# Tests the known resource environment detection in runner.sh.tpl.
#
# The functions are read out of the template rather than kept in a second
# file, so there is one copy of them and the thing under test is the thing
# that ships. The template is not sourceable as a whole, because it still has
# its @@SUBSTITUTION@@ placeholders, so only the marked block is extracted.

set -o errexit -o nounset -o pipefail

readonly _tpl="${1}"
_lib="$(mktemp)"
readonly _lib
sed -n '/^# --- begin known resource environment ---$/,/^# --- end known resource environment ---$/p' \
  "${_tpl}" > "${_lib}"

if [[ ! -s "${_lib}" ]]; then
  echo "FAIL: could not extract the known environment block from ${_tpl}"
  exit 1
fi
# shellcheck disable=SC1090
source "${_lib}"

_failures=0

# fail MESSAGE
fail() {
  echo "FAIL: $*"
  _failures=$((_failures + 1))
}

# expect_eq NAME GOT WANT
expect_eq() {
  if [[ "$2" != "$3" ]]; then
    fail "$1: got '$2', wanted '$3'"
  fi
}

# Builds a rootfs skeleton from the directories named as arguments.
make_rootfs() {
  local _dir
  _dir="$(mktemp -d)"
  local _sub
  for _sub in "$@"; do
    mkdir -p "${_dir}/${_sub}"
  done
  echo "${_dir}"
}

echo "== ghostscript, versioned directory =="
(
  _failures=0
  _r="$(make_rootfs \
    usr/share/ghostscript/10.02.1/Resource/Init \
    usr/share/ghostscript/10.02.1/lib \
    usr/share/ghostscript/10.02.1/Resource/Font \
    usr/share/ghostscript/fonts)"
  _rootfs_apply_known_env "${_r}"
  expect_eq "GS_LIB" "${GS_LIB:-}" \
    "${_r}/usr/share/ghostscript/10.02.1/Resource/Init:${_r}/usr/share/ghostscript/10.02.1/lib:${_r}/usr/share/ghostscript/10.02.1/Resource/Font:${_r}/usr/share/ghostscript/fonts"
  exit "${_failures}"
) || _failures=$((_failures + 1))

echo "== ghostscript, a different version, which is the point of globbing =="
(
  _failures=0
  _r="$(make_rootfs usr/share/ghostscript/9.55.0/lib)"
  _rootfs_apply_known_env "${_r}"
  expect_eq "GS_LIB" "${GS_LIB:-}" "${_r}/usr/share/ghostscript/9.55.0/lib"
  exit "${_failures}"
) || _failures=$((_failures + 1))

echo "== imagemagick, versioned in two places =="
(
  _failures=0
  _r="$(make_rootfs \
    etc/ImageMagick-6 \
    usr/lib/x86_64-linux-gnu/ImageMagick-6.9.12/modules-Q16/coders \
    usr/lib/x86_64-linux-gnu/ImageMagick-6.9.12/modules-Q16/filters)"
  _rootfs_apply_known_env "${_r}"
  expect_eq "MAGICK_CONFIGURE_PATH" "${MAGICK_CONFIGURE_PATH:-}" "${_r}/etc/ImageMagick-6"
  expect_eq "MAGICK_CODER_MODULE_PATH" "${MAGICK_CODER_MODULE_PATH:-}" \
    "${_r}/usr/lib/x86_64-linux-gnu/ImageMagick-6.9.12/modules-Q16/coders"
  expect_eq "MAGICK_FILTER_MODULE_PATH" "${MAGICK_FILTER_MODULE_PATH:-}" \
    "${_r}/usr/lib/x86_64-linux-gnu/ImageMagick-6.9.12/modules-Q16/filters"
  exit "${_failures}"
) || _failures=$((_failures + 1))

echo "== asymptote, including the ghostscript it shells out to =="
(
  _failures=0
  _r="$(make_rootfs usr/share/asymptote usr/bin)"
  touch "${_r}/usr/bin/gs"
  chmod +x "${_r}/usr/bin/gs"
  _rootfs_apply_known_env "${_r}"
  expect_eq "ASYMPTOTE_DIR" "${ASYMPTOTE_DIR:-}" "${_r}/usr/share/asymptote"
  expect_eq "ASYMPTOTE_GS" "${ASYMPTOTE_GS:-}" "${_r}/usr/bin/gs"
  exit "${_failures}"
) || _failures=$((_failures + 1))

echo "== calibre =="
(
  _failures=0
  _r="$(make_rootfs \
    usr/lib/calibre/calibre/plugins \
    usr/share/calibre \
    usr/lib/python3/dist-packages)"
  _rootfs_apply_known_env "${_r}"
  expect_eq "CALIBRE_PYTHON_PATH" "${CALIBRE_PYTHON_PATH:-}" "${_r}/usr/lib/calibre"
  expect_eq "CALIBRE_EXTENSIONS_PATH" "${CALIBRE_EXTENSIONS_PATH:-}" \
    "${_r}/usr/lib/calibre/calibre/plugins"
  expect_eq "CALIBRE_RESOURCES_PATH" "${CALIBRE_RESOURCES_PATH:-}" "${_r}/usr/share/calibre"
  expect_eq "PYTHONPATH" "${PYTHONPATH:-}" \
    "${_r}/usr/lib/calibre:${_r}/usr/lib/python3/dist-packages"
  exit "${_failures}"
) || _failures=$((_failures + 1))

echo "== PYTHONPATH is not set for a rootfs that merely has dist-packages =="
(
  _failures=0
  _r="$(make_rootfs usr/lib/python3/dist-packages)"
  _rootfs_apply_known_env "${_r}"
  expect_eq "PYTHONPATH" "${PYTHONPATH:-}" ""
  exit "${_failures}"
) || _failures=$((_failures + 1))

echo "== a rootfs with none of these packages gets nothing set =="
(
  _failures=0
  _r="$(make_rootfs usr/bin bin usr/lib/x86_64-linux-gnu)"
  _rootfs_apply_known_env "${_r}"
  for _v in GS_LIB MAGICK_CONFIGURE_PATH MAGICK_CODER_MODULE_PATH \
            MAGICK_FILTER_MODULE_PATH ASYMPTOTE_DIR ASYMPTOTE_GS \
            CALIBRE_PYTHON_PATH PYTHONPATH FONTCONFIG_PATH; do
    expect_eq "${_v}" "$(eval "echo \${${_v}:-}")" ""
  done
  exit "${_failures}"
) || _failures=$((_failures + 1))

echo "== a value the caller already set is left alone =="
(
  _failures=0
  _r="$(make_rootfs usr/share/ghostscript/10.02.1/lib)"
  export GS_LIB="/somewhere/the/caller/chose"
  _rootfs_apply_known_env "${_r}"
  expect_eq "GS_LIB" "${GS_LIB}" "/somewhere/the/caller/chose"
  exit "${_failures}"
) || _failures=$((_failures + 1))

echo "== a directory that does not exist is left out of the list =="
(
  _failures=0
  # Only Init and fonts exist, so lib and Resource/Font must not appear.
  _r="$(make_rootfs \
    usr/share/ghostscript/10.02.1/Resource/Init \
    usr/share/ghostscript/fonts)"
  _rootfs_apply_known_env "${_r}"
  expect_eq "GS_LIB" "${GS_LIB:-}" \
    "${_r}/usr/share/ghostscript/10.02.1/Resource/Init:${_r}/usr/share/ghostscript/fonts"
  exit "${_failures}"
) || _failures=$((_failures + 1))

if [[ "${_failures}" -ne 0 ]]; then
  echo "${_failures} test(s) failed"
  exit 1
fi
echo "all known environment tests passed"
