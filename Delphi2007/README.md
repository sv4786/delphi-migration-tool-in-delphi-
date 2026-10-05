# Delphi 2007 Migration Tool

This folder contains the migration assistant implemented as a native Delphi 2007 console application.

## Purpose

The tool creates a migration copy of a Delphi 2007 project and scans the copy for common Unicode migration hazards when moving to a Unicode Delphi compiler.

It currently:

- Copies the project without changing the original.
- Removes standalone {$DEFINE NO_UNICODE} directives.
- Reports SizeOf(Char), Length, Move, FillChar, PChar, AnsiString, AnsiChar and other Unicode-sensitive code.
- Writes a plain-text migration report.

## Usage

Build `Delphi2007Migration.dpr` with Delphi 2007, then run:

```
Delphi2007Migration.exe "C:\Projects\MyDelphi2007Project"
```

The output is created beside the source project as:

```
MyDelphi2007Project_Migration
```

This version intentionally performs only the safest automatic transformation. Findings such as Length, Move and FillChar must be reviewed because blindly changing them can break binary formats or buffer handling.
