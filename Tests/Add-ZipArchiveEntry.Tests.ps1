
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

function  WhenAddingFiles
{
    [CmdletBinding()]
    param(
        [string[]]
        $Path,

        [Switch]
        $Force,

        $AtArchiveRoot,

        [Switch]
        $NoPipeline,

        [Switch]
        $NoBasePath,

        [string]
        $AtBasePath
    )

    $archivePath = Join-Path -Path $TestDrive.FullName -ChildPath 'zip.zip'
    if( -not (Test-Path -Path $archivePath -PathType Leaf) )
    {
        $script:archive = New-ZipArchive -Path $archivePath
    }

    $params = @{
                    ZipArchivePath = $archive.FullName;
                }
    if( -not $NoBasePath )
    {
        $params['BasePath'] = $TestDrive.FullName;
    }

    if( $AtBasePath )
    {
        $params['BasePath'] = $AtBasePath
    }

    if( $AtArchiveRoot )
    {
        $params['EntryParentPath'] = $AtArchiveRoot
    }

    if( $Force )
    {
        $params['Force'] = $true
    }

    $Global:Error.Clear()
    if( $NoPipeline )
    {
        Push-Location -Path $TestDrive.FullName
        try
        {
            foreach( $item in $Path )
            {
                Add-ZipArchiveEntry @params -InputObject $item
            }
        }
        finally
        {
            Pop-Location
        }
    }
    else
    {
        Find-GlobFile -Path $TestDrive.FullName -Include $Path | Add-ZipArchiveEntry @params
    }
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
    WhenAddingFiles '*.cs' -NoPipeline
    ThenArchiveContains 'one.cs','two.cs'
}

Describe 'Add-ZipArchiveEntry.when no base path' {
    Init
    GivenFile 'one.cs','two.cs'
    WhenAddingFiles '*.cs' -NoBasePath
    $rootPath = $TestDrive.FullName -replace '^[^:]:\\',''
    ThenArchiveContains ('one.cs','two.cs' | ForEach-Object { '{0}\{1}' -f $rootPath,$_ })
}

Describe 'Add-ZipArchiveEntry.when passing a directory' {
    Init
    GivenFile 'dir1\one.cs','dir1\two.cs'
    WhenAddingFiles (Join-Path -Path $TestDrive.FullName -ChildPath 'dir1') -NoPipeline
    ThenArchiveContains 'dir1\one.cs','dir1\two.cs'
}

Describe 'Add-ZipArchiveEntry.when giving an item a new root name' {
    Init
    GivenFile 'dir1\one.cs','dir1\two.cs'
    $root = Join-Path -Path $TestDrive.FullName -ChildPath 'dir1'
    WhenAddingFiles $root -AtBasePath $root -AtArchiveRoot 'dir2' -NoPipeline
    ThenArchiveContains 'dir2\one.cs','dir2\two.cs'
}
