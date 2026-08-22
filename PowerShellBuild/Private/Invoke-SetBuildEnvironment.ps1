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

        Get-BuildVariable decides where the commit message comes from with a switch over the
        environment variable names it recognises. Some branches read a message straight out of a
        variable; the rest run git against a commit SHA held in a variable. This function makes
        the first kind win:

        1. The SHA variables whose branches shell out to git are removed for the duration of the
           call, so none of those branches can be selected. The switch runs over an unordered
           hashtable of variables, so removing them is the only way to make the choice
           deterministic -- setting a competing variable is a coin toss.
        2. The commit message is read here instead. PowerShell drains the pipe while the process
           writes, so reading it cannot deadlock.
        3. That message is published through the Azure Pipelines variable BuildHelpers consumes
           verbatim, and removed again afterwards.

        Nothing else keys off the borrowed variable: the build system, branch, build root, and
        build number are each detected from different variables. The suppressed SHA variables are
        also used to report the commit hash, so the hash BuildHelpers derives from HEAD is
        replaced afterwards with the value the build system supplied.

        See psake/PowerShellBuild#167. The defect is upstream in BuildHelpers, whose last release
        (2.0.16) predates this workaround by five years.

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

    # Every variable whose Get-BuildVariable branch runs 'git log --format=%B -n 1 <sha>'.
    $shaVariableUsingGit = @(
        'CI_COMMIT_SHA'                     # GitLab CI 9.0+
        'CI_BUILD_REF'                      # GitLab CI 8.x
        'GIT_COMMIT'                        # Jenkins
        'BUILD_SOURCEVERSION'               # Azure Pipelines classic release
        'BUILD_VCS_NUMBER'                  # TeamCity
        'BAMBOO_REPOSITORY_REVISION_NUMBER' # Bamboo
        'GITHUB_SHA'                        # GitHub Actions
    )
    $azureCommitMessageVariable = 'Env:BUILD_SOURCEVERSIONMESSAGE'

    $suppressedVariable = @{}
    foreach ($name in $shaVariableUsingGit) {
        $variablePath = "Env:$name"
        if (Test-Path -Path $variablePath) {
            $suppressedVariable[$name] = (Get-Item -Path $variablePath).Value
            Remove-Item -Path $variablePath
        }
    }

    # A build system that publishes the message itself already avoids the git call. Only read the
    # repository when nothing supplied one.
    $ownCommitMessage = $null
    if (-not (Test-Path -Path $azureCommitMessageVariable)) {
        $ownCommitMessage = Get-HeadCommitMessage -Path $Path
    }

    try {
        if ($ownCommitMessage) {
            Set-Item -Path $azureCommitMessageVariable -Value $ownCommitMessage
        }

        BuildHelpers\Set-BuildEnvironment @Parameter

        if ($ownCommitMessage) {
            # The Azure Pipelines branch joins the message onto a single line. Restore the form
            # the git branch produces so the variable looks the way it always has.
            $env:BHCommitMessage = $ownCommitMessage
        }

        # With the SHA variables hidden, BuildHelpers falls back to HEAD for the commit hash.
        # That is the same commit every build system checks out, but report what the build system
        # actually said. Only one CI system's variables are ever present at once; if that ever
        # stops being true, leave the value BuildHelpers derived rather than guess between them.
        if ($suppressedVariable.Count -eq 1) {
            $env:BHCommitHash = $suppressedVariable.Values | Select-Object -First 1
        }
    } finally {
        if ($ownCommitMessage) {
            Remove-Item -Path $azureCommitMessageVariable -ErrorAction SilentlyContinue
        }
        foreach ($name in $suppressedVariable.Keys) {
            Set-Item -Path "Env:$name" -Value $suppressedVariable[$name]
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
