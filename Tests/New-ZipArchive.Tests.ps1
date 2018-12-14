
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

    It ('should return FileInfo object for archive') {
        $result | Should -Exist
        $result | Should -BeOfType ([IO.FileInfo])
        $result.FullName | Should -Be (Join-Path -Path $TestDrive.FullName -ChildPath $ExpectedPath)
    }

    $zipExpandPath = Join-Path -Path $TestDrive.FullName -ChildPath ('zip.{0}' -f [IO.Path]::GetRandomFileName())
    It ('should create an empty ZIP file') {
        { Expand-Archive -Path $result.FullName -DestinationPath $zipExpandPath } | Should -Not -Throw
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

function ThenNothingReturned
{
    It ('should return nothing') {
        $result | Should -BeNullOrEmpty
    }
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
    finally
    {
        if( $WithRelativePath )
        {
            Pop-Location
        }
    }
}

Describe 'New-ZipArchive.when passing absolute path' {
    Init
    WhenCreatingArchive 'somefile.zip'
    ThenArchiveCreated 'somefile.zip'
}

Describe 'New-ZipArchive.when passing relative path' {
    Init
    WhenCreatingArchive 'somefile.zip' -WithRelativePath
    ThenArchiveCreated 'somefile.zip'
}

Describe 'New-ZipArchive.when file exists' {
    Init
    GivenFile 'somefile.zip'
    WhenCreatingArchive 'somefile.zip' -ErrorAction SilentlyContinue
    ThenNothingReturned
    ThenError -Matches 'already exists'
}

Describe 'New-ZipArchive.when file exists and forcing creation' {
    Init
    GivenFile 'somefile.zip'
    WhenCreatingArchive 'somefile.zip' -Force
    ThenArchiveCreated 'somefile.zip'
}
