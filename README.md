# borg-archive.sh

A wrapper that allows [Borg Backup](https://www.borgbackup.org/) to be used to create single-file compressed archives.

Basic functions are supported creating, mount/extract, and update of the archive.

The primary use-case is sharing and archiving versioned datasets for research and similar purposes.

I've been using the `.baz` extension for these archives, but you can do whatever you like. 😄

## Installation

### Requirements

You will need a working installation of [Borg Backup](https://www.borgbackup.org/), `tar`, and `zstd`.  This script is just a convenience wrapper around Borg and `tar`+`zstd`.  If you don't have `zstd` available, the tool will fall back to `gzip` (resulting in slower creation/extraction and larger archives).

If you want to be able to use the `mount` functionality, you will also need a working installation of FUSE (See https://en.wikipedia.org/wiki/Filesystem_in_Userspace).  If you are on a Mac, you might want [macFuse](https://macfuse.github.io/).

### Installing

The script `borg-archive.sh` contains all functional code.  It is a Bash script, so you will need to run it under a bash shell.  To install it for all users, you could copy it to e.g. `/usr/local/sbin/` and maybe symbolic link the shorter name `borg-archive`.  To install for your own user account, you might copy it to `~/.local/sbin/` or similar.

## Usage

* `borg_archive.sh create archive_file.baz  /path/to/archive-root-dir [encryption] [borg-options]`
  * Initializes and creates initial archive.
  * `encryption`: Turns on encryption of the archive.
  * `borg-options`: Fine-tune underlying Borg Backup parameters.

* `borg_archive.sh extract archive_file.baz  /path/to/destination [tag]`
  * Extracts the archive to 'destination'. 'destination' will be created
    if it does not exist. If it exists, current contents will be
    _OVERWRITTEN_!
  * `tag`: Name of a commit tag to extract (default is most recent).

* `borg_archive.sh help`  (or `--help` or `-h`)
    * Prints usage information.

* `borg_archive.sh list archive_file.baz`
        Lists all available commits in this archive.

* `borg_archive.sh mount archive_file.baz  /path/to/mount-dir [tag]`
  * Mounts read-only to 'mount-dir'. mount-dir will be created if it
        does not exist.
  * `tag`: Name of a commit tag to extract (default is most recent).

* `borg_archive.sh umount /path/to/mount-dir`
  * Unmount an archive that was mounted with 'mount'.

* `borg_archive.sh update archive_file.baz  /path/to/archive-root-dir [tag]`
  * Update the archive with any changes in 'archive-root-dir'.
  * tag: Used to name the commit, if omitted the tag is generated
    automatically as an incrementing counter.

## Inspiration

This script was inspired as a continuation of my search for new and better? ways to store and share versioned datasets.  I thought of the question:  What if Borg could create a tarball-like file instead of a directory?  After a little searching, I found the following thread online:

* [https://github.com/borgbackup/borg/issues/4808](https://github.com/borgbackup/borg/issues/4808)

Where jpfleury was asking basically the same question.  The Borg maintainers understandably saw this option as too complex and outside their scope, ending with "If you need that composition, just write a shell script.".  Well, I couldn't find any evidence that Jean-Philippe had done that, so I decided to take a shot at it.  This repo is the proof-of-concept for that.

## What's next?

Probably nothing... But this experience has gotten me thinking that this tool could be expanded to allow a very Git-like workflow for datasets.  My hangup is the prerequisite software users would have to install.  To do this right, it needs to be self-contained.  And I don't have time to do that right now, so it'll have to wait.
