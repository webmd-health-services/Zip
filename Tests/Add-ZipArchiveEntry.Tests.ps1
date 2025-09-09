
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Zip' -Resolve) -Force
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Glob' -Resolve) -Force

    $script:testDirPath = $null
    $script:testNum = 0
    $script:archive = $null

    # https://docs.microsoft.com/en-us/dotnet/api/system.io.compression.ziparchiveentry.lastwritetime#exceptions
    $script:ZipEntryLastWriteTime_MinimumValue = [datetime]'1/1/1980 00:00:00'
    $script:ZipEntryLastWriteTime_MaximumValue = [datetime]'12/31/2107 23:59:59'

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
            $fullPath = Join-Path -Path $script:testDirPath -ChildPath $pathItem

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

    function ThenArchiveContains
    {
        param(
            [string[]]
            $EntryName,

            $ExpectedContent,

            [DateTime]
            $LastModified
        )

        [IO.Compression.ZipArchive]$file = [IO.Compression.ZipFile]::OpenRead($script:archive.FullName)
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
        [IO.Compression.ZipArchive]$file = [IO.Compression.ZipFile]::OpenRead($script:archive.FullName)
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

        [IO.Compression.ZipArchive]$file = [IO.Compression.ZipFile]::OpenRead($script:archive.FullName)
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
            $MatchesRegex
        )

        $Global:Error | Should -Match $MatchesRegex
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

        $archivePath = Join-Path -Path $script:testDirPath -ChildPath 'zip.zip'
        if( -not (Test-Path -Path $archivePath -PathType Leaf) )
        {
            $script:archive = New-ZipArchive -Path $archivePath
        }

        $params = @{
            ZipArchivePath = $script:archive.FullName
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

        $pathsToZip = $Path | ForEach-Object { Join-Path -Path $script:testDirPath -ChildPath $_ }

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
}

Describe 'Add-ZipArchiveEntry' {
    BeforeEach {
        $script:archive = $null
        $script:testDirPath = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testDirPath -ItemType Directory
    }

    It 'adds files to an archive' {
        $lastModified = (Get-Date).AddDays(-1)
        GivenFile 'one.cs','one.aspx','one.js','one.txt' -LastModified $lastModified
        WhenAddingFiles '*.aspx','*.js'
        ThenArchiveContains 'one.aspx','one.js' -LastModified $lastModified
        ThenArchiveNotContains 'one.cs','one.txt'
    }

    It 'adds non-pipelined files to archive' {
        GivenFile 'one.cs', 'two.cs'
        WhenAddingFiles 'one.cs', 'two.cs' -NonPipeline
        ThenArchiveContains 'one.cs', 'two.cs'
    }

    It 'it does not replace existing entry' {
        GivenFile 'one.cs' 'first'
        WhenAddingFiles '*.cs'
        GivenFile 'one.cs' 'second'
        WhenAddingFiles '*.cs' -ErrorAction SilentlyContinue
        ThenArchiveContains 'one.cs' 'first'
        ThenError -Matches 'archive\ already\ has'
    }

    It 'it replaces existing entry' {
        GivenFile 'one.cs' 'first'
        WhenAddingFiles '*.cs'
        GivenFile 'one.cs' 'second'
        WhenAddingFiles '*.cs' -Force
        ThenArchiveContains 'one.cs' 'second'
    }

    It 'adds file in specific directory in archive' {
        GivenFile 'one.cs'
        WhenAddingFiles '*.cs' -AtArchiveRoot 'package'
        ThenArchiveContains 'package/one.cs'
        ThenArchiveNotContains 'one.cs'
    }

    It 'supports file paths' {
        GivenFile 'one.cs','two.cs'
        WhenAddingFiles 'one.cs', 'two.cs' -AsPathString
        ThenArchiveContains 'one.cs','two.cs'
    }

    It 'customizes file name in archive' {
        GivenFile 'one.cs'
        WhenAddingFiles 'one.cs' -WithName 'cs.one'
        ThenArchiveContains 'cs.one'
        ThenArchiveNotContains 'one.cs'
    }

    It 'adds all the files under a directory to the archive' {
        GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
        WhenAddingFiles 'dir1'
        ThenArchiveContains 'dir1/one.cs','dir1/two.cs','dir1/three/four.cs'
    }

    It 'customizes directory name' {
        GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
        WhenAddingFiles 'dir1' -WithName '1dir'
        ThenArchiveContains '1dir/one.cs','1dir/two.cs','1dir/three/four.cs'
        ThenArchiveNotContains 'dir1/one.cs','dir1/two.cs','dir1/three/four.cs'
    }

    It 'uses custom base path' {
        GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
        WhenAddingFiles 'dir1' -WithBasePath (Join-Path -Path $script:testDirPath -ChildPath 'dir1')
        ThenArchiveContains 'one.cs','two.cs','three/four.cs'
    }

    It 'uses custom directory name with a change to the root directory' {
        GivenFile 'dir1\another\one.cs','dir1\another\two.cs'
        $root = Join-Path -Path $script:testDirPath -ChildPath 'dir1'
        WhenAddingFiles 'dir1\another\one.cs','dir1\another\two.cs' -AtArchiveRoot 'dir2' -WithBasePath $root
        ThenArchiveContains 'dir2/another/one.cs','dir2/another/two.cs'
    }

    It 'customizes file parent directory name' {
        GivenFile 'dir1\one.cs','dir1\two.cs'
        WhenAddingFiles 'dir1\*.cs' -AtArchiveRoot 'dir2'
        ThenArchiveContains 'dir2/one.cs','dir2/two.cs'
    }

    It 'customzies direcotry parent direcotry name ' {
        GivenFile 'dir1\one.cs','dir1\two.cs'
        WhenAddingFiles 'dir1' -AtArchiveRoot 'dir2'
        ThenArchiveContains 'dir2/dir1/one.cs','dir2/dir1/two.cs'
    }

    It 'validates base path part of each path' {
        GivenFile 'one.cs'
        WhenAddingFiles 'one.cs' -WithBasePath 'C:\Windows\System32' -ErrorAction SilentlyContinue
        ThenError -Matches 'is\ not\ in'
    }

    It 'ignore separator at end of custom base path' {
        GivenFile 'dir1\one.cs','dir1\two.cs', 'dir1\three\four.cs'
        WhenAddingFiles 'dir1' -WithBasePath (Join-Path -Path $script:testDirPath -ChildPath 'dir1\')
        ThenArchiveContains 'one.cs','two.cs','three/four.cs'
    }

    It 'rejects paths with wildcards that do not exist' {
        GivenFile 'one.cs', 'two.cs'
        WhenAddingFiles '*.cs', 'one.cs' -AsPathString -ErrorAction SilentlyContinue
        ThenArchiveContains 'one.cs'
        ThenArchiveNotContains 'two.cs'
        ThenError -Matches 'does\ not\ exist\.\ Wildcard\ expressions\ are\ not\ supported\.'
    }

    It 'accepts paths with wildcards that exist' {
        GivenFile '[one].cs', 'o.cs', 'n.cs', 'e.cs', 'two.cs'
        WhenAddingFiles '[one].cs', 'two.cs' -AsPathString
        ThenArchiveContains '[one].cs', 'two.cs'
        ThenArchiveNotContains 'o.cs', 'n.cs', 'e.cs'
    }

    It 'turns off progress' {
        Mock -CommandName 'Write-Progress' -ModuleName 'Zip'
        GivenFile 'one.cs'
        WhenAddingFiles 'one.cs' -Quiet
        Assert-MockCalled -CommandName 'Write-Progress' -ModuleName 'Zip' -Times 0
    }

    It 'handles files with less than mininum last write time value' {
        GivenFile 'file.txt' -LastModified $script:ZipEntryLastWriteTime_MinimumValue.AddSeconds(-1)
        WhenAddingFiles 'file.txt'
        ThenArchiveContains 'file.txt' -LastModified $script:ZipEntryLastWriteTime_MinimumValue
    }

    It 'handles files with greater than maximum last write time value' {
        GivenFile 'file.txt' -LastModified $script:ZipEntryLastWriteTime_MaximumValue.AddSeconds(1)
        WhenAddingFiles 'file.txt'
        ThenArchiveContains 'file.txt' -LastModified $script:ZipEntryLastWriteTime_MaximumValue
    }
}
