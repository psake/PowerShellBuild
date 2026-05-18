---
applyTo: '**/*'
description: 'Test writing best practices and conventions'
---

# Testing Instructions

Language-agnostic guidelines for writing effective tests.

## Discovering Existing Test Tooling

Before creating scripts for test-related tasks (running tests, gathering coverage, generating reports):

1. **Check for build systems** - Look for `Makefile`, `build.ps1`, `package.json` scripts, `tox.ini`,
   `pyproject.toml`, or similar build configuration files
2. **Search README and CI configs** - Existing commands are often documented or visible in CI workflows
3. **Ask the user** - If unsure whether tooling exists, ask before creating anything new

**Never create new scripts when existing build tooling already handles the task.**

## Test Structure

### Arrange-Act-Assert (AAA)

Structure each test in three clear sections:

```javascript
// Arrange - Set up test data and preconditions
// Act - Execute the code being tested
// Assert - Verify the expected outcome
```

**Example:**

```javascript
// Arrange
user = createTestUser(name: "Alice", role: "admin")

// Act
result = user.hasPermission("delete")

// Assert
expect(result).toBe(true)
```

### Given-When-Then (BDD Style)

Alternative structure for behavior-focused tests:

```javascript
// Given - Initial context
// When - Action occurs
// Then - Expected outcome
```

## Naming Conventions

### Test Names Should Describe Behavior

**Pattern:** `<unit>_<scenario>_<expectedResult>`

**Good examples:**

```text
calculateTotal_withEmptyCart_returnsZero
userLogin_withInvalidPassword_throwsAuthError
emailValidator_withValidEmail_returnsTrue
```

**Avoid:**

```text
test1
testCalculate
itWorks
```

### Test File Naming

Place test files alongside source files or in a dedicated test directory:

```text
src/
  calculator.js
  calculator.test.js    # Adjacent to source

tests/
  calculator.test.js    # Or in test directory
```

Common extensions:

- `.test.js`, `.test.ts`
- `.spec.js`, `.spec.ts`
- `_test.go`
- `Test.cs`
- `.Tests.ps1`

## Test Types

### Unit Tests

- Test individual functions or methods in isolation
- Mock external dependencies
- Fast execution (milliseconds)
- High coverage of edge cases

### Integration Tests

- Test interaction between components
- May use real databases or services
- Slower than unit tests
- Focus on component boundaries

### End-to-End Tests

- Test complete user workflows
- Use real browser/UI automation
- Slowest to execute
- Cover critical user paths

## Best Practices

### One Assertion Per Concept

Each test should verify one logical concept:

**Good:**

```text
test_addItem_increasesCartCount
test_addItem_updatesCartTotal
```

**Avoid:**

```text
test_addItem_doesEverything  // Tests multiple things
```

### Test Independence

- Each test should run independently
- Don't rely on test execution order
- Clean up test data after each test
- Use fresh fixtures for each test

### Avoid Test Interdependence

**Bad:**

```javascript
test1_createUser()      // Creates user
test2_loginUser()       // Assumes user exists from test1
```

**Good:**

```javascript
test_loginUser() {
    user = createTestUser()   // Each test creates its own data
    // ... test logic
}
```

### Use Descriptive Assertions

**Good:**

```javascript
expect(user.isActive).toBe(true)
expect(result).toContain("success")
expect(list).toHaveLength(3)
```

**Avoid:**

```javascript
expect(x).toBe(true)  // What is x?
assert(result)        // What should result be?
```

## Test Data

### Use Meaningful Test Data

**Good:**

```javascript
email = "valid.user@example.com"
invalidEmail = "not-an-email"
```

**Avoid:**

```javascript
email = "test"
x = "asdf"
```

### Use Factories or Builders

Create helper functions for test data:

```javascript
function createTestUser(overrides = {}) {
    return {
        id: generateId(),
        name: "Test User",
        email: "test@example.com",
        role: "user",
        ...overrides
    }
}

// Usage
adminUser = createTestUser({ role: "admin" })
```

### Edge Cases to Consider

- Empty inputs (null, undefined, empty string, empty array)
- Boundary values (0, -1, max int, min int)
- Invalid inputs (wrong type, malformed data)
- Large inputs (performance edge cases)
- Special characters and unicode
- Concurrent access (race conditions)

## Mocking and Stubbing

### When to Mock

- External services (APIs, databases)
- Time-dependent operations
- Random number generation
- File system operations
- Network requests

### When Not to Mock

- Simple value objects
- Pure functions with no side effects
- The code you're actually testing

### Mock Guidelines

- Only mock what you need
- Verify mock interactions when behavior matters
- Reset mocks between tests
- Prefer dependency injection for easier mocking

## Test Coverage

### Focus on Critical Paths

Prioritize testing:

1. Business-critical functionality
2. Error handling and edge cases
3. Security-sensitive code
4. Complex algorithms

### Coverage Goals

- Aim for meaningful coverage, not 100%
- High coverage doesn't guarantee quality
- Focus on testing behavior, not implementation details

## Bug Fix Testing

### Test-First Bug Fixing

When fixing a bug, always follow this workflow:

1. **Write a failing test first** - Create at least one test that reproduces the bug
2. **Verify the test fails** - Confirm the test fails for the expected reason
3. **Fix the bug** - Implement the minimal fix to make the test pass
4. **Verify all tests pass** - Ensure both the new test and existing tests pass

**Example workflow:**

```text
# 1. Create test that exposes the bug
test_calculateDiscount_withZeroQuantity_returnsZero()
    # This test fails because of the bug

# 2. Run tests - confirm failure
> npm test
FAIL: calculateDiscount returns NaN instead of 0

# 3. Fix the bug in the source code

# 4. Run tests - confirm fix
> npm test
PASS: All tests passing
```

### Why Test-First Matters

- **Proves the bug exists** - The failing test documents the exact issue
- **Prevents regressions** - The test ensures the bug won't return
- **Validates the fix** - You know the fix works when the test passes
- **Documents behavior** - Future developers understand the expected behavior

### Bug Test Naming

Name bug-related tests to indicate the scenario being fixed:

```text
calculateTotal_withNullItems_returnsZeroInsteadOfCrashing
parseDate_withLeapYear_handlesFebruary29Correctly
userAuth_withExpiredToken_returnsUnauthorizedNotServerError
```

## Running Tests

### Before Committing

- Run related tests locally
- Ensure all tests pass
- Add tests for new functionality
- Update tests for changed behavior

### Continuous Integration

- Tests should run on every PR
- Failed tests should block merging
- Keep test suite fast (parallelize when possible)

## Anti-Patterns to Avoid

| Anti-Pattern            | Problem            | Solution                      |
| ----------------------- | ------------------ | ----------------------------- |
| Testing implementation  | Brittle tests      | Test behavior/outcomes        |
| Flaky tests             | Unreliable CI      | Fix timing/ordering issues    |
| Slow tests              | Developer friction | Optimize or parallelize       |
| No assertions           | False confidence   | Always verify outcomes        |
| Commented-out tests     | Hidden failures    | Delete or fix tests           |
| Test data in production | Security risk      | Use separate test environment |
