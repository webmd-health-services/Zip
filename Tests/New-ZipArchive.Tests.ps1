
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeDiscovery {
    if (-not (Test-Path -Path 'variable:IsWindows'))
    {
        $script:IsWindows = $true
        $script:IsLinux = $false
        $script:IsMacOS = $false
    }
}

BeforeAll {
    Set-StrictMode -Version 'Latest'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Zip' -Resolve) -Force

    $script:result = $null
    $script:testDirPath = $null
    $script:testNum = 0

    function GivenFile
    {
        param(
            [string[]]
            $Path
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
        }
    }

    function ThenArchive
    {
        param(
            $ExpectedPath,
            [switch] $Not,
            [switch] $Created
        )

        if ($Not)
        {
            Join-Path -Path $script:testDirPath -ChildPath $ExpectedPath | Should -Not -Exist
            return
        }

        $expectedPath = Join-path -Path $script:testDirPath -ChildPath $ExpectedPath
        Test-Path -LiteralPath $expectedPath -PathType Leaf | Should -BeTrue
        $script:result | Should -BeOfType ([IO.FileInfo])
        $expectedPath | Should -Be $script:result.FullName

        $zipExpandPath = Join-Path -Path $script:testDirPath -ChildPath ('zip.{0}' -f [IO.Path]::GetRandomFileName())
        { Expand-Archive -LiteralPath $script:result.FullName -DestinationPath $zipExpandPath } | Should -Not -Throw
    }

    function ThenError
    {
        param(
            $MatchesRegex
        )

        $Global:Error | Should -Match $MatchesRegex
    }

    function ThenNothingReturned
    {
        $script:result | Should -BeNullOrEmpty
    }

    function WhenCreatingArchive
    {
        [CmdletBinding()]
        param(
            $Name,

            [switch] $WithRelativePath,

            [switch] $Force,

            [hashtable] $WithArgs
        )

        $path = Join-Path -Path $script:testDirPath -ChildPath $Name
        if( $WithRelativePath )
        {
            Push-Location $script:testDirPath
            $path = $Name
        }

        if (-not $WithArgs)
        {
            $WithArgs = @{}
        }

        try
        {
            $Global:Error.Clear()
            $script:result = New-ZipArchive -Path $path -Force:$Force @WithArgs
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
}

Describe 'New-ZipArchive' {
    BeforeEach {
        $script:result = $null
        $script:testDirPath = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testDirPath -ItemType Directory
    }

    It 'supports absolute paths' {
        WhenCreatingArchive 'somefile.zip'
        ThenArchive 'somefile.zip' -Created
    }

    It 'supports relative paths' {
        WhenCreatingArchive 'somefile.zip' -WithRelativePath
        ThenArchive 'somefile.zip' -Created
    }

    It 'preserves existing file' {
        GivenFile 'somefile.zip'
        WhenCreatingArchive 'somefile.zip' -ErrorAction SilentlyContinue
        ThenNothingReturned
        ThenError -Matches 'already exists'
    }

    It 'clobbers existing file' {
        GivenFile 'somefile.zip'
        WhenCreatingArchive 'somefile.zip' -Force
        ThenArchive 'somefile.zip' -Created
    }

    It 'rejects when destination is a directory' {
        GivenFile 'dir1.zip/somefile.zip'
        WhenCreatingArchive 'dir1.zip' -Force -ErrorAction SilentlyContinue
        ThenNothingReturned
        ThenError -Matches 'is\ a\ directory'
    }

    It 'supports valid wildcard characters in file name' {
        WhenCreatingArchive 'somefile[1].zip'
        ThenArchive 'somefile[1].zip' -Created
    }

    # Only Windows really has filename character limitations
    It 'rejects invalid wildcard cahracter in file name' -Skip:(-not $IsWindows) {
        $expectedError = 'Illegal characters in path'
        if ($PSVersionTable.PSVersion.Major -ge 6)
        {
            $expectedError = 'The filename, directory name, or volume label syntax is incorrect.'
        }
        WhenCreatingArchive 'somefile*.zip' -ErrorAction SilentlyContinue
        ThenNothingReturned
        ThenError -Matches $expectedError
    }

    It 'supports WhatIf' {
        WhenCreatingArchive 'whatif.zip' -WithArgs @{ WhatIf = $true }
        ThenNothingReturned
        ThenArchive 'whatif.zip' -Not -Created
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'supports WhatIf when archive exists' {
        GivenFile 'whatif2.zip'
        WhenCreatingArchive 'whatif2.zip' -Force -WithArgs @{ WhatIf = $true }
        ThenNothingReturned
        Join-Path -Path $script:testDirPath -ChildPath 'whatif2.zip' | Should -Exist
        $Global:Error | Should -BeNullOrEmpty
    }
}
