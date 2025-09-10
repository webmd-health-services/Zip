# PowerShell 5.1 doesn't have these variables so create them if they don't exist.
if( -not (Get-Variable -Name 'IsLinux' -ErrorAction Ignore) )
{
    $script:IsLinux = $false
    $script:IsMacOS = $false
    $script:IsWindows = $true
}

Add-Type -AssemblyName 'System.IO.Compression'
Add-Type -AssemblyName 'System.IO.Compression.FileSystem'

$functionsDirPath = Join-Path -Path $PSScriptRoot -ChildPath 'Functions'
if (Test-Path -Path $functionsDirPath)
{
    Get-ChildItem -Path $functionsDirPath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}
