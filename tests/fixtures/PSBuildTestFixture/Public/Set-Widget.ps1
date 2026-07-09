function Set-Widget {
    <#
    .SYNOPSIS
        Set the quantity of a widget.
    .DESCRIPTION
        Returns a widget object with the supplied name and quantity, as if the widget had been
        updated. This function exists only to give the PowerShellBuild integration tests a second
        public command, including one that supports ShouldProcess.
    .PARAMETER Name
        Name of the widget to update.
    .PARAMETER Quantity
        New number of widget units.
    .EXAMPLE
        PS> Set-Widget -Name 'Sprocket' -Quantity 3

        Sets the Sprocket widget quantity to 3 and returns the updated widget object.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1000)]
        [int]
        $Quantity
    )

    if (-not (Test-WidgetName -Name $Name)) {
        throw "Invalid widget name [$Name]"
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Set widget quantity')) {
        [PSCustomObject]@{
            Name     = $Name
            Quantity = $Quantity
        }
    }
}
