# Delphi 10.4 Automatic Converter

This is the Delphi 10.4 Sydney build of the automatic Delphi 2007 -> Delphi 10.4 source converter.

Usage:

```text
Delphi10_4Converter.exe "C:\Path\To\Delphi2007Project"
```

It creates:

```text
C:\Path\To\Delphi2007Project_Converted
```

Automatic conversions currently include:

- Removes `{$DEFINE NO_UNICODE}`.
- Makes the Unicode mappings explicit:
  - `string` -> `UnicodeString`
  - `Char` -> `WideChar`
  - `PChar` -> `PWideChar`
- Avoids changing comments and quoted string literals.
- Preserves explicit ANSI types such as `AnsiString`, `AnsiChar`, and `PAnsiChar`.
- Copies non-source project files into the converted project.
- Produces `conversion-report.txt`.

The tool also reports constructs that still require human review, especially `Length`, `Move`, `FillChar`, `SizeOf(Char)`, and explicit ANSI APIs.

This tool is designed to be run with Delphi 10.4 Sydney and is the target-side companion to the Delphi 2007 converter.
