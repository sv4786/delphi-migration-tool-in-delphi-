# Delphi Migration Tool

Native Delphi implementations of the Delphi 2007 -> Delphi 10.4 migration assistant.

## Folders

- `Delphi2007` - native Delphi 2007 implementation.
- `Delphi10.4` - native Delphi 10.4 Sydney implementation.

## Version clarification

There is a naming mismatch in the requested target: Delphi 10.4 is **Sydney**, while **Seattle is Delphi 10.1**. The modern implementation in this repository targets Delphi 10.4 Sydney.

## Design

Both versions follow the same conservative migration model:

1. Accept the Delphi 2007 project directory.
2. Create a sibling directory named `<Project>_Migration`.
3. Copy the original project into the migration directory.
4. Scan Delphi source files for Unicode migration hazards.
5. Apply only safe transformations.
6. Write a migration report.
7. Never modify the original project.

The first automatic transformation is removal of the obsolete standalone `{$DEFINE NO_UNICODE}` directive.

## What is intentionally not automatic

The tool does not blindly convert every `string` to `AnsiString`, replace every `Char`, or rewrite binary I/O. Those changes depend on how the application uses the data and can introduce subtle bugs.

## No external dependencies

Both implementations are native Delphi console applications and do not require Python or third-party libraries.
