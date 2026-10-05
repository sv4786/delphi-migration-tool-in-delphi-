# Delphi 10.4 Migration Tool

This folder contains the migration assistant implemented as a native Delphi 10.4 console application.

## Important version note

Embarcadero Delphi 10.4 is **Sydney**. Seattle is Delphi 10.1. This folder targets Delphi 10.4 Sydney as requested for the modern Delphi version.

## Purpose

The tool creates a migration copy of a Delphi 2007 project and scans the copy for common Unicode migration hazards.

It currently:

- Copies the project without changing the original.
- Removes standalone {$DEFINE NO_UNICODE} directives.
- Uses Delphi's regular-expression support for more accurate pattern matching.
- Reports common Unicode and byte-semantics hazards.
- Writes a UTF-8 migration report.

## Usage

Build `Delphi10_4Migration.dpr` with Delphi 10.4 Sydney, then run:

```
Delphi10_4Migration.exe "C:\Projects\MyDelphi2007Project"
```

The output is created beside the source project as:

```
MyDelphi2007Project_Migration
```

Only explicitly safe transformations are automatic. Code involving Length, Move, FillChar, PChar, registry APIs, binary I/O and explicit ANSI types is reported for manual review.
