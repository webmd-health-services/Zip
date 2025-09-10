
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'
}

Describe 'Zip' {
    It 'imports without errors' {
        if ((Get-Module -Name 'Zip'))
        {
            Remove-Module -Name 'Zip'
        }

        $functionsDirPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Zip\Functions'
        if (-not (Get-ChildItem -path $functionsDirPath))
        {
            Remove-Item -Path $functionsDirPath
        }

        $Global:Error.Clear()
        { Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Zip' -Resolve) -ErrorAction Stop } |
            Should -Not -Throw
        $Global:Error | Should -BeNullOrEmpty
    }
}