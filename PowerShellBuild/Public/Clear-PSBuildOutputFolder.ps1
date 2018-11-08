function Clear-PSBuildOutputFolder {
    <#
    .SYNOPSIS
        Clears module output directory.
    .DESCRIPTION
        Clears module output directory.
    .PARAMETER Path
        Module output path to remove.
    .EXAMPLE
        PS> Clear-PSBuildOutputFolder -Path ./Output/MyModule/0.1.0

        Removes the './Output/MyModule/0.1.0' directory.
    #>
    [CmdletBinding()]
    param(
        # Maybe a bit paranoid but this task nuked \ on my laptop. Good thing I was not running as admin.
        [parameter(Mandatory)]
        [ValidateScript({
            if ($_.Length -le 3) {
                throw "`$Path [$_] must be longer than 3 characters."
            }
            $true
        })]
        [string]$Path
    )

    if (Test-Path -Path $Path) {
        Remove-Item -Path $Path -Recurse -Force -Verbose:$false
    }
}
