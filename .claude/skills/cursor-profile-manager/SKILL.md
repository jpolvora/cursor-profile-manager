```markdown
# cursor-profile-manager Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches you the core development patterns and conventions used in the `cursor-profile-manager` Python codebase. You'll learn how to structure files, write imports and exports, follow commit conventions, and implement and test features in a consistent, maintainable way.

## Coding Conventions

### File Naming
- Use **PascalCase** for all file names.
  - Example: `UserProfileManager.py`, `ProfileSettings.py`

### Import Style
- Use **relative imports** within the package.
  - Example:
    ```python
    from .UserProfileManager import UserProfileManager
    from .ProfileSettings import ProfileSettings
    ```

### Export Style
- Use **named exports** by explicitly listing classes or functions in `__all__`.
  - Example:
    ```python
    __all__ = ["UserProfileManager", "ProfileSettings"]
    ```

### Commit Patterns
- Mixed commit types, with prefixes like `docs` and `feat`.
- Commit messages are concise, averaging ~58 characters.
  - Example:
    ```
    feat: add support for multiple profile types
    docs: update README with usage examples
    ```

## Workflows

### Feature Implementation
**Trigger:** When adding a new feature  
**Command:** `/feature-implementation`

1. Create a new PascalCase Python file for the feature.
2. Implement the feature using relative imports as needed.
3. Add the new class or function to the module's `__all__` list.
4. Write or update tests in a corresponding `*.test.*` file.
5. Commit changes with a `feat:` prefix and a concise description.

### Documentation Update
**Trigger:** When updating or adding documentation  
**Command:** `/docs-update`

1. Edit or create documentation files as needed.
2. Ensure code examples follow the project's conventions.
3. Commit changes with a `docs:` prefix and a concise description.

### Testing
**Trigger:** When writing or running tests  
**Command:** `/run-tests`

1. Create or update test files matching the `*.test.*` pattern.
2. Use the project's preferred (unknown) testing framework.
3. Run tests and ensure all pass before merging changes.

## Testing Patterns

- Test files follow the `*.test.*` naming convention, such as `UserProfileManager.test.py`.
- The specific testing framework is not specified, but tests should reside in files matching the pattern above.
- Example test file:
  ```python
  # UserProfileManager.test.py
  from .UserProfileManager import UserProfileManager

  def test_profile_creation():
      manager = UserProfileManager()
      profile = manager.create_profile("Alice")
      assert profile.name == "Alice"
  ```

## Commands
| Command                | Purpose                                       |
|------------------------|-----------------------------------------------|
| /feature-implementation| Step-by-step guide for adding new features    |
| /docs-update           | Instructions for updating documentation       |
| /run-tests             | How to write and execute tests                |
```