
function Expand-ZipArchive
{
    <#
    .SYNOPSIS
    Decompresses a ZIP archive to a directory.

    .DESCRIPTION
    The `Expand-ZipArchive` decompresses a ZIP archive into a directory. Pass the path to the archive to the `Path` parameter. Pass the path to the directory where you want the archive decompressed to the `DestinationPath` parameter. The directory is created for you if it doesn't exist. 

    The destination directory must be empty. If you want to delete any files in the destination directory before decompressing, use the `Force` switch.
    
    .EXAMPLE
    Expand-ZipArchive -Path 'archive.zip' -DestinationPath 'archive'

    Demonstrates how to decompress a ZIP archive. The `archive.zip` file in the current directory is decompressed to an `archive` directory in the current directory.
    
    .EXAMPLE
    Expand-ZipArchive -Path 'archive.zip' -DestinationPath 'archive' -Force

    Demonstrates how to decompress a ZIP archive to an existing, non-empty directory. In this example, the contents of the `archive` directory are deleted before the archie `archive.zip` is decompressed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        # Path to the ZIP archive to decompress.
        $Path,

        [Parameter(Mandatory)]
        [string]
        # The path to the directory where the archive should be expanded.
        $DestinationPath,

        [Switch]
        # Delete the destination directory contents if it already exists.
        $Force
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $Path = Resolve-Path -LiteralPath $Path | Select-Object -ExpandProperty 'ProviderPath'
    if( -not $Path )
    {
        return
    }

    if( -not [IO.Path]::IsPathRooted($DestinationPath) )
    {
        $DestinationPath = [IO.Path]::Combine((Get-Location).Path,$DestinationPath)
    }
    $DestinationPath = [IO.Path]::GetFullPath($DestinationPath)

    if( (Test-Path -LiteralPath $DestinationPath -PathType Container) )
    {
        if( $Force )
        {
            Get-ChildItem -LiteralPath $DestinationPath | Remove-Item -Recurse -Force
        }
        elseif( (Get-ChildItem -LiteralPath $DestinationPath) )
        {
            Write-Error -Message ('Unable to decompress ZIP archive "{0}": the destionation directory "{1}" is not empty.' -f $Path,$DestinationPath) -ErrorAction $ErrorActionPreference
            return
        }
    }

    $errorCount = $Global:Error.Count
    try
    {
        [IO.Compression.ZipFile]::ExtractToDirectory($Path, $DestinationPath)
    }
    catch
    {
        for( $idx = $errorCount; $idx -lt $Global:Error.Count; ++$idx )
        {
            $Global:Error.RemoveAt(0)
        }

        Write-Error -ErrorRecord $_ -ErrorAction $ErrorActionPreference
    }
}
