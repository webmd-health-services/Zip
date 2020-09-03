
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Zip' -Resolve) -Force

$result = $null

function GivenFile
{
    param(
        [string[]]
        $Path
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
    }
}

function Init
{
    $script:result = $null
}

function ThenArchiveCreated
{
    param(
        $ExpectedPath
    )

    Test-Path -LiteralPath $result.FullName -PathType Leaf | Should -BeTrue
    $result | Should -BeOfType ([IO.FileInfo])
    $result.FullName | Should -Be (Join-Path -Path $TestDrive.FullName -ChildPath $ExpectedPath)

    $zipExpandPath = Join-Path -Path $TestDrive.FullName -ChildPath ('zip.{0}' -f [IO.Path]::GetRandomFileName())
    { Expand-Archive -LiteralPath $result.FullName -DestinationPath $zipExpandPath } | Should -Not -Throw
}

function ThenError
{
    param(
        $Matches
    )

    $Global:Error | Should -Match $Matches
}

function ThenNothingReturned
{
    $result | Should -BeNullOrEmpty
}

function WhenCreatingArchive
{
    [CmdletBinding()]
    param(
        $Name,
        [Switch]
        $WithRelativePath,
        [Switch]
        $Force
    )

    $path = Join-Path -Path $TestDrive.FullName -ChildPath $Name
    if( $WithRelativePath )
    {
        Push-Location $TestDrive.FullName
        $path = $Name
    }

    try
    {
        $Global:Error.Clear()
        $script:result = New-ZipArchive -Path $path -Force:$Force
    }
    catch
    {
        Write-Error -ErrorRecord $_
    }
    finally
    {
        if( $WithRelativePath )
        {
            Pop-Location
        }
    }
}

Describe 'New-ZipArchive.when passing absolute path' {
    It 'should create archive at that path' {
        Init
        WhenCreatingArchive 'somefile.zip'
        ThenArchiveCreated 'somefile.zip'
    }
}

Describe 'New-ZipArchive.when passing relative path' {
    It 'should resolve path relative to working directory' {
        Init
        WhenCreatingArchive 'somefile.zip' -WithRelativePath
        ThenArchiveCreated 'somefile.zip'
    }
}

Describe 'New-ZipArchive.when file exists' {
    It 'should fail' {
        Init
        GivenFile 'somefile.zip'
        WhenCreatingArchive 'somefile.zip' -ErrorAction SilentlyContinue
        ThenNothingReturned
        ThenError -Matches 'already exists'
    }
}

Describe 'New-ZipArchive.when file exists and forcing creation' {
    It 'should clobber original file' {
        Init
        GivenFile 'somefile.zip'
        WhenCreatingArchive 'somefile.zip' -Force
        ThenArchiveCreated 'somefile.zip'
    }
}

Describe 'New-ZipArchive.when destination exists but it''s a directory' {
    It 'should fail' {
        Init
        GivenFile 'dir1.zip/somefile.zip'
        WhenCreatingArchive 'dir1.zip' -Force -ErrorAction SilentlyContinue
        ThenNothingReturned
        ThenError -Matches 'is\ a\ directory'
    }
}

Describe 'New-ZipArchive.when passing path with valid special characters in path' {
    It 'should create the file with those characters' {
        Init
        WhenCreatingArchive 'somefile[1].zip'
        ThenArchiveCreated 'somefile[1].zip'
    }
}

# Only Windows really has filename character limitations
if ($IsWindows)
{
    Describe 'New-ZipArchive.when passing path with invalid special characters in path' {
        $expectedError = 'Illegal characters in path'
        if ($PSVersionTable.PSVersion.Major -ge 6)
        {
            $expectedError = 'The filename, directory name, or volume label syntax is incorrect.'
        }

        It 'should fail' {
            Init
            WhenCreatingArchive 'somefile*.zip' -ErrorAction SilentlyContinue
            ThenNothingReturned
            ThenError -Matches $expectedError
        }
    }
}
