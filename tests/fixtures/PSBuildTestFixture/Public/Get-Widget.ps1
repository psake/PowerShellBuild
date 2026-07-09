function Get-Widget {
    <#
    .SYNOPSIS
        Get a widget by name.
    .DESCRIPTION
        Returns a widget object with the requested name and quantity. This function exists only to
        give the PowerShellBuild integration tests a public command with complete comment-based
        help, typed parameters, and a private helper dependency.
    .PARAMETER Name
        Name of the widget to return.
    .PARAMETER Quantity
        Number of widget units to report on the returned object. Defaults to 1.
    .EXAMPLE
        PS> Get-Widget -Name 'Sprocket'

        Returns a widget object named Sprocket with a quantity of 1.
    .EXAMPLE
        PS> Get-Widget -Name 'Sprocket' -Quantity 5

        Returns a widget object named Sprocket with a quantity of 5.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]
        $Quantity = 1
    )

    if (-not (Test-WidgetName -Name $Name)) {
        throw "Invalid widget name [$Name]"
    }

    [PSCustomObject]@{
        Name     = $Name
        Quantity = $Quantity
    }
}
