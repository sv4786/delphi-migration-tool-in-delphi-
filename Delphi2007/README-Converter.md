# Delphi 2007 Automatic Converter

This companion tool performs actual source conversion while leaving the original project untouched.

Usage:

```text
Delphi2007Converter.exe "C:\Path\To\Delphi2007Project"
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

This is intentionally conservative. Delphi's Unicode transition changed the meaning of character and string types, while byte-count operations can depend on the application's intended memory layout. The converter therefore does not blindly rewrite those operations.
