
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Zip' -Resolve) -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Glob' -Resolve) -Force

$archive = $null

function GivenFile
{
    param(
        [string[]]
        $Path,

        $Content
    )

    foreach( $pathItem in $Path )
    {
        $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $pathItem

        $parentDir = $fullPath | Split-Path
        if( -not (Test-Path -Path $parentDir -PathType Container) )
        {
            New-Item -Path $parentDir -ItemType 'Directory'
        }

        if( -not (Test-Path -Path $fullPath -PathType Leaf) )
        {
            New-Item -Path $fullPath -ItemType 'File'
        }

        if( $Content )
        {
            [IO.File]::WriteAllText($fullPath,$Content)
        }
    }
}

function Init
{
    $script:archive = $null
}

function ThenArchiveContains
{
    param(
        [string[]]
        $EntryName,

        $ExpectedContent
    )

    [IO.Compression.ZipArchive]$file = [IO.Compression.ZipFile]::OpenRead($archive.FullName)
    try
    {
        It ('shouldn''t have duplicate entries') {
            $file.Entries | Group-Object -Property 'FullName' | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty 'Group' | Should -HaveCount 0
        }

        It ('should add files to ZIP') {
            foreach( $entryNameItem in $EntryName )
            {
                [IO.Compression.ZipArchiveEntry]$entry = $file.GetEntry($entryNameItem) 
                $entry | Should -Not -BeNullOrEmpty
                if( $ExpectedContent )
                {
                    $reader = New-Object 'IO.StreamReader' ($entry.Open())
                    try
                    {
                        $content = $reader.ReadToEnd()
                        $content | Should -Be $ExpectedContent
                    }
                    finally
                    {
                        $reader.Close()
                    }
                }
            }
        }
    }
    finally
    {
        $file.Dispose()
    }
}

function ThenArchiveEmpty
{
    [IO.Compression.ZipArchive]$file = [IO.Compression.ZipFile]::OpenRead($archive.FullName)
    try
    {
        It ('should not add any files to ZIP') {
            $file.Entries | Should -BeNullOrEmpty
        }
    }
    finally
    {
        $file.Dispose()
    }    
}

function ThenArchiveNotContains
{
    param(
        [string[]]
        $Entry
    )

    [IO.Compression.ZipArchive]$file = [IO.Compression.ZipFile]::OpenRead($archive.FullName)
    try
    {
        It ('should not add files to ZIP') {
            foreach( $entryName in $Entry )
            {
                $file.GetEntry($entryName) | Should -BeNullOrEmpty
            }
        }
    }
    finally
    {
        $file.Dispose()
    }
}

function ThenError
{
    param(
        $Matches
    )

    It ('should write an error') {
        $Global:Error | Should -Match $Matches
    }
}

function WhenAddingFiles
{
    [CmdletBinding()]
    param(
        [string[]]
        $Path,

        [Switch]
        $Force,

        $AtArchiveRoot,

        $WithBasePath,

        $WithName
    )

    $archivePath = Join-Path -Path $TestDrive.FullName -ChildPath 'zip.zip'
    if( -not (Test-Path -Path $archivePath -PathType Leaf) )
    {
        $script:archive = New-ZipArchive -Path $archivePath
    }

    $params = @{
                    ZipArchivePath = $archive.FullName;
                }

    if( $AtArchiveRoot )
    {
        $params['EntryParentPath'] = $AtArchiveRoot
    }

    if( $Force )
    {
        $params['Force'] = $true
    }

    if( $WithBasePath )
    {
        $params['BasePath'] = $WithBasePath
    }

    if( $WithName )
    {
        $params['EntryName'] = $WithName
    }

    $Global:Error.Clear()

    $Path | 
        ForEach-Object { Join-Path -Path $TestDrive.FullName -ChildPath $_ } |
        Get-Item |
        Add-ZipArchiveEntry @params
}

Describe 'Add-ZipArchiveEntry' {
    Init
    GivenFile 'one.cs','one.aspx','one.js','one.txt'
    WhenAddingFiles '*.aspx','*.js'
    ThenArchiveContains 'one.aspx','one.js'
    ThenArchiveNotContains 'one.cs','one.txt'
}

Describe 'Add-ZipArchiveEntry.when file already exists' {
    Init
    GivenFile 'one.cs' 'first'
    WhenAddingFiles '*.cs'
    GivenFile 'one.cs' 'second'
    WhenAddingFiles '*.cs' -ErrorAction SilentlyContinue
    ThenArchiveContains 'one.cs' 'first'
    ThenError -Matches 'archive\ already\ has'
}

Describe 'Add-ZipArchiveEntry.when file already exists and forcing overwrite' {
    Init
    GivenFile 'one.cs' 'first'
    WhenAddingFiles '*.cs'
    GivenFile 'one.cs' 'second'
    WhenAddingFiles '*.cs' -Force
    ThenArchiveContains 'one.cs' 'second'
}

Describe 'Add-ZipArchiveEntry.when adding archive root' {
    Init
    GivenFile 'one.cs'
    WhenAddingFiles '*.cs' -AtArchiveRoot 'package'
    ThenArchiveContains 'package\one.cs'
    ThenArchiveNotContains 'one.cs'
}

Describe 'Add-ZipArchiveEntry.when passing path instead of file objects' {
    Init
    GivenFile 'one.cs','two.cs'
    WhenAddingFiles '*.cs'
    ThenArchiveContains 'one.cs','two.cs'
}

Describe 'Add-ZipArchiveEntry.when changing name' {
    Init
    GivenFile 'one.cs'
    WhenAddingFiles 'one.cs' -WithName 'cs.one'
    ThenArchiveContains 'cs.one'
    ThenArchiveNotContains 'one.cs'
}

Describe 'Add-ZipArchiveEntry.when passing a directory' {
    Init
    GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
    WhenAddingFiles 'dir1'
    ThenArchiveContains 'dir1\one.cs','dir1\two.cs','dir1\three\four.cs'
}

Describe 'Add-ZipArchiveEntry.when customizing a directory name' {
    Init
    GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
    WhenAddingFiles 'dir1' -WithName '1dir'
    ThenArchiveContains '1dir\one.cs','1dir\two.cs','1dir\three\four.cs'
    ThenArchiveNotContains 'dir1\one.cs','dir1\two.cs','dir1\three\four.cs'
}

Describe 'Add-ZipArchiveEntry.when passing a directory with a custom base path' {
    Init
    GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
    WhenAddingFiles 'dir1'
    ThenArchiveContains 'dir1\one.cs','dir1\two.cs','dir1\three\four.cs'
}

Describe 'Add-ZipArchiveEntry.when piping filtered list of files' {
    Init
    GivenFile 'dir1\another\one.cs','dir1\another\two.cs'
    $root = Join-Path -Path $TestDrive.FullName -ChildPath 'dir1'
    WhenAddingFiles 'dir1\another\one.cs','dir1\another\two.cs' -AtArchiveRoot 'dir2' -WithBasePath $root
    ThenArchiveContains 'dir2\another\one.cs','dir2\another\two.cs'
}

Describe 'Add-ZipArchiveEntry.when giving a direcotry a new root name' {
    Init
    GivenFile 'dir1\one.cs','dir1\two.cs'
    $root = Join-Path -Path $TestDrive.FullName -ChildPath 'dir1'
    WhenAddingFiles 'dir1\*.cs' -AtArchiveRoot 'dir2'
    ThenArchiveContains 'dir2\one.cs','dir2\two.cs'
}

Describe 'Add-ZipArchiveEntry.when base path doesn''t match files' {
    Init
    GivenFile 'one.cs'
    WhenAddingFiles 'one.cs' -WithBasePath 'C:\Windows\System32' -ErrorAction SilentlyContinue
    ThenError -Matches 'is\ not\ in'
}

Describe 'Add-ZipArchiveEntry.when base path has a directory separator at the end' {
    Init
    GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
    WhenAddingFiles 'dir1' -WithBasePath (Join-Path -Path $TestDrive.FullName -ChildPath 'dir1\')
    ThenArchiveContains 'one.cs','two.cs','three\four.cs'
}

