
# Zip PowerShell Module Changelog

## 1.0.0

Added WhatIf/ShouldProcess support to `New-ZipArchive` and `Add-ZipArchiveEntry`.

## 0.3.2

> Released 3 Sep 2020

Fixed: Add-ZipArchiveEntry fails to add a file with a last write timestamp before 1980 January 1 0:00:00 (midnight) or
later than 2107 December 31 23:59:59.

## 0.3.1

> Released 5 Sep 2019

Fixed: creates archives that can't be extracted on non-Windows platforms.

## 0.3.0

> Released 25 Jan 2019

* Fixed: `Add-ZipArchiveEntry` fails when passed multiple paths directly, in a non-pipeline manner.
* `Add-ZipArchiveEntry` no longer supports resolving wildcard expressions in paths.
* Fixed: `New-ZipArchive` fails if archive name contains `[]` characters.
* Improved the performance of `Add-ZipArchiveEntry` when zipping a large number of files by reducing the number of
  progress messages that are written during the operation. Progress messages are now only written every 100ms as opposed
  for every file added to the ZIP archive.
* Added a `-Quiet` switch to `Add-ZipArchiveEntry` that will suppress progress messages during the operation.

## 0.2.0

> Released 27 Dec 2018

`Add-ZipArchiveEntry` now preserves a file's last write/modified date/time.

## 0.1.0

> Released 24 Dec 2018

Optimized `Add-ZipArchiveEntry` to compress files more than an order of magnitude faster. In our testing, compressing a
190MB folder of 538 files/assemblies went from 2 minutes to 14 seconds.

## 0.0.0

> Releaesd 17 Dec 2018

* Created `New-ZipArchive` function for creating new archives.
* Created `Add-ZipArchiveEntry` funcgtion for adding files to an existing ZIP archive.
