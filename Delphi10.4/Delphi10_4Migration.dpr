program Delphi10_4Migration;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.StrUtils;

const
  SourceExtensions: array[0..4] of string = ('.pas', '.dpr', '.dpk', '.inc', '.dfm');

function IsSourceFile(const FileName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(SourceExtensions) to High(SourceExtensions) do
    if SameText(ExtractFileExt(FileName), SourceExtensions[I]) then
      Exit(True);
end;

function IsSkippedDirectory(const Name: string): Boolean;
var
  N: string;
begin
  N := LowerCase(Name);
  Result := MatchText(N, ['.git', '__history', '__recovery', 'backup', 'debug', 'release', 'win32', 'win64']);
end;

function RemoveNoUnicodeDirective(const Text: string; var Changed: Boolean): string;
begin
  Result := TRegEx.Replace(
    Text,
    '^\s*\{\$DEFINE\s+NO_UNICODE\}\s*\R?',
    '',
    [roIgnoreCase, roMultiLine]
  );
  Changed := not SameText(Result, Text);
end;

procedure ScanText(const FileName, Text: string; Findings: TStrings);
const
  Patterns: array[0..13] of string = (
    '(?i)\bSizeOf\s*\(\s*Char\s*\)',
    '(?i)\bLength\s*\(',
    '(?i)\bMove\s*\(',
    '(?i)\bFillChar\s*\(',
    '(?i)\bPChar\b',
    '(?i)\bPAnsiChar\b',
    '(?i)\bAnsiString\b',
    '(?i)\bAnsiChar\b',
    '(?i)\bGetProcAddress\b',
    '(?i)\bRegQueryValueEx\b',
    '(?i)\bMultiByteToWideChar\b',
    '(?i)\bWideCharToMultiByte\b',
    '(?i)\bBlockRead\b',
    '(?i)\bBlockWrite\b'
  );
  Categories: array[0..13] of string = (
    'unicode-sizeof-char',
    'length-byte-count',
    'move',
    'fillchar',
    'pchar',
    'pansichar',
    'ansistring',
    'ansichar',
    'dynamic-api',
    'registry',
    'multibyte',
    'wide-to-multibyte',
    'blockread',
    'blockwrite'
  );
  Severities: array[0..13] of string = (
    'HIGH', 'MEDIUM', 'MEDIUM', 'MEDIUM', 'MEDIUM', 'LOW', 'LOW',
    'LOW', 'HIGH', 'HIGH', 'MEDIUM', 'MEDIUM', 'MEDIUM', 'MEDIUM'
  );
var
  I, Line: Integer;
  Match: TMatch;
  Matches: TMatchCollection;
  Lines: TArray<string>;
begin
  Lines := TRegEx.Split(Text, '\R');
  for I := Low(Patterns) to High(Patterns) do
  begin
    Matches := TRegEx.Matches(Text, Patterns[I]);
    for Match in Matches do
    begin
      Line := 1 + TRegEx.Matches(Text.Substring(0, Match.Index), '\R').Count;
      Findings.Add(
        FileName + ':' + IntToStr(Line) + ' ' + Severities[I] + ' ' +
        Categories[I] + ' Review Unicode/byte semantics'
      );
    end;
  end;
end;

procedure ProcessDirectory(const SourceDir, DestinationDir: string; Findings, Changes: TStrings);
var
  FileName, RelativeName, SourceFile, DestinationFile, Text, NewText: string;
  Files, Directories: TStringDynArray;
  Changed: Boolean;
begin
  ForceDirectories(DestinationDir);

  Files := TDirectory.GetFiles(SourceDir);
  for FileName in Files do
  begin
    if IsSourceFile(FileName) then
    begin
      Text := TFile.ReadAllText(FileName, TEncoding.Default);
      ScanText(FileName, Text, Findings);
      NewText := RemoveNoUnicodeDirective(Text, Changed);
      RelativeName := TPath.GetRelativePath(SourceDir, FileName);
      DestinationFile := TPath.Combine(DestinationDir, RelativeName);
      ForceDirectories(ExtractFileDir(DestinationFile));
      if Changed then
      begin
        TFile.WriteAllText(DestinationFile, NewText, TEncoding.UTF8);
        Changes.Add(FileName + ' -> ' + DestinationFile + ' | remove-no-unicode-directive');
      end
      else
        TFile.WriteAllText(DestinationFile, Text, TEncoding.Default);
    end
    else
    begin
      RelativeName := TPath.GetRelativePath(SourceDir, FileName);
      DestinationFile := TPath.Combine(DestinationDir, RelativeName);
      TFile.Copy(FileName, DestinationFile, True);
    end;
  end;

  Directories := TDirectory.GetDirectories(SourceDir);
  for FileName in Directories do
  begin
    if not IsSkippedDirectory(ExtractFileName(ExcludeTrailingPathDelimiter(FileName))) then
    begin
      RelativeName := TPath.GetRelativePath(SourceDir, FileName);
      SourceFile := TPath.Combine(SourceDir, RelativeName);
      DestinationFile := TPath.Combine(DestinationDir, RelativeName);
      ProcessDirectory(SourceFile, DestinationFile, Findings, Changes);
    end;
  end;
end;

var
  SourceDir, OutputDir: string;
  Findings, Changes: TStringList;
begin
  try
    if ParamCount < 1 then
    begin
      Writeln('Delphi 10.4 Migration Tool');
      Writeln('Usage: Delphi10_4Migration.exe "C:\Path\To\Project"');
      Writeln('The original project is never modified.');
      ExitCode := 1;
      Exit;
    end;

    SourceDir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ParamStr(1)));
    if not TDirectory.Exists(SourceDir) then
      raise Exception.Create('Project directory does not exist: ' + SourceDir);

    OutputDir := SourceDir + '_Migration';
    if TDirectory.Exists(OutputDir) then
      raise Exception.Create('Migration directory already exists: ' + OutputDir);

    Findings := TStringList.Create;
    Changes := TStringList.Create;
    try
      ProcessDirectory(SourceDir, OutputDir, Findings, Changes);

      TFile.WriteAllText(
        TPath.Combine(OutputDir, 'migration-report.txt'),
        'Delphi 2007 -> Delphi 10.4 Migration Report' + sLineBreak +
        'Generated: ' + DateTimeToStr(Now) + sLineBreak + sLineBreak +
        'Automatic changes: ' + IntToStr(Changes.Count) + sLineBreak +
        Changes.Text + sLineBreak +
        'Review findings: ' + IntToStr(Findings.Count) + sLineBreak +
        Findings.Text,
        TEncoding.UTF8
      );

      Writeln('Migration copy created: ' + OutputDir);
      Writeln('Automatic changes: ' + IntToStr(Changes.Count));
      Writeln('Review findings: ' + IntToStr(Findings.Count));
    finally
      Findings.Free;
      Changes.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
