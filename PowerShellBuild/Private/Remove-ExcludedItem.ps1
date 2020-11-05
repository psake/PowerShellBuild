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
        :item
        foreach ($item in $InputObject) {
            foreach ($regex in $Exclude) {
                if ($_ -match $regex) {
                    break item
                }
            }
            $keepers.Add($_)
        }
    }

    end {
        $keepers
    }
}
