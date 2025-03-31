InModuleScope TestModule {
    Describe 'MyModule' {
        Context 'Private' {
            It 'Can test a private module' {
                (GetHelloWorld) | Should -BeExactly 'Hello world'
            }
        }
    }
}
