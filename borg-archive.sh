#! /usr/bin/env bash
# borg-archive.sh
#   A wrapper that allows Borg Backup to be used to create single-file
#   compressed archives.  Basic functions are supported creating, mount/extract,
#   and update of the archive.  Primary use-case is sharing and archiving
#   versioned datasets for research and similar purposes.
#
# MIT License
#
# Copyright 2025 Jason L. Causey
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

borg_archive=$(basename "$0")
function usage() {
    cat <<EOF

Usage:
    $borg_archive create archive_file.baz  /path/to/archive-root-dir [encryption] [borg-options]
        Initializes and creates initial archive.
        encryption: Turns on encryption of the archive.
        borg-options: Fine-tune underlying Borg Backup parameters.

    $borg_archive extract archive_file.baz  /path/to/destination [tag]
        Extracts the archive to 'destination'. 'destination' will be created 
            if it does not exist. If it exists, current contents will 
            be OVERWRITTEN!
        tag: Name of a commit tag to extract (default is most recent).

    $borg_archive list archive_file.baz
        Lists all available commits in this archive.

    $borg_archive mount archive_file.baz  /path/to/mount-dir [tag]
        Mounts read-only to 'mount-dir'. mount-dir will be created if it 
            does not exist.
        tag: Name of a commit tag to extract (default is most recent).

    $borg_archive umount /path/to/mount-dir
        Unmount an archive that was mounted with 'mount'.

    $borg_archive update archive_file.baz  /path/to/archive-root-dir [tag]
        Update the archive with any changes in 'archive-root-dir'.
        tag: Used to name the commit, if omitted the tag is generated
            automatically as an incrementing counter.

EOF
}

function create_tarfile {
    [[ -z $1 ]] && {
        echo "TARPATH name not provided."
        exit 97
    }
    [[ -z $2 ]] && {
        echo "WORKDIR name not provided."
        exit 97
    }
    cd "${2}/.."
    # Try to use zstd if it is available; fall back to pigz then gzip otherwise.
    if command -v zstd >/dev/null 2>&1; then
        tar -cv "$(basename "${2}")" | zstd -9 >"${1}"
    elif command -v pigz >/dev/null 2>&1; then
        tar -cv "$(basename "${2}")" | pigz -9 >"${1}"
    else
        tar -cv "$(basename "${2}")" | gzip -9 >"${1}"
    fi
}

function extract_tarfile {
    [[ -z $1 ]] && {
        echo "TARFILE name not provided."
        exit 98
    }
    [[ -z $2 ]] && {
        echo "WORKDIR name not provided."
        exit 98
    }
    tar -xf "${1}" -C "${2}" --strip-components=1
}

trap '{ [[ "$ACTION" != "mount" ]] && rm -rf -- "$WORKDIR" 2> /dev/null; }' EXIT
set -e
WORKDIR="$(mktemp -d)"
ACTION="$1"

case $ACTION in
create | extract | list | mount | update)
    shift
    ;; # OK
umount | unmount)
    ACTION='umount'
    shift
    ;; # OK, and standardize 'umount'
--help | -h | help)
    usage
    exit 0
    ;; # OK, show help then exit
*)
    SAW=''
    if [ -n "${ACTION}" ]; then
        SAW="  Saw '${ACTION}'."
    fi
    echo "First argument must be create, extract, help, list, mount, or update.${SAW}"
    usage
    exit 1
    ;;
esac

if [ -z "$1" ]; then
    if [[ $ACTION != "umount" ]]; then
        echo "Archive file name is required."
        usage
        exit 1
    fi
fi

ARCHFILE="${1}"
shift

# Perform the requested action
case $ACTION in
create) # CREATE NEW ARCHIVE
    if [ -z "$1" ]; then
        echo "Path to root of archive directory must be given."
        exit 2
    fi
    SOURCEDIR="$1"
    shift

    # Set the encryption mode, which is the only REQUIRED option for Borg.
    ENCR_MODE="none"
    if [ "$1" == "encryption" ] || [ "$1" == "-e" ] || [ "$1" == "--encryption" ]; then
        if [ "$1" == "encryption" ]; then
            ENCR_MODE="repofile"
            shift
        else
            ENCR_MODE="$2"
            shift
            shift
        fi
    fi

    # We are initializing a tag list here. We always use "1" as the initial commit tag.
    TAG=1
    echo "${TAG}" >"${SOURCEDIR}/.ba-tags"

    borg init --encryption "${ENCR_MODE}" "$@" "${WORKDIR}"
    OLDDIR="$(pwd)"
    cd "${SOURCEDIR}/.."
    borg create --progress "${WORKDIR}::${TAG}" "$(basename "${SOURCEDIR}")"
    create_tarfile "${OLDDIR}/${ARCHFILE}" "${WORKDIR}"
    cd "${OLDDIR}"
    ;;

extract) # EXTRACT most recent or specified [TAG] to specified directory
    OUTPUTDIR="${1}"
    shift
    [[ -d "${OUTPUTDIR}" ]] && {
        read -p "${OUTPUTDIR} already exists.  Contents will be overwritten."$'\n'"Are you sure? [y|N]  " -n 1 -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Stopping."
            exit 0
        fi
        echo
    }
    mkdir -p "${OUTPUTDIR}" || {
        echo "Cannot create output directory '${OUTPUTDIR}'."
        exit 3
    }
    extract_tarfile "${ARCHFILE}" "${WORKDIR}"
    OLDDIR="$(pwd)"
    cd "${OUTPUTDIR}"

    TAG="${1}"
    if [ -z "${TAG}" ]; then
        TAG=$(BORG_RELOCATED_REPO_ACCESS_IS_OK="yes" borg list "${WORKDIR}" --short --last 1 2>/dev/null) # default to latest
    fi

    BORG_RELOCATED_REPO_ACCESS_IS_OK="yes" borg extract --progress --error "${WORKDIR}::${TAG}" 2>/dev/null
    cd "${OLDDIR}"

    echo "Extracted archive contents to '${OUTPUTDIR}'."
    ;;

list) # LIST the commit tags associated with this archive.
    extract_tarfile "${ARCHFILE}" "${WORKDIR}"
    BORG_RELOCATED_REPO_ACCESS_IS_OK="yes" borg list --format="{archive:<36} {time}{NL}" "${WORKDIR}" 2>/dev/null
    ;;

mount) # MOUNT most recent or specified [TAG] to specified directory (read-only)
    if [ -z "$1" ]; then
        echo "Must provide path to directory to mount."
        usage
        exit 4
    fi
    MOUNTDIR="${1}"
    shift
    [[ -d ${MOUNTDIR} ]] || mkdir "${MOUNTDIR}"
    [[ -d ${MOUNTDIR} ]] || {
        echo "Cannot create mount directory '${MOUNTDIR}'."
        exit 4
    }

    # Save the path to the temp dir in the mount directory so we can clean up on unmount
    echo "${WORKDIR}" >"${MOUNTDIR}/.borg-repo"
    extract_tarfile "${ARCHFILE}" "${WORKDIR}"

    TAG="${1}"
    if [ -z "${TAG}" ]; then
        TAG=$(BORG_RELOCATED_REPO_ACCESS_IS_OK="yes" borg list "${WORKDIR}" --short --last 1 2>/dev/null) # default to latest
    fi
    BORG_RELOCATED_REPO_ACCESS_IS_OK="yes" borg mount --error "${WORKDIR}::${TAG}" "${MOUNTDIR}" 2>"${WORKDIR}/.ba-error" ||
        {
            echo "Failed to mount:"
            echo "   $(cat "${WORKDIR}/.ba-error")"
            exit 4
        }
    echo "Mounted archive to '${MOUNTDIR}' (read-only)."
    ;;

umount)
    # This is the only case where we don't have a real ARCHFILE.
    # That variable holds the mount point here.
    if [ -z "$ARCHFILE" ]; then
        echo "Must provide path to mounted archive to unmount."
        usage
        exit 5
    fi
    # The steps here must happen in the right order to clean everything up.
    rm -rf "${WORKDIR}"                     # delete current WORKDIR; we don't need it.
    MOUNTDIR="${ARCHFILE}"                  # pull into correct variable for code clarity
    borg umount "${MOUNTDIR}"               # unmount the borg repo
    WORKDIR=$(cat "${MOUNTDIR}/.borg-repo") # .borg-repo becomes visible after unmount, get the temp dir name
    rm "${MOUNTDIR}/.borg-repo"             # clean up the metadata file
    echo "Unmounted archive."
    ;;

update)
    if [ -z "$1" ]; then
        echo "Path to root of archive directory must be given."
        exit 6
    fi
    SOURCEDIR="$1"
    shift
    if [ -z "$1" ]; then
        NTAGS=$(wc -l <"${SOURCEDIR}/.ba-tags")
        TAG=$((NTAGS + 1))
    else
        TAG="$1"
    fi
    echo "${TAG}" >>"${SOURCEDIR}/.ba-tags"

    # Extract existing archive to the WORKDIR:
    extract_tarfile "${ARCHFILE}" "${WORKDIR}"
    # The following steps match the "create" routine, except that we are careful
    # not to overwrite the previous archive until creating the new one succeeds.
    OLDDIR="$(pwd)"
    cd "${SOURCEDIR}/.."
    BORG_RELOCATED_REPO_ACCESS_IS_OK="yes" borg create "${WORKDIR}::${TAG}" "$(basename "${SOURCEDIR}")" 2>/dev/null
    cd "${WORKDIR}/.."
    # shellcheck disable=SC2015
    create_tarfile "${OLDDIR}/.${ARCHFILE}.working" "${WORKDIR}" &&
        mv "${OLDDIR}/.${ARCHFILE}.working" "${OLDDIR}/${ARCHFILE}" ||
        {
            echo "Failed to update archive."
            cd "${OLDDIR}"
            exit 6
        }
    cd "${OLDDIR}"
    echo "Archive updated successfully."
    ;;

*)
    echo "Unknown action."
    exit 99
    ;;

esac
