function Invoke-SetBuildEnvironment {
    <#
    .SYNOPSIS
        Calls BuildHelpers\Set-BuildEnvironment without tripping its Invoke-Git deadlock.
    .DESCRIPTION
        BuildHelpers' Invoke-Git redirects git's output streams and then calls WaitForExit()
        before reading them. When git writes more than the pipe buffer holds, git blocks waiting
        for the pipe to drain while BuildHelpers blocks waiting for git to exit, and the build
        hangs with no output and no timeout. The payload large enough to trigger it is the HEAD
        commit message, which Get-BuildVariable reads with 'git log --format=%B -n 1'. Windows
        has the smaller pipe buffer, so it hangs there first.

        Get-BuildVariable only shells out for the commit message when it cannot read one from a
        known CI variable. This function reads the message itself -- PowerShell drains the pipe
        while the process writes, so it cannot deadlock -- and publishes it through the one
        variable BuildHelpers consumes verbatim, so BuildHelpers never runs the git command that
        hangs. The variable is removed again afterwards.

        See psake/PowerShellBuild#167. The defect is upstream in BuildHelpers, whose last release
        (2.0.16) predates this workaround by several years.

        This file is dot-sourced by build.properties.ps1 and by this repository's own build.ps1
        as well as being loaded with the module, so it must stay self-contained: no localized
        strings and no calls to other PowerShellBuild functions.
    .PARAMETER Parameter
        Parameters to splat onto Set-BuildEnvironment, for example @{ BuildOutput = $path;
        Force = $true }.
    .PARAMETER Path
        Repository to read the commit message from. Defaults to the current location, which is
        what Set-BuildEnvironment itself inspects when no path is supplied.
    .EXAMPLE
        PS> Invoke-SetBuildEnvironment -Parameter @{ Force = $true }

        Populate the BH* environment variables for the current location.
    #>
    [CmdletBinding()]
    param(
        [hashtable]
        $Parameter = @{},

        [string]
        $Path = $PWD.Path
    )

    # Azure Pipelines publishes the commit message in this variable, and Get-BuildVariable reads
    # it directly instead of calling git. Nothing else keys off it: the build system, branch,
    # commit hash, and build number are each detected from different variables, so borrowing this
    # one does not make BuildHelpers report an Azure Pipelines build.
    $commitMessageVariable = 'Env:BUILD_SOURCEVERSIONMESSAGE'

    $commitMessage = $null
    # A real Azure Pipelines build already supplies the variable. Leave it alone -- BuildHelpers
    # will use it and never reach the git call.
    if (-not (Test-Path -Path $commitMessageVariable)) {
        $commitMessage = Get-HeadCommitMessage -Path $Path
    }

    try {
        if ($commitMessage) {
            Set-Item -Path $commitMessageVariable -Value $commitMessage
        }

        BuildHelpers\Set-BuildEnvironment @Parameter

        if ($commitMessage) {
            # The Azure Pipelines path joins the message onto a single line. Restore the form the
            # git path produces so the variable looks the same as it always has.
            $env:BHCommitMessage = $commitMessage
        }
    } finally {
        if ($commitMessage) {
            Remove-Item -Path $commitMessageVariable -ErrorAction SilentlyContinue
        }
    }
}

function Get-HeadCommitMessage {
    <#
    .SYNOPSIS
        Reads the HEAD commit message the way BuildHelpers would, without the deadlock.
    .DESCRIPTION
        Returns the HEAD commit message normalized exactly as Get-BuildVariable normalizes it:
        blank lines dropped, each remaining line trimmed, joined with newlines. Returns nothing
        when git is unavailable, the path is not a repository, or the repository has no commits,
        which are the same conditions under which BuildHelpers skips its own git call.
    .PARAMETER Path
        Repository to read from.
    .EXAMPLE
        PS> Get-HeadCommitMessage -Path $PWD.Path

        Return the current commit message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]
        $Path = $PWD.Path
    )

    $gitCommand = Get-Command -Name 'git' -CommandType 'Application' -ErrorAction 'SilentlyContinue'
    if (-not $gitCommand) {
        return
    }

    # Matches the check BuildHelpers makes before using git. A worktree's .git is a file rather
    # than a directory, which Test-Path accepts either way.
    if (-not (Test-Path -Path ([IO.Path]::Combine($Path, '.git')))) {
        return
    }

    $messageLines = & $gitCommand[0].Path -C $Path log --format=%B -n 1 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $messageLines) {
        return
    }

    ($messageLines.Where({ $_ }).ForEach({ $_.Trim() })) -join "`n"
}
