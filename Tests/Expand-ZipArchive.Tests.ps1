
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Zip' -Resolve) -Force

$expandToName = 'decompress'
$expandToPath = $null

function Init
{
    $script:expandToPath = Join-Path -Path $TestDrive.FullName -ChildPath $expandToName
}

function GivenArchive
{
    param(
        $FileName,
        $WithFiles
    )

    $zip = New-ZipArchive -Path (Join-Path -Path $TestDrive.FullName -ChildPath $FileName)

    foreach( $file in $WithFiles )
    {
        $filePath = Join-Path -Path $TestDrive.FullName -ChildPath $file
        New-Item -Path $filePath -ItemType 'File' | Out-Null
        Add-ZipArchiveEntry -ZipArchivePath $zip -InputObject $filePath -BasePath $TestDrive.FullName
    }
}

function GivenFile
{
    param(
        $Path,
        $WithContent
    )

    foreach( $pathItem in $Path )
    {
        $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $pathItem
        New-Item -Path $fullPath -ItemType 'File' | Out-Null
        if( $WithContent )
        {
            [IO.File]::WriteAllText($fullPath,$WithContent)
        }
    }
}

function GivenDirectory
{
    param(
        $Path
    )

    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Path) -ItemType 'Directory' | Out-Null
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

function ThenFile
{
    param(
        $Named,
        $HasContent,
        $Because
    )

    It $Because {
        $path = Join-Path -Path $expandToPath -ChildPath $Named
        $path | Should -Exist
        $path | Should -FileContentMatchExactly $HasContent
    }
}

function ThenFilesDecompressed
{
    param(
        $Files
    )

    It ('should decompress the archive') {
        foreach( $file in $Files )
        {
            $filePath = Join-Path -Path $expandToPath -ChildPath $file
            $filePath | Should -Exist
            [IO.File]::ReadAllText($filePath) | Should -BeNullOrEmpty
        }
    }
}

function ThenFilesNotDecompressed
{
    param(
        $Files
    )

    It ('should not decompress the archive') {
        foreach( $file in $Files )
        {
            $filePath = Join-Path -Path $expandToPath -ChildPath $file
            $filePath | Should -Not -Exist
        }
    }
}

function ThenNoErrors
{
    param(
    )

    It ('should not write any errors') {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function WhenDecompressing
{
    [CmdletBinding()]
    param(
        $ZipArchive,
        [Switch]
        $Force,
        $To = $expandToPath
    )

    Push-Location -Path $TestDrive.FullName
    try
    {
        $Global:Error.Clear()
        Expand-ZipArchive -Path $ZipArchive -DestinationPath $To -Force:$Force
    }
    finally
    {
        Pop-Location
    }
}

Describe ('Expand-ZipArchive') {
    Init
    GivenArchive 'zip.upack' -WithFiles 'file1','file2'
    WhenDecompressing 'zip.upack'
    ThenFilesDecompressed 'file1','file2'
}

Describe ('Expand-ZipArchive.when using absolute path to zip archive') {
    Init
    GivenArchive 'zip.upack' -WithFiles 'file1','file2'
    WhenDecompressing (Join-Path -Path $TestDrive -ChildPath 'zip.upack')
    ThenFilesDecompressed 'file1','file2'
    ThenNoErrors
}

Describe ('Expand-ZipArchive.when archive doesn''t exist') {
    Init
    WhenDecompressing 'zip.upack' -ErrorAction SilentlyContinue
    ThenFilesNotDecompressed 'file1','file2'
    ThenError 'does\ not\ exist'
}

Describe ('Expand-ZipArchive.when directory doesn''t exist') {
    Init
    GivenArchive 'zip.upack' -WithFiles 'file1','file2'
    WhenDecompressing 'zip.upack' -To 'decompress\level2'
    ThenFilesDecompressed 'level2\file1','level2\file2'
    ThenNoErrors
}

Describe ('Expand-ZipArchive.when directory exists') {
    Init
    GivenArchive 'zip.upack' -WithFiles 'file1','file2'
    GivenDirectory $expandToName
    WhenDecompressing 'zip.upack' -To $expandToName
    ThenFilesDecompressed 'file1','file2'
    ThenNoErrors
}

Describe ('Expand-ZipArchive.when directory has contents') {
    Init
    GivenArchive 'zip.upack' -WithFiles 'file1','file2'
    GivenDirectory $expandToName
    GivenFile (Join-Path -Path $expandToName -ChildPath 'file1') -WithContent 'AAAAA'
    WhenDecompressing 'zip.upack' -ErrorAction SilentlyContinue
    ThenError 'is\ not\ empty'
    ThenFilesNotDecompressed 'file2'
    ThenFile 'file1' -HasContent 'AAAAA' -Because 'should not overwrite existing contents'
}

Describe ('Expand-ZipArchive.when ignoring errors') {
    Init
    GivenArchive 'zip.upack' -WithFiles 'file1'
    GivenDirectory $expandToName
    GivenFile (Join-Path -Path $expandToName -ChildPath 'file1') -WithContent 'AAAAA'
    WhenDecompressing 'zip.upack' -ErrorAction Ignore
    ThenNoErrors
}

Describe ('Expand-ZipArchive.when overwriting destination') {
    Init
    GivenArchive 'zip.upack' -WithFiles 'file1'
    GivenDirectory $expandToName
    GivenFile (Join-Path -Path $expandToName -ChildPath 'file1') -WithContent 'AAAAA'
    WhenDecompressing 'zip.upack' -Force
    ThenNoErrors
    ThenFilesDecompressed 'file1'
}