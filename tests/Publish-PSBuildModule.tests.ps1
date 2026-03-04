Describe 'Publish-PSBuildModule' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module ([IO.Path]::Combine($script:moduleRoot, 'PowerShellBuild', 'PowerShellBuild.psd1')) -Force
    }

    It 'Should exist and be exported' {
        Get-Command Publish-PSBuildModule -Module PowerShellBuild -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Requires Path parameter' {
        $command = Get-Command Publish-PSBuildModule
        $command.Parameters['Path'].Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' }).Mandatory |
            Should -Contain $true
    }

    It 'Requires Version parameter' {
        $command = Get-Command Publish-PSBuildModule
        $command.Parameters['Version'].Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' }).Mandatory |
            Should -Contain $true
    }

    It 'Requires Repository parameter' {
        $command = Get-Command Publish-PSBuildModule
        $command.Parameters['Repository'].Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' }).Mandatory |
            Should -Contain $true
    }

    It 'Throws when Path does not exist' {
        $missingPath = Join-Path -Path $TestDrive -ChildPath 'does-not-exist'

        { Publish-PSBuildModule -Path $missingPath -Version '1.0.0' -Repository 'PSGallery' } |
            Should -Throw
    }

    It 'Throws when Path is a file instead of a directory' {
        $filePath = Join-Path -Path $TestDrive -ChildPath 'module.psm1'
        New-Item -Path $filePath -ItemType File -Force | Out-Null

        { Publish-PSBuildModule -Path $filePath -Version '1.0.0' -Repository 'PSGallery' } |
            Should -Throw
    }

    It 'Passes NuGetApiKey to Publish-Module when provided' {
        $modulePath = Join-Path -Path $TestDrive -ChildPath 'MyModule'
        New-Item -Path $modulePath -ItemType Directory -Force | Out-Null

        Mock Publish-Module {}

        Publish-PSBuildModule -Path $modulePath -Version '1.0.0' -Repository 'PSGallery' -NuGetApiKey 'abc123'

        Should -Invoke Publish-Module -Times 1 -Exactly -ParameterFilter {
            $Path -eq $modulePath -and
            $Repository -eq 'PSGallery' -and
            $NuGetApiKey -eq 'abc123'
        }
    }

    It 'Passes Credential to Publish-Module when provided' {
        $modulePath = Join-Path -Path $TestDrive -ChildPath 'MyModuleWithCred'
        New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
        $securePassword = ConvertTo-SecureString -String 'pw' -AsPlainText -Force
        $credential = [PSCredential]::new('user', $securePassword)

        Mock Publish-Module {}

        Publish-PSBuildModule -Path $modulePath -Version '1.0.0' -Repository 'PSGallery' -Credential $credential

        Should -Invoke Publish-Module -Times 1 -Exactly -ParameterFilter {
            $Path -eq $modulePath -and
            $Repository -eq 'PSGallery' -and
            $Credential.UserName -eq 'user'
        }
    }
}
