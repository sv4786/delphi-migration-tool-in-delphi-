program Delphi2007Migration;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Windows;

const
  SourceExtensions: array[0..4] of string = ('.pas', '.dpr', '.dpk', '.inc', '.dfm');

function IsSourceFile(const FileName: string): Boolean;
var
  I: Integer;
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := False;
  for I := Low(SourceExtensions) to High(SourceExtensions) do
    if Ext = SourceExtensions[I] then
    begin
      Result := True;
      Exit;
    end;
end;

function IsSkippedDirectory(const Name: string): Boolean;
var
  N: string;
begin
  N := LowerCase(Name);
  Result :=
    (N = '.git') or
    (N = '__history') or
    (N = '__recovery') or
    (N = 'backup') or
    (N = 'debug') or
    (N = 'release') or
    (N = 'win32') or
    (N = 'win64');
end;

function RemoveNoUnicodeDirective(const Text: string; var Changed: Boolean): string;
var
  Lines: TStringList;
  Output: TStringList;
  I: Integer;
  Line: string;
begin
  Changed := False;
  Lines := TStringList.Create;
  Output := TStringList.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if SameText(Line, '{$DEFINE NO_UNICODE}') then
      begin
        Changed := True;
        Continue;
      end;
      Output.Add(Lines[I]);
    end;
    Result := Output.Text;
  finally
    Lines.Free;
    Output.Free;
  end;
end;

function ReadTextFile(const FileName: string): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

procedure WriteTextFile(const FileName, Text: string);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    Lines.SaveToFile(FileName);
  finally
    Lines.Free;
  end;
end;

procedure ScanText(const FileName, Text: string; Findings: TStrings);
var
  Lines: TStringList;
  I: Integer;
  L: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
    begin
      L := LowerCase(Lines[I]);
      if Pos('sizeof(char)', StringReplace(L, ' ', '', [rfReplaceAll])) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' HIGH unicode-sizeof-char SizeOf(Char) changes meaning under Unicode Delphi');
      if Pos('length(', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' MEDIUM length-byte-count Review whether Length is being used as a byte count');
      if Pos('move(', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' MEDIUM move Review byte counts and record sizes');
      if Pos('fillchar(', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' MEDIUM fillchar Review character and buffer sizes');
      if Pos('pchar', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' MEDIUM pchar Review implicit Unicode conversion');
      if Pos('ansistring', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' LOW ansistring Explicit ANSI usage requires review');
      if Pos('ansichar', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' LOW ansichar Explicit ANSI character usage requires review');
      if Pos('getprocaddress', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' HIGH dynamic-api GetProcAddress signatures should be reviewed');
      if Pos('regqueryvalueex', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' HIGH registry RegQueryValueEx buffer type should be reviewed');
      if Pos('multibytetowidechar', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' MEDIUM multibyte Explicit ANSI/Unicode conversion requires review');
      if Pos('widechartomultibyte', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' MEDIUM wide-to-multibyte Explicit ANSI/Unicode conversion requires review');
      if Pos('blockread', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' MEDIUM blockread Binary record sizes should be reviewed');
      if Pos('blockwrite', L) > 0 then
        Findings.Add(FileName + ':' + IntToStr(I + 1) + ' MEDIUM blockwrite Binary record sizes should be reviewed');
    end;
  finally
    Lines.Free;
  end;
end;

procedure ProcessDirectory(const SourceDir, DestinationDir: string; Findings, Changes: TStrings);
var
  Search: TSearchRec;
  Path, DestPath, Text, NewText: string;
  Changed: Boolean;
begin
  if FindFirst(IncludeTrailingPathDelimiter(SourceDir) + '*.*', faAnyFile, Search) = 0 then
  try
    repeat
      if (Search.Name <> '.') and (Search.Name <> '..') then
      begin
        Path := IncludeTrailingPathDelimiter(SourceDir) + Search.Name;
        DestPath := IncludeTrailingPathDelimiter(DestinationDir) + Search.Name;

        if (Search.Attr and faDirectory) <> 0 then
        begin
          if not IsSkippedDirectory(Search.Name) then
          begin
            ForceDirectories(DestPath);
            ProcessDirectory(Path, DestPath, Findings, Changes);
          end;
        end
        else if IsSourceFile(Search.Name) then
        begin
          Text := ReadTextFile(Path);
          ScanText(Path, Text, Findings);
          NewText := RemoveNoUnicodeDirective(Text, Changed);
          if Changed then
          begin
            WriteTextFile(DestPath, NewText);
            Changes.Add(Path + ' -> ' + DestPath + ' | remove-no-unicode-directive');
          end
          else
            WriteTextFile(DestPath, Text);
        end
        else
          CopyFile(PChar(Path), PChar(DestPath), False);
      end;
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

function GetOutputDirectory(const SourceDir: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(SourceDir) + '_Migration';
end;

procedure WriteReport(const OutputDir: string; Findings, Changes: TStrings);
var
  Report: TStringList;
begin
  Report := TStringList.Create;
  try
    Report.Add('Delphi 2007 -> Delphi 10.4 Migration Report');
    Report.Add('Generated: ' + DateTimeToStr(Now));
    Report.Add('');
    Report.Add('Automatic changes: ' + IntToStr(Changes.Count));
    Report.AddStrings(Changes);
    Report.Add('');
    Report.Add('Review findings: ' + IntToStr(Findings.Count));
    Report.AddStrings(Findings);
    Report.SaveToFile(IncludeTrailingPathDelimiter(OutputDir) + 'migration-report.txt');
  finally
    Report.Free;
  end;
end;

var
  SourceDir, OutputDir: string;
  Findings, Changes: TStringList;
begin
  try
    if ParamCount < 1 then
    begin
      Writeln('Delphi 2007 -> Delphi 10.4 Migration Tool');
      Writeln('Usage: Delphi2007Migration.exe "C:\Path\To\Project"');
      Writeln('The original project is never modified.');
      Halt(1);
    end;

    SourceDir := ExcludeTrailingPathDelimiter(ExpandFileName(ParamStr(1)));
    if not DirectoryExists(SourceDir) then
      raise Exception.Create('Project directory does not exist: ' + SourceDir);

    OutputDir := GetOutputDirectory(SourceDir);
    if DirectoryExists(OutputDir) then
      raise Exception.Create('Migration directory already exists: ' + OutputDir);

    ForceDirectories(OutputDir);
    Findings := TStringList.Create;
    Changes := TStringList.Create;
    try
      ProcessDirectory(SourceDir, OutputDir, Findings, Changes);
      WriteReport(OutputDir, Findings, Changes);
      Writeln('Migration copy created: ' + OutputDir);
      Writeln('Automatic changes: ' + IntToStr(Changes.Count));
      Writeln('Review findings: ' + IntToStr(Findings.Count));
      Writeln('Report: ' + IncludeTrailingPathDelimiter(OutputDir) + 'migration-report.txt');
    finally
      Findings.Free;
      Changes.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.Message);
      Halt(1);
    end;
  end;
end.
