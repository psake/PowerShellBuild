InModuleScope TestModule {
    describe 'MyModule' {
        context 'Private' {
            it 'Can test a private module' {
                (GetHelloWorld) | Should -BeExactly 'Hello world'
            }
        }
    }
}
