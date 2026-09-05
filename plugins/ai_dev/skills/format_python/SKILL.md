---
name: format_python
description: Apply formatting standards, code quality rules, structure conventions, linting prevention, and best practices when generating or editing Python code (.py). Covers indentation, quoting, imports, naming, line length, type hints, error handling, logging, data structures, testing, and security practices aligned with common linters (flake8, ruff, pylint).
version: 1.4.1
author: Andreas F. Hoffmann
license: MIT
---

# format_python

## Formatting Standards

- Use exactly 4 spaces for indentation (never tabs)
- Use double quotes for all string literals consistently
- Write one import per line, grouped stdlib → third party → first party → local, to prevent the E401 multiple-imports error
- Use absolute imports, and import from the `typing` module only when a built-in type will not do
- Import only the modules, names, and types you use, and remove unused imports immediately to prevent F401 errors
- Use `snake_case` for variables/functions, `PascalCase` for classes, `UPPER_CASE` for constants
- Keep lines under 88 characters, break long lines at logical points with proper indentation

## Code Quality Standards

- Write valid Python syntax that passes all linter checks
- Use specific exception types like `ValueError`, `FileNotFoundError`
- Assign error messages to variables before raising exceptions
- Remove unused variables, and use `_` for intentionally unused values, to prevent F841 errors
- Use modern type hints: `dict[str, Any]` instead of `Dict[str, Any]`, `str | None` instead of `Optional[str]`
- Use f-strings for general formatting, use % formatting in logging statements
- Use `is`/`is not` for `None` comparisons, use `in`/`not in` for membership testing
- Avoid single-letter variable names except for loop counters
- Don't shadow built-in names like `list`, `dict`, `str`, `id`, `type`
- Use context managers (`with` statements) for all file operations and resource cleanup
- Use `logger = logging.getLogger(__name__)` for module-level logging
- Use logging instead of print statements for all output

## Code Structure

- Follow this exact order: docstring → imports → constants → classes → functions → main guard
- Write functions with single responsibility, clear parameters, and early returns for better readability
- Use clear, descriptive class names; apply proper decorators (`@classmethod`, `@staticmethod`) for class methods
- Validate all input parameters when necessary, especially for public functions

## Linting Prevention (Critical for LLM Code Generation)

- Omit exception variable name when not using the exception object
- Remove commented-out code and unreachable statements immediately
- Update all class references when renaming to prevent F821 undefined name errors
- Use descriptive class names without "Test" prefix for non-test classes
- Use `is None` instead of `== None` to prevent E711 comparison error

## Best Practices

- Define named functions instead of lambda assignments for better readability
- Write one statement per line for maximum readability
- Create variables only when needed; use unique, descriptive names per scope
- Use `isinstance()` for type comparisons instead of `type()` checks
- Use `path.open()` instead of `open(path)` when working with Path objects
- Use `logger.exception()` in except blocks for better error tracking
- Validate and sanitize all external inputs
- Use environment variables for sensitive configuration

## Error Handling & Resilience

- Always handle exceptions at the appropriate level of abstraction
- Use specific exception types and provide meaningful error messages
- Log errors with sufficient context for debugging
- Implement graceful degradation when possible
- Use try-except-else-finally blocks appropriately
- Re-raise exceptions with `raise ... from e` to preserve stack traces
- Create custom exception classes for domain-specific errors

## Performance & Efficiency

- Use generators for large datasets to conserve memory
- Prefer list comprehensions over explicit loops when readable
- Use `enumerate()` instead of manual index tracking
- Cache expensive computations when appropriate
- Use `collections.defaultdict` and `collections.Counter` for common patterns
- Avoid premature optimization; profile before optimizing
- Use `functools.lru_cache` for expensive pure functions

## Data Structures & Patterns

- Use dataclasses for simple data containers
- Prefer dictionaries over classes for simple data grouping
- Use `collections.namedtuple` for immutable data structures
- Implement `__str__` and `__repr__` methods for custom classes
- Use `__slots__` for memory-efficient classes with many instances
- Prefer composition over inheritance when possible

## Type Safety & Documentation

- Use type hints for all function parameters and return values
- Document complex algorithms and business logic
- Use docstrings following PEP 257 conventions
- Include examples in docstrings for complex functions
- Use `typing.Protocol` for structural subtyping
- Prefer `typing.Literal` for fixed value sets

## Testing & Maintainability

- Write testable code with clear separation of concerns
- Use dependency injection for external dependencies
- Make functions pure when possible (no side effects)
- Use constants for magic numbers and strings
- Keep functions small and focused on single responsibilities
- Use meaningful variable and function names that explain intent

## Security & Safety

- Never use `eval()` or `exec()` with user input
- Validate and sanitize all external data
- Use `secrets` module for cryptographic operations
- Be cautious with file path operations to prevent directory traversal
- Use parameterized queries for database operations
- Store sensitive data in environment variables or secure vaults

## Example

```python
"""Module docstring."""

import logging
from typing import Any

# Constants
DEFAULT_TIMEOUT = 30
logger = logging.getLogger(__name__)


class ExampleClass:
    """Example class demonstrating proper patterns."""

    def __init__(self, name: str, value: int | None = None) -> None:
        """Initialize with name and optional value."""
        self.name = name
        self.value = value

    def process_data(self, data: list[dict[str, Any]]) -> bool:
        """Process data and return success status."""
        if not data:
            return False

        for item in data:
            if not isinstance(item, dict):
                return False

        return True

    def get_info(self) -> dict[str, Any]:
        """Get class information."""
        return {
            "name": self.name,
            "value": self.value,
            "has_value": self.value is not None,
        }


def main() -> None:
    """Execute main function."""
    example = ExampleClass("test")
    result = example.process_data([{"id": 1, "name": "item"}])
    logger.info("Result: %s", result)


if __name__ == "__main__":
    main()
```
