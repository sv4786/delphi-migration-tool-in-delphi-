program Delphi10_4Converter;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions;

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

function ReplaceTokenOutsideComments(const Text, OldToken, NewToken: string;
  var Count: Integer): string;
var
  I: Integer;
  State: Integer;
  Ch: Char;
  OutText: string;
  PrevIsIdent, NextIsIdent: Boolean;
begin
  Count := 0;
  I := 1;
  State := 0;
  OutText := '';

  while I <= Length(Text) do
  begin
    Ch := Text[I];

    if State = 0 then
    begin
      if Ch = '''' then
        State := 1
      else if Ch = '{' then
        State := 2
      else if (Ch = '(') and (I < Length(Text)) and (Text[I + 1] = '*') then
      begin
        OutText := OutText + '(*';
        Inc(I, 2);
        State := 3;
        Continue;
      end
      else if (Ch = '/') and (I < Length(Text)) and (Text[I + 1] = '/') then
      begin
        OutText := OutText + '//';
        Inc(I, 2);
        State := 4;
        Continue;
      end
      else
      begin
        PrevIsIdent := (I > 1) and (Text[I - 1] in ['A'..'Z', 'a'..'z', '0'..'9', '_']);
        NextIsIdent := (I + Length(OldToken) <= Length(Text)) and
          (Text[I + Length(OldToken)] in ['A'..'Z', 'a'..'z', '0'..'9', '_']);

        if (not PrevIsIdent) and
           (not NextIsIdent) and
           SameText(Copy(Text, I, Length(OldToken)), OldToken) then
        begin
          OutText := OutText + NewToken;
          Inc(Count);
          Inc(I, Length(OldToken));
          Continue;
        end;
      end;
    end
    else if State = 1 then
    begin
      if Ch = '''' then
      begin
        if (I < Length(Text)) and (Text[I + 1] = '''') then
        begin
          OutText := OutText + '''''';
          Inc(I, 2);
          Continue;
        end;
        State := 0;
      end;
    end
    else if State = 2 then
    begin
      if Ch = '}' then
        State := 0;
    end
    else if State = 3 then
    begin
      if (Ch = '*') and (I < Length(Text)) and (Text[I + 1] = ')') then
      begin
        OutText := OutText + '*)';
        Inc(I, 2);
        State := 0;
        Continue;
      end;
    end
    else if State = 4 then
    begin
      if (Ch = #13) or (Ch = #10) then
        State := 0;
    end;

    OutText := OutText + Ch;
    Inc(I);
  end;

  Result := OutText;
end;

function ConvertUnicodeTypes(const Text: string; Changes: TStrings): string;
var
  S: string;
  C: Integer;
begin
  S := Text;

  S := ReplaceTokenOutsideComments(S, 'PChar', 'PWideChar', C);
  if C > 0 then
    Changes.Add('PChar -> PWideChar: ' + C.ToString);

  S := ReplaceTokenOutsideComments(S, 'Char', 'WideChar', C);
  if C > 0 then
    Changes.Add('Char -> WideChar: ' + C.ToString);

  S := ReplaceTokenOutsideComments(S, 'string', 'UnicodeString', C);
  if C > 0 then
    Changes.Add('string -> UnicodeString: ' + C.ToString);

  Result := S;
end;

function RemoveNoUnicodeDirective(const Text: string; var Changed: Boolean): string;
begin
  Result := TRegEx.Replace(
    Text,
    '^s*{$DEFINEs+NO_UNICODE}s*R?',
    '',
    [roIgnoreCase, roMultiLine]
  );
  Changed := not SameText(Result, Text);
end;

procedure ProcessDirectory(const SourceDir, DestinationDir: string;
  Changes, Findings: TStrings);
var
  FileName, RelativeName, DestinationFile, Text, NewText: string;
  Files, Directories: TStringDynArray;
  Changed: Boolean;
  LocalChanges: TStringList;
begin
  ForceDirectories(DestinationDir);

  Files := TDirectory.GetFiles(SourceDir);
  for FileName in Files do
  begin
    RelativeName := TPath.GetRelativePath(SourceDir, FileName);
    DestinationFile := TPath.Combine(DestinationDir, RelativeName);
    ForceDirectories(ExtractFileDir(DestinationFile));

    if IsSourceFile(FileName) then
    begin
      Text := TFile.ReadAllText(FileName, TEncoding.Default);
      LocalChanges := TStringList.Create;
      try
        NewText := RemoveNoUnicodeDirective(Text, Changed);
        if Changed then
          LocalChanges.Add('remove {$DEFINE NO_UNICODE}');

        NewText := ConvertUnicodeTypes(NewText, LocalChanges);

        if LocalChanges.Count > 0 then
        begin
          TFile.WriteAllText(DestinationFile, NewText, TEncoding.UTF8);
          Changes.Add(FileName + ' -> ' + DestinationFile + ' | ' +
            StringReplace(LocalChanges.Text, sLineBreak, '; ', [rfReplaceAll]));
        end
        else
          TFile.WriteAllText(DestinationFile, Text, TEncoding.Default);
      finally
        LocalChanges.Free;
      end;
    end
    else
      TFile.Copy(FileName, DestinationFile, True);
  end;

  Directories := TDirectory.GetDirectories(SourceDir);
  for FileName in Directories do
    if not IsSkippedDirectory(ExtractFileName(ExcludeTrailingPathDelimiter(FileName))) then
    begin
      RelativeName := TPath.GetRelativePath(SourceDir, FileName);
      ProcessDirectory(
        FileName,
        TPath.Combine(DestinationDir, RelativeName),
        Changes,
        Findings
      );
    end;
end;

procedure AddFindings(const Root: string; Findings: TStrings);
var
  FileName, Text: string;
  Files, Directories: TStringDynArray;
begin
  Files := TDirectory.GetFiles(Root);
  for FileName in Files do
    if IsSourceFile(FileName) then
    begin
      Text := TFile.ReadAllText(FileName, TEncoding.Default);
      if TRegEx.IsMatch(Text, '(?i)SizeOfs*(s*Chars*)') then
        Findings.Add(FileName + ' | REVIEW: SizeOf(Char) now means 2 bytes');
      if TRegEx.IsMatch(Text, '(?i)Lengths*(') then
        Findings.Add(FileName + ' | REVIEW: Length() returns character count');
      if TRegEx.IsMatch(Text, '(?i)Moves*(') then
        Findings.Add(FileName + ' | REVIEW: Move() uses byte counts');
      if TRegEx.IsMatch(Text, '(?i)FillChars*(') then
        Findings.Add(FileName + ' | REVIEW: FillChar() uses byte counts');
      if TRegEx.IsMatch(Text, '(?i)AnsiString') then
        Findings.Add(FileName + ' | REVIEW: intentional ANSI storage is preserved');
      if TRegEx.IsMatch(Text, '(?i)PAnsiChar') then
        Findings.Add(FileName + ' | REVIEW: ANSI API pointer is preserved');
    end;

  Directories := TDirectory.GetDirectories(Root);
  for FileName in Directories do
    if not IsSkippedDirectory(ExtractFileName(ExcludeTrailingPathDelimiter(FileName))) then
      AddFindings(FileName, Findings);
end;

var
  SourceDir, OutputDir: string;
  Changes, Findings: TStringList;
  Report: TStringList;
begin
  try
    if ParamCount < 1 then
    begin
      Writeln('Delphi 2007 -> Delphi 10.4 Automatic Converter');
      Writeln('Usage: Delphi10_4Converter.exe "C:PathToProject"');
      Writeln('Creates a separate _Converted copy. The original is never modified.');
      ExitCode := 1;
      Exit;
    end;

    SourceDir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ParamStr(1)));
    if not TDirectory.Exists(SourceDir) then
      raise Exception.Create('Project directory does not exist: ' + SourceDir);

    OutputDir := SourceDir + '_Converted';
    if TDirectory.Exists(OutputDir) then
      raise Exception.Create('Conversion directory already exists: ' + OutputDir);

    Changes := TStringList.Create;
    Findings := TStringList.Create;
    Report := TStringList.Create;
    try
      ProcessDirectory(SourceDir, OutputDir, Changes, Findings);
      AddFindings(OutputDir, Findings);

      Report.Add('Delphi 2007 -> Delphi 10.4 Automatic Conversion Report');
      Report.Add('Generated: ' + DateTimeToStr(Now));
      Report.Add('');
      Report.Add('AUTOMATIC CONVERSIONS');
      Report.Add('Count: ' + Changes.Count.ToString);
      Report.AddStrings(Changes);
      Report.Add('');
      Report.Add('REVIEW ITEMS');
      Report.Add('Count: ' + Findings.Count.ToString);
      Report.AddStrings(Findings);
      Report.Add('');
      Report.Add('Notes:');
      Report.Add('- string/Char/PChar are made explicit as UnicodeString/WideChar/PWideChar.');
      Report.Add('- AnsiString, AnsiChar and PAnsiChar are intentionally preserved.');
      Report.Add('- Byte-count operations such as Move, FillChar and Length are reported for review.');
      Report.Add('- The Delphi IDE may still need to upgrade the legacy .dproj/project settings.');

      TFile.WriteAllText(
        TPath.Combine(OutputDir, 'conversion-report.txt'),
        Report.Text,
        TEncoding.UTF8
      );

      Writeln('Converted project created: ' + OutputDir);
      Writeln('Automatic conversion entries: ' + Changes.Count.ToString);
      Writeln('Review items: ' + Findings.Count.ToString);
      Writeln('Report: ' + TPath.Combine(OutputDir, 'conversion-report.txt'));
    finally
      Changes.Free;
      Findings.Free;
      Report.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
