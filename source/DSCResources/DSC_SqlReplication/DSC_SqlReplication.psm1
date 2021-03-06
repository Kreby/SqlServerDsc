$script:sqlServerDscHelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Modules\SqlServerDsc.Common'
$script:resourceHelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Modules\DscResource.Common'

Import-Module -Name $script:sqlServerDscHelperModulePath
Import-Module -Name $script:resourceHelperModulePath

$script:localizedData = Get-LocalizedData -DefaultUICulture 'en-US'

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Local', 'Remote')]
        [System.String]
        $DistributorMode,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $AdminLinkCredentials,

        [Parameter()]
        [System.String]
        $DistributionDBName = 'distribution',

        [Parameter()]
        [System.String]
        $RemoteDistributor,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WorkingDirectory,

        [Parameter()]
        [System.Boolean]
        $UseTrustedConnection = $true,

        [Parameter()]
        [System.Boolean]
        $UninstallWithForce = $true
    )

    Write-Verbose -Message (
        $script:localizedData.GetCurrentState -f $InstanceName
    )

    $sqlMajorVersion = Get-SqlServerMajorVersion -InstanceName $InstanceName
    $localSqlName = Get-SqlLocalServerName -InstanceName $InstanceName

    $localServerConnection = New-ServerConnection -SqlMajorVersion $sqlMajorVersion -SqlServerName $localSqlName
    $localReplicationServer = New-ReplicationServer -SqlMajorVersion $sqlMajorVersion -ServerConnection $localServerConnection

    $currentEnsure = 'Present'

    if ($localReplicationServer.IsDistributor -eq $true)
    {
        $currentDistributorMode = 'Local'
    }
    elseif ($localReplicationServer.IsPublisher -eq $true)
    {
        $currentDistributorMode = 'Remote'
    }
    else
    {
        $currentEnsure = 'Absent'
    }

    if ($currentEnsure -eq 'Present')
    {
        Write-Verbose -Message (
            $script:localizedData.DistributorMode -f $DistributorMode, $InstanceName
        )

        $currentDistributionDBName = $localReplicationServer.DistributionDatabase
        $currentRemoteDistributor = $localReplicationServer.DistributionServer
        $currentWorkingDirectory = $localReplicationServer.WorkingDirectory
    }
    else
    {
        Write-Verbose -Message (
            $script:localizedData.NoDistributorMode -f $InstanceName
        )
    }

    $returnValue = @{
        InstanceName       = $InstanceName
        Ensure             = $currentEnsure
        DistributorMode    = $currentDistributorMode
        DistributionDBName = $currentDistributionDBName
        RemoteDistributor  = $currentRemoteDistributor
        WorkingDirectory   = $currentWorkingDirectory
    }

    return $returnValue
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Local', 'Remote')]
        [System.String]
        $DistributorMode,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $AdminLinkCredentials,

        [Parameter()]
        [System.String]
        $DistributionDBName = 'distribution',

        [Parameter()]
        [System.String]
        $RemoteDistributor,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WorkingDirectory,

        [Parameter()]
        [System.Boolean]
        $UseTrustedConnection = $true,

        [Parameter()]
        [System.Boolean]
        $UninstallWithForce = $true
    )

    if (($DistributorMode -eq 'Remote') -and (-not $RemoteDistributor))
    {
        $errorMessage = $script:localizedData.NoRemoteDistributor
        New-InvalidArgumentException -ArgumentName 'RemoteDistributor' -Message $errorMessage
    }

    $sqlMajorVersion = Get-SqlServerMajorVersion -InstanceName $InstanceName
    $localSqlName = Get-SqlLocalServerName -InstanceName $InstanceName

    $localServerConnection = New-ServerConnection -SqlMajorVersion $sqlMajorVersion -SqlServerName $localSqlName
    $localReplicationServer = New-ReplicationServer -SqlMajorVersion $sqlMajorVersion -ServerConnection $localServerConnection

    if ($Ensure -eq 'Present')
    {
        if ($DistributorMode -eq 'Local' -and $localReplicationServer.IsDistributor -eq $false)
        {
            Write-Verbose -Message (
                $script:localizedData.ConfigureLocalDistributor
            )

            $distributionDB = New-DistributionDatabase `
                -SqlMajorVersion $sqlMajorVersion `
                -DistributionDBName $DistributionDBName `
                -ServerConnection $localServerConnection

            Install-LocalDistributor `
                -ReplicationServer $localReplicationServer `
                -AdminLinkCredentials $AdminLinkCredentials `
                -DistributionDB $distributionDB

            Register-DistributorPublisher `
                -SqlMajorVersion $sqlMajorVersion `
                -PublisherName $localSqlName `
                -ServerConnection $localServerConnection `
                -DistributionDBName $DistributionDBName `
                -WorkingDirectory $WorkingDirectory `
                -UseTrustedConnection $UseTrustedConnection
        }

        if ($DistributorMode -eq 'Remote' -and $localReplicationServer.IsPublisher -eq $false)
        {
            Write-Verbose -Message (
                $script:localizedData.ConfigureRemoteDistributor
            )

            $remoteConnection = New-ServerConnection -SqlMajorVersion $sqlMajorVersion -SqlServerName $RemoteDistributor

            Register-DistributorPublisher `
                -SqlMajorVersion $sqlMajorVersion `
                -PublisherName $localSqlName `
                -ServerConnection $remoteConnection `
                -DistributionDBName $DistributionDBName `
                -WorkingDirectory $WorkingDirectory `
                -UseTrustedConnection $UseTrustedConnection

            Install-RemoteDistributor `
                -ReplicationServer $localReplicationServer `
                -RemoteDistributor $RemoteDistributor `
                -AdminLinkCredentials $AdminLinkCredentials
        }
    }
    else #'Absent'
    {
        if ($localReplicationServer.IsDistributor -eq $true -or $localReplicationServer.IsPublisher -eq $true)
        {
            Write-Verbose -Message (
                $script:localizedData.RemoveDistributor
            )

            Uninstall-Distributor -ReplicationServer $localReplicationServer -UninstallWithForce $UninstallWithForce
        }
        else
        {
            Write-Verbose -Message (
                $script:localizedData.NoDistributorMode -f $InstanceName
            )
        }
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Local', 'Remote')]
        [System.String]
        $DistributorMode,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $AdminLinkCredentials,

        [Parameter()]
        [System.String]
        $DistributionDBName = 'distribution',

        [Parameter()]
        [System.String]
        $RemoteDistributor,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WorkingDirectory,

        [Parameter()]
        [System.Boolean]
        $UseTrustedConnection = $true,

        [Parameter()]
        [System.Boolean]
        $UninstallWithForce = $true
    )

    Write-Verbose -Message (
        $script:localizedData.TestingConfiguration
    )

    $result = $false
    $state = Get-TargetResource @PSBoundParameters

    if ($Ensure -eq 'Absent' -and $state.Ensure -eq 'Absent')
    {
        $result = $true
    }
    elseif ($Ensure -eq 'Present' -and $state.Ensure -eq 'Present' -and $state.DistributorMode -eq $DistributorMode)
    {
        $result = $true
    }

    return $result
}

function New-ServerConnection
{
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SqlMajorVersion,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SqlServerName
    )

    $connInfo = Get-ConnectionInfoAssembly -SqlMajorVersion $SqlMajorVersion
    $serverConnection = New-Object $connInfo.GetType('Microsoft.SqlServer.Management.Common.ServerConnection') $SqlServerName

    return $serverConnection
}

function New-ReplicationServer
{
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SqlMajorVersion,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $ServerConnection
    )

    $rmo = Get-RmoAssembly -SqlMajorVersion $SqlMajorVersion
    $localReplicationServer = New-Object $rmo.GetType('Microsoft.SqlServer.Replication.ReplicationServer') $ServerConnection

    return $localReplicationServer;
}

function New-DistributionDatabase
{
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SqlMajorVersion,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DistributionDBName,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $ServerConnection
    )

    $rmo = Get-RmoAssembly -SqlMajorVersion $SqlMajorVersion

    Write-Verbose -Message (
        $script:localizedData.CreateDistributionDatabase -f $DistributionDBName
    )

    $distributionDB = New-Object $rmo.GetType('Microsoft.SqlServer.Replication.DistributionDatabase') $DistributionDBName, $ServerConnection

    return $distributionDB
}

function New-DistributionPublisher
{
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SqlMajorVersion,

        [Parameter(Mandatory = $true)]
        [System.String]
        $PublisherName,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $ServerConnection
    )

    $rmo = Get-RmoAssembly -SqlMajorVersion $SqlMajorVersion

    try
    {
        $distributorPublisher = New-object $rmo.GetType('Microsoft.SqlServer.Replication.DistributionPublisher') $PublisherName, $ServerConnection
    }
    catch
    {
        $errorMessage = $script:localizedData.FailedInFunction -f 'New-DistributionPublisher'

        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }

    return $distributorPublisher
}

function Install-RemoteDistributor
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ReplicationServer,

        [Parameter(Mandatory = $true)]
        [System.String]
        $RemoteDistributor,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $AdminLinkCredentials
    )

    Write-Verbose -Message (
        $script:localizedData.InstallRemoteDistributor -f $RemoteDistributor
    )

    try
    {
        $ReplicationServer.InstallDistributor($RemoteDistributor, $AdminLinkCredentials.Password)
    }
    catch
    {
        $errorMessage = $script:localizedData.FailedInFunction -f 'Install-RemoteDistributor'

        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }
}

function Install-LocalDistributor
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ReplicationServer,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $AdminLinkCredentials,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $DistributionDB
    )

    Write-Verbose -Message (
        $script:localizedData.InstallLocalDistributor
    )

    try
    {
        $ReplicationServer.InstallDistributor($AdminLinkCredentials.Password, $DistributionDB)
    }
    catch
    {
        $errorMessage = $script:localizedData.FailedInFunction -f 'Install-LocalDistributor'

        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }
}

function Uninstall-Distributor
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ReplicationServer,

        [Parameter(Mandatory = $true)]
        [System.Boolean]
        $UninstallWithForce
    )

    Write-Verbose -Message (
        $script:localizedData.UninstallDistributor
    )

    try
    {
        $ReplicationServer.UninstallDistributor($UninstallWithForce)
    }
    catch
    {
        $errorMessage = $script:localizedData.FailedInFunction -f 'Uninstall-Distributor'

        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }
}

function Register-DistributorPublisher
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SqlMajorVersion,

        [Parameter(Mandatory = $true)]
        [System.String]
        $PublisherName,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $ServerConnection,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DistributionDBName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [System.Boolean]
        $UseTrustedConnection
    )

    Write-Verbose -Message (
        $script:localizedData.CreateDistributorPublisher -f $PublisherName, $ServerConnection.ServerInstance
    )

    $distributorPublisher = New-DistributionPublisher `
        -SqlMajorVersion $SqlMajorVersion `
        -PublisherName $PublisherName `
        -ServerConnection $ServerConnection

    $distributorPublisher.DistributionDatabase = $DistributionDBName
    $distributorPublisher.WorkingDirectory = $WorkingDirectory
    $distributorPublisher.PublisherSecurity.WindowsAuthentication = $UseTrustedConnection

    try
    {
        $distributorPublisher.Create()
    }
    catch
    {
        $errorMessage = $script:localizedData.FailedInFunction -f 'Register-DistributorPublisher'

        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }
}

<#
    .SYNOPSIS
        Returns a reference to the ConnectionInfo assembly.

    .DESCRIPTION
        Returns a reference to the ConnectionInfo assembly.

    .PARAMETER SqlMajorVersion
        Specifies the major version of the SQL Server instance, e.g. '14'.

    .OUTPUTS
        [System.Reflection.Assembly]

        Returns a reference to the ConnectionInfo assembly.

    .EXAMPLE
        Get-ConnectionInfoAssembly -SqlMajorVersion '14'

    .NOTES
        This should normally work using Import-Module and New-Object instead of
        using the method [System.Reflection.Assembly]::Load(). But due to a
        missing assembly in the module SqlServer ('Microsoft.SqlServer.Rmo') we
        cannot use this:

        Import-Module SqlServer
        $connectionInfo = New-Object -TypeName 'Microsoft.SqlServer.Management.Common.ServerConnection' -ArgumentList @('testclu01a\SQL2014')
        # Missing assembly 'Microsoft.SqlServer.Rmo' in module SqlServer prevents this call from working.
        $replication = New-Object -TypeName 'Microsoft.SqlServer.Replication.ReplicationServer' -ArgumentList @($connectionInfo)
#>
function Get-ConnectionInfoAssembly
{
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SqlMajorVersion
    )

    $connectionInfo = Import-Assembly -Name "Microsoft.SqlServer.ConnectionInfo, Version=$SqlMajorVersion.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"

    return $connectionInfo
}

<#
    .SYNOPSIS
        Returns a reference to the RMO assembly.

    .DESCRIPTION
        Returns a reference to the RMO assembly.

    .PARAMETER SqlMajorVersion
        Specifies the major version of the SQL Server instance, e.g. '14'.

    .OUTPUTS
        [System.Reflection.Assembly]

        Returns a reference to the RMO assembly.

    .EXAMPLE
        Get-RmoAssembly -SqlMajorVersion '14'

    .NOTES
        This should normally work using Import-Module and New-Object instead of
        using the method [System.Reflection.Assembly]::Load(). But due to a
        missing assembly in the module SqlServer ('Microsoft.SqlServer.Rmo') we
        cannot use this:

        Import-Module SqlServer
        $connectionInfo = New-Object -TypeName 'Microsoft.SqlServer.Management.Common.ServerConnection' -ArgumentList @('testclu01a\SQL2014')
        # Missing assembly 'Microsoft.SqlServer.Rmo' in module SqlServer prevents this call from working.
        $replication = New-Object -TypeName 'Microsoft.SqlServer.Replication.ReplicationServer' -ArgumentList @($connectionInfo)
#>
function Get-RmoAssembly
{
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SqlMajorVersion
    )

    $rmo = Import-Assembly -Name "Microsoft.SqlServer.Rmo, Version=$SqlMajorVersion.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"

    return $rmo
}

function Get-SqlServerMajorVersion
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName
    )

    $instanceId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$InstanceName
    $sqlVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\Setup").Version

    $sqlMajorVersion = $sqlVersion.Split(".")[0]
    if (-not $sqlMajorVersion)
    {
        $errorMessage = $script:localizedData.FailedToDetectSqlVersion -f $InstanceName

        New-InvalidResultException -Message $errorMessage
    }

    return $sqlMajorVersion
}

function Get-SqlLocalServerName
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName
    )

    if ($InstanceName -eq 'MSSQLSERVER')
    {
        return $env:COMPUTERNAME
    }
    else
    {
        return "$($env:COMPUTERNAME)\$InstanceName"
    }
}

Export-ModuleMember -Function *-TargetResource
