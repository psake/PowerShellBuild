function Test-WidgetName {
    <#
    .SYNOPSIS
        Validate a widget name.
    .DESCRIPTION
        Returns $true when the widget name contains only letters, digits, and hyphens. This private
        helper exists so the integration tests can assert that private functions are dot-sourced
        into compiled output but never exported.
    .PARAMETER Name
        Widget name to validate.
    .EXAMPLE
        PS> Test-WidgetName -Name 'Sprocket'

        Returns $true.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    $Name -match '^[A-Za-z0-9-]+$'
}
