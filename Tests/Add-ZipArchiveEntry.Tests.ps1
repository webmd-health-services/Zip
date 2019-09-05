
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

        $Content,

        [datetime]
        $LastModified
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

        if( $LastModified )
        {
            (Get-Item -Path $fullPath).LastWriteTime = $LastModified
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

        $ExpectedContent,

        [DateTime]
        $LastModified
    )

    [IO.Compression.ZipArchive]$file = [IO.Compression.ZipFile]::OpenRead($archive.FullName)
    try
    {
        $file.Entries | 
            Group-Object -Property 'FullName' | 
            Where-Object { $_.Count -gt 1 } | 
            Select-Object -ExpandProperty 'Group' | 
            Should -HaveCount 0
        # Make sure we use '/' as the separator character, as using '\' makes a ZIP file unusable on non-Windows platforms
        $file.Entries | Where-Object { $_.FullName -match '\\' } | Should -BeNullOrEmpty
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
            if( $LastModified )
            {
                # Zip files have two-second granularity times
                $entry.LastWriteTime | Should -BeGreaterThan $LastModified.AddSeconds(-2)
                $entry.LastWriteTime | Should -BeLessThan $LastModified.AddSeconds(2)
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
        $file.Entries | Should -BeNullOrEmpty
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
        foreach( $entryName in $Entry )
        {
            $file.GetEntry($entryName) | Should -BeNullOrEmpty
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

    $Global:Error | Should -Match $Matches
}

function WhenAddingFiles
{
    [CmdletBinding()]
    param(
        [string[]]
        $Path,

        [switch]
        $AsPathString,

        [switch]
        $NonPipeline,

        [Switch]
        $Force,

        $AtArchiveRoot,

        $WithBasePath,

        $WithName,

        [switch]
        $Quiet
    )

    $archivePath = Join-Path -Path $TestDrive.FullName -ChildPath 'zip.zip'
    if( -not (Test-Path -Path $archivePath -PathType Leaf) )
    {
        $script:archive = New-ZipArchive -Path $archivePath
    }

    $params = @{
        ZipArchivePath = $archive.FullName
        Quiet = $Quiet
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

    $pathsToZip = $Path | ForEach-Object { Join-Path -Path $TestDrive.FullName -ChildPath $_ }

    if( -not $AsPathString )
    {
        $pathsToZip = $pathsToZip | Get-Item
    }

    if( $NonPipeline )
    {
        Add-ZipArchiveEntry -InputObject $pathsToZip @params
    }
    else
    {
        $pathsToZip | Add-ZipArchiveEntry @params
    }
}

Describe 'Add-ZipArchiveEntry' {
    It 'should add files to an archive' {
        Init
        $lastModified = (Get-Date).AddDays(-1)
        GivenFile 'one.cs','one.aspx','one.js','one.txt' -LastModified $lastModified
        WhenAddingFiles '*.aspx','*.js'
        ThenArchiveContains 'one.aspx','one.js' -LastModified $lastModified
        ThenArchiveNotContains 'one.cs','one.txt'
    }
}

Describe 'Add-ZipArchiveEntry.when passing files directly to InputObject parameter' {
    It 'should add the files to the archive' {
        Init
        GivenFile 'one.cs', 'two.cs'
        WhenAddingFiles 'one.cs', 'two.cs' -NonPipeline
        ThenArchiveContains 'one.cs', 'two.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when file already exists in the archive' {
    It 'should fail' {
        Init
        GivenFile 'one.cs' 'first'
        WhenAddingFiles '*.cs'
        GivenFile 'one.cs' 'second'
        WhenAddingFiles '*.cs' -ErrorAction SilentlyContinue
        ThenArchiveContains 'one.cs' 'first'
        ThenError -Matches 'archive\ already\ has'
    }
}

Describe 'Add-ZipArchiveEntry.when file already exists and forcing overwrite' {
    It 'should replace the existing file' {
        Init
        GivenFile 'one.cs' 'first'
        WhenAddingFiles '*.cs'
        GivenFile 'one.cs' 'second'
        WhenAddingFiles '*.cs' -Force
        ThenArchiveContains 'one.cs' 'second'
    }
}

Describe 'Add-ZipArchiveEntry.when adding archive root' {
    It 'should put file in that root in the archive' {
        Init
        GivenFile 'one.cs'
        WhenAddingFiles '*.cs' -AtArchiveRoot 'package'
        ThenArchiveContains 'package/one.cs'
        ThenArchiveNotContains 'one.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when passing path instead of file objects' {
    It 'should add the files' {
        Init
        GivenFile 'one.cs','two.cs'
        WhenAddingFiles 'one.cs', 'two.cs' -AsPathString
        ThenArchiveContains 'one.cs','two.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when changing name' {
    It 'should use the custom name in the archive' {
        Init
        GivenFile 'one.cs'
        WhenAddingFiles 'one.cs' -WithName 'cs.one'
        ThenArchiveContains 'cs.one'
        ThenArchiveNotContains 'one.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when passing a directory' {
    It 'should add all the files under that directory to the archive' {
        Init
        GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
        WhenAddingFiles 'dir1'
        ThenArchiveContains 'dir1/one.cs','dir1/two.cs','dir1/three/four.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when customizing a directory name' {
    It 'should use custom directory name for the directory' {
        Init
        GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
        WhenAddingFiles 'dir1' -WithName '1dir'
        ThenArchiveContains '1dir/one.cs','1dir/two.cs','1dir/three/four.cs'
        ThenArchiveNotContains 'dir1/one.cs','dir1/two.cs','dir1/three/four.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when passing a directory with a custom base path' {
    It 'should omit base directory information from archive' {
        Init
        GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
        WhenAddingFiles 'dir1' -WithBasePath (Join-Path -Path $TestDrive.FullName -ChildPath 'dir1')
        ThenArchiveContains 'one.cs','two.cs','three/four.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when piping filtered list of files' {
    It 'should use custom directory name and change the root directory' {
        Init
        GivenFile 'dir1\another\one.cs','dir1\another\two.cs'
        $root = Join-Path -Path $TestDrive.FullName -ChildPath 'dir1'
        WhenAddingFiles 'dir1\another\one.cs','dir1\another\two.cs' -AtArchiveRoot 'dir2' -WithBasePath $root
        ThenArchiveContains 'dir2/another/one.cs','dir2/another/two.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when giving files a new root name' {
    It 'should use the new root name' {
        Init
        GivenFile 'dir1\one.cs','dir1\two.cs'
        WhenAddingFiles 'dir1\*.cs' -AtArchiveRoot 'dir2'
        ThenArchiveContains 'dir2/one.cs','dir2/two.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when giving a directory a new root name' {
    It 'should add the directory into the new root directory' {
        Init
        GivenFile 'dir1\one.cs','dir1\two.cs'
        WhenAddingFiles 'dir1' -AtArchiveRoot 'dir2'
        ThenArchiveContains 'dir2/dir1/one.cs','dir2/dir1/two.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when base path doesn''t match files' {
    It 'should fail' {
        Init
        GivenFile 'one.cs'
        WhenAddingFiles 'one.cs' -WithBasePath 'C:\Windows\System32' -ErrorAction SilentlyContinue
        ThenError -Matches 'is\ not\ in'
    }
}

Describe 'Add-ZipArchiveEntry.when base path has a directory separator at the end' {
    It 'should ignore the separator' {
        Init
        GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
        WhenAddingFiles 'dir1' -WithBasePath (Join-Path -Path $TestDrive.FullName -ChildPath 'dir1\')
        ThenArchiveContains 'one.cs','two.cs','three/four.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when passed path string with wildcard' {
    It 'should fail' {
        Init
        GivenFile 'one.cs', 'two.cs'
        WhenAddingFiles '*.cs', 'one.cs' -AsPathString -ErrorAction SilentlyContinue
        ThenArchiveContains 'one.cs'
        ThenArchiveNotContains 'two.cs'
        ThenError -Matches 'does\ not\ exist\.\ Wildcard\ expressions\ are\ not\ supported\.'
    }
}

Describe 'Add-ZipArchiveEntry.when character set wildcard matches a filename literally' {
    It 'should include the file' {
        Init
        GivenFile '[one].cs', 'o.cs', 'n.cs', 'e.cs', 'two.cs'
        WhenAddingFiles '[one].cs', 'two.cs' -AsPathString
        ThenArchiveContains '[one].cs', 'two.cs'
        ThenArchiveNotContains 'o.cs', 'n.cs', 'e.cs'
    }
}

Describe 'Add-ZipArchiveEntry.when using Quiet switch' {
    It 'should not call Write-Progress' {
        Init
        Mock -CommandName 'Write-Progress' -ModuleName 'Zip'
        GivenFile 'one.cs'
        WhenAddingFiles 'one.cs' -Quiet
        Assert-MockCalled -CommandName 'Write-Progress' -ModuleName 'Zip' -Times 0
    }
}
