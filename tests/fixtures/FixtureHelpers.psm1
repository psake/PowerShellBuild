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

    # Remove any previous copy and recreate the directory before copying the fixture
    # contents. Copying into an existing directory would otherwise nest a second
    # PSBuildTestFixture directory inside it, and the destination (or its parents)
    # may not exist yet.
    if (Test-Path -Path $fixtureCopyPath) {
        Remove-Item -Path $fixtureCopyPath -Recurse -Force
    }
    New-Item -Path $fixtureCopyPath -ItemType Directory -Force > $null
    Copy-Item -Path (Join-Path -Path $fixtureSourcePath -ChildPath '*') -Destination $fixtureCopyPath -Recurse -Force

    $fixtureCopyPath
}

Export-ModuleMember -Function 'Copy-PSBuildTestFixture'
