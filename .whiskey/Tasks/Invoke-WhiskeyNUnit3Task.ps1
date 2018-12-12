
function Invoke-WhiskeyNUnit3Task
{
    [CmdletBinding()]
    [Whiskey.Task("NUnit3",SupportsClean=$true,SupportsInitialize=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $nunitPackage = 'NUnit.ConsoleRunner'
    # Due to a bug in NuGet we can't search for and install packages with wildcards (e.g. 3.*), so we're hardcoding a version for now. See Resolve-WhiskeyNuGetPackageVersion for more details.
    $nunitVersion = '3.7.0'
    if( $TaskParameter['Version'] )
    {
        $nunitVersion = $TaskParameter['Version']
        if( $nunitVersion -notlike '3.*' )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Version' -Message ('The version ''{0}'' isn''t a valid 3.x version of NUnit.' -f $TaskParameter['Version'])
            return
        }
    }

    $nunitReport = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('nunit3+{0}.xml' -f [IO.Path]::GetRandomFileName())
    $nunitReportParam = '--result={0}' -f $nunitReport

    $openCoverVersionParam = @{}
    if ($TaskParameter['OpenCoverVersion'])
    {
        $openCoverVersionParam['Version'] = $TaskParameter['OpenCoverVersion']
    }

    $reportGeneratorVersionParam = @{}
    if ($TaskParameter['ReportGeneratorVersion'])
    {
        $reportGeneratorVersionParam['Version'] = $TaskParameter['ReportGeneratorVersion']
    }

    if( $TaskContext.ShouldClean )
    {
        Uninstall-WhiskeyTool -NuGetPackageName $nunitPackage -BuildRoot $TaskContext.BuildRoot -Version $nunitVersion
        Uninstall-WhiskeyTool -NuGetPackageName 'OpenCover' -BuildRoot $TaskContext.BuildRoot @openCoverVersionParam
        Uninstall-WhiskeyTool -NuGetPackageName 'ReportGenerator' -BuildRoot $TaskContext.BuildRoot @reportGeneratorVersionParam
        return
    }

    $nunitPath = Install-WhiskeyTool -NuGetPackageName $nunitPackage -Version $nunitVersion -DownloadRoot $TaskContext.BuildRoot
    if (-not $nunitPath)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Package "{0}" failed to install.' -f $nunitPackage)
        return
    }

    $openCoverPath = Install-WhiskeyTool -NuGetPackageName 'OpenCover' -DownloadRoot $TaskContext.BuildRoot @openCoverVersionParam
    if (-not $openCoverPath)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Package "OpenCover" failed to install.'
        return
    }

    $reportGeneratorPath = Install-WhiskeyTool -NuGetPackageName 'ReportGenerator' -DownloadRoot $TaskContext.BuildRoot @reportGeneratorVersionParam
    if (-not $reportGeneratorPath)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Package "ReportGenerator" failed to install.'
        return
    }

    if( $TaskContext.ShouldInitialize )
    {
        return
    }

    $openCoverArgument = @()
    if ($TaskParameter['OpenCoverArgument'])
    {
        $openCoverArgument = $TaskParameter['OpenCoverArgument']
    }

    $reportGeneratorArgument = @()
    if ($TaskParameter['ReportGeneratorArgument'])
    {
        $reportGeneratorArgument = $TaskParameter['ReportGeneratorArgument']
    }

    $framework = '4.0'
    if ($TaskParameter['Framework'])
    {
        $framework = $TaskParameter['Framework']
    }
    $frameworkParam = '--framework={0}' -f $framework

    $testFilter = ''
    $testFilterParam = ''
    if ($TaskParameter['TestFilter'])
    {
        $testFilter = $TaskParameter['TestFilter'] | ForEach-Object { '({0})' -f $_ }
        $testFilter = $testFilter -join ' or '
        $testFilterParam = '--where={0}' -f $testFilter
    }

    $nunitExtraArgument = ''
    if ($TaskParameter['Argument'])
    {
        $nunitExtraArgument = $TaskParameter['Argument']
    }

    $disableCodeCoverage = $TaskParameter['DisableCodeCoverage'] | ConvertFrom-WhiskeyYamlScalar

    $coverageFilter = ''
    if ($TaskParameter['CoverageFilter'])
    {
        $coverageFilter = $TaskParameter['CoverageFilter'] -join ' '
    }

    $nunitConsolePath = Get-ChildItem -Path $nunitPath -Filter 'nunit3-console.exe' -Recurse |
                            Select-Object -First 1 |
                            Select-Object -ExpandProperty 'FullName'

    if( -not $nunitConsolePath )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unable to find "nunit3-console.exe" in NUnit3 NuGet package at "{0}".' -f $nunitPath)
        return
    }


    $openCoverConsolePath = Get-ChildItem -Path $openCoverPath -Filter 'OpenCover.Console.exe' -Recurse |
                                Select-Object -First 1 |
                                Select-Object -ExpandProperty 'FullName'

    if( -not $openCoverConsolePath )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unable to find "OpenCover.Console.exe" in OpenCover NuGet package at "{0}".' -f $openCoverPath)
        return
    }


    $reportGeneratorConsolePath = Get-ChildItem -Path $reportGeneratorPath -Filter 'ReportGenerator.exe' -Recurse |
                                      Select-Object -First 1 |
                                      Select-Object -ExpandProperty 'FullName'

    if( -not $reportGeneratorConsolePath )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unable to find "ReportGenerator.exe" in ReportGenerator NuGet package at "{0}".' -f $reportGeneratorPath)
        return
    }

    if (-not $TaskParameter['Path'])
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Path'' is mandatory. It should be one or more paths to the assemblies whose tests should be run, e.g.

            Build:
            - NUnit3:
                Path:
                - Assembly.dll
                - OtherAssembly.dll

        ')
        return
    }

    $path = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    $path | Foreach-Object {
        if (-not (Test-Path -Path $_ -PathType Leaf))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('''Path'' item ''{0}'' does not exist.' -f $_)
            return
        }
    }

    $coverageReportDir = Join-Path -Path $TaskContext.outputDirectory -ChildPath "opencover"
    New-Item -Path $coverageReportDir -ItemType 'Directory' -Force | Out-Null
    $openCoverReport = Join-Path -Path $coverageReportDir -ChildPath 'openCover.xml'

    $separator = '{0}VERBOSE:                       ' -f [Environment]::NewLine
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Path                {0}' -f ($Path -join $separator))
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Framework           {0}' -f $framework)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  TestFilter          {0}' -f $testFilter)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Argument            {0}' -f ($nunitExtraArgument -join $separator))
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  NUnit Report        {0}' -f $nunitReport)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  CoverageFilter      {0}' -f $coverageFilter)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  OpenCover Report    {0}' -f $openCoverReport)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  DisableCodeCoverage {0}' -f $disableCodeCoverage)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  OpenCoverArgs       {0}' -f ($openCoverArgument -join ' '))
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  ReportGeneratorArgs {0}' -f ($reportGeneratorArgument -join ' '))

    $nunitExitCode = 0
    $reportGeneratorExitCode = 0
    $openCoverExitCode = 0
    $openCoverExitCodeOffset = 1000

    if (-not $disableCodeCoverage)
    {

        $path = $path | ForEach-Object { '\"{0}\"' -f $_ }
        $path = $path -join ' '

        $nunitReportParam = '\"{0}\"' -f $nunitReportParam

        if ($frameworkParam)
        {
            $frameworkParam = '\"{0}\"' -f $frameworkParam
        }

        if ($testFilterParam)
        {
            $testFilterParam = '\"{0}\"' -f $testFilterParam
        }

        if ($nunitExtraArgument)
        {
            $nunitExtraArgument = $nunitExtraArgument | ForEach-Object { '\"{0}\"' -f $_ }
            $nunitExtraArgument = $nunitExtraArgument -join ' '
        }

        $openCoverNunitArguments = '{0} {1} {2} {3} {4}' -f $path,$frameworkParam,$testFilterParam,$nunitReportParam,$nunitExtraArgument
        & $openCoverConsolePath "-target:$nunitConsolePath" "-targetargs:$openCoverNunitArguments" "-filter:$coverageFilter" "-output:$openCoverReport" -register:user -returntargetcode:$openCoverExitCodeOffset $openCoverArgument

        if ($LASTEXITCODE -ge 745)
        {
            $openCoverExitCode = $LASTEXITCODE - $openCoverExitCodeOffset
        }
        else
        {
            $nunitExitCode = $LASTEXITCODE
        }

        & $reportGeneratorConsolePath "-reports:$openCoverReport" "-targetdir:$coverageReportDir" $reportGeneratorArgument
        $reportGeneratorExitCode = $LASTEXITCODE
    }
    else
    {
        & $nunitConsolePath $path $frameworkParam $testFilterParam $nunitReportParam $nunitExtraArgument
        $nunitExitCode = $LASTEXITCODE

    }

    if ($reportGeneratorExitCode -ne 0)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('ReportGenerator didn''t run successfully. ''{0}'' returned exit code ''{1}''.' -f $reportGeneratorConsolePath,$reportGeneratorExitCode)
        return
    }
    elseif ($openCoverExitCode -ne 0)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('OpenCover didn''t run successfully. ''{0}'' returned exit code ''{1}''.' -f $openCoverConsolePath, $openCoverExitCode)
        return
    }
    elseif ($nunitExitCode -ne 0)
    {
        if (-not (Test-Path -Path $nunitReport -PathType Leaf))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NUnit3 didn''t run successfully. ''{0}'' returned exit code ''{1}''.' -f $nunitConsolePath,$nunitExitCode)
            return
        }
        else
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NUnit3 tests failed. ''{0}'' returned exit code ''{1}''.' -f $nunitConsolePath,$nunitExitCode)
            return
        }
    }
}
