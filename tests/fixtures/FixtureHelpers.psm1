function Copy-PSBuildTestFixture {
    <#
    .SYNOPSIS
        Copy the PSBuildTestFixture module to a destination directory.
    .DESCRIPTION
        Copies the checked-in PSBuildTestFixture module into the supplied destination (typically
        $TestDrive) and returns the path of the copy. Tests must always operate on a copy so that
        no test run ever mutates the checked-in fixture and every test starts from a pristine
        fixture state.
    .PARAMETER Destination
        Directory to copy the fixture into. The copy is created as a PSBuildTestFixture
        subdirectory of this path.
    .EXAMPLE
        PS> $fixturePath = Copy-PSBuildTestFixture -Destination $TestDrive

        Copies the fixture module into the Pester test drive and returns the path of the copy.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Destination
    )

    $fixtureSourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'PSBuildTestFixture'
    $fixtureCopyPath = Join-Path -Path $Destination -ChildPath 'PSBuildTestFixture'

    Copy-Item -Path $fixtureSourcePath -Destination $fixtureCopyPath -Recurse -Force
    $fixtureCopyPath
}

Export-ModuleMember -Function 'Copy-PSBuildTestFixture'
