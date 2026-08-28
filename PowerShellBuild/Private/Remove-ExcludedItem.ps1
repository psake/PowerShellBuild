function Remove-ExcludedItem {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [cmdletbinding()]
    [OutputType([IO.FileSystemInfo[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('PSPath', 'FullName')]
        [AllowEmptyCollection()]
        [IO.FileSystemInfo[]]$InputObject,

        [string[]]$Exclude
    )

    begin {
        $keepers = [Collections.Generic.List[IO.FileSystemInfo]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            # A labeled break used to skip an excluded item here. On Windows PowerShell 5.1 that
            # break escapes this function instead of ending the loop it names, and an escaping
            # break aborts whatever loop the caller happened to be running, silently and with no
            # error. Pester reports it as "a 'break' or 'continue' statement with a label that
            # does not match any enclosing loop escaped from your code". A flag keeps all flow
            # control inside this function.
            #
            # The labeled break was also aimed at the wrong loop: it ended the loop over
            # $InputObject rather than skipping the one excluded item, so a caller that passed a
            # collection through -InputObject lost every item after the first excluded one.
            $isExcluded = $false
            foreach ($regex in $Exclude) {
                if ($item -match $regex) {
                    $isExcluded = $true
                    break
                }
            }

            if (-not $isExcluded) {
                $keepers.Add($item)
            }
        }
    }

    end {
        $keepers
    }
}
