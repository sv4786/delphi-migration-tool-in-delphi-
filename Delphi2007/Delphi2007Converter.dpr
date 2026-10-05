program Delphi2007Converter;

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
    (N = '.git') or (N = '__history') or (N = '__recovery') or
    (N = 'backup') or (N = 'debug') or (N = 'release') or
    (N = 'win32') or (N = 'win64');
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

function ReplaceTokenOutsideComments(const Text, OldToken, NewToken: string;
  var Count: Integer): string;
var
  I, StartPos: Integer;
  State: Integer;
  Ch: Char;
  Token: string;
  OutText: string;
begin
  Count := 0;
  OutText := '';
  I := 1;
  State := 0;
  while I <= Length(Text) do
  begin
    Ch := Text[I];

    if State = 0 then
    begin
      if Ch = '''' then
      begin
        State := 1;
        OutText := OutText + Ch;
        Inc(I);
        Continue;
      end;
      if Ch = '{' then
      begin
        State := 2;
        OutText := OutText + Ch;
        Inc(I);
        Continue;
      end;
      if (Ch = '(') and (I < Length(Text)) and (Text[I + 1] = '*') then
      begin
        State := 3;
        OutText := OutText + '(*';
        Inc(I, 2);
        Continue;
      end;
      if (Ch = '/') and (I < Length(Text)) and (Text[I + 1] = '/') then
      begin
        State := 4;
        OutText := OutText + '//';
        Inc(I, 2);
        Continue;
      end;

      if ((I = 1) or not (Text[I - 1] in
        ['A'..'Z', 'a'..'z', '0'..'9', '_'])) and
         ((I + Length(OldToken) > Length(Text)) or
          not (Text[I + Length(OldToken)] in
            ['A'..'Z', 'a'..'z', '0'..'9', '_'])) and
         SameText(Copy(Text, I, Length(OldToken)), OldToken) then
      begin
        OutText := OutText + NewToken;
        Inc(Count);
        Inc(I, Length(OldToken));
        Continue;
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

function RemoveNoUnicodeDirective(const Text: string; var Changed: Boolean): string;
var
  Lines, Output: TStringList;
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

function ConvertUnicodeTypes(const Text: string; Changes: TStrings): string;
var
  C: Integer;
  S: string;
begin
  S := Text;

  S := ReplaceTokenOutsideComments(S, 'PChar', 'PWideChar', C);
  if C > 0 then
    Changes.Add('PChar -> PWideChar: ' + IntToStr(C));

  S := ReplaceTokenOutsideComments(S, 'Char', 'WideChar', C);
  if C > 0 then
    Changes.Add('Char -> WideChar: ' + IntToStr(C));

  S := ReplaceTokenOutsideComments(S, 'string', 'UnicodeString', C);
  if C > 0 then
    Changes.Add('string -> UnicodeString: ' + IntToStr(C));

  Result := S;
end;

procedure ProcessDirectory(const SourceDir, DestinationDir: string;
  Changes, Findings: TStrings);
var
  Search: TSearchRec;
  Path, DestPath, Text, NewText: string;
  Changed: Boolean;
  LocalChanges: TStringList;
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
            ProcessDirectory(Path, DestPath, Changes, Findings);
          end;
        end
        else if IsSourceFile(Search.Name) then
        begin
          Text := ReadTextFile(Path);
          LocalChanges := TStringList.Create;
          try
            NewText := RemoveNoUnicodeDirective(Text, Changed);
            if Changed then
              LocalChanges.Add('remove {$DEFINE NO_UNICODE}');

            NewText := ConvertUnicodeTypes(NewText, LocalChanges);

            if LocalChanges.Count > 0 then
            begin
              WriteTextFile(DestPath, NewText);
              Changes.Add(Path + ' -> ' + DestPath + ' | ' +
                StringReplace(LocalChanges.Text, #13#10, '; ', [rfReplaceAll]));
            end
            else
              WriteTextFile(DestPath, Text);
          finally
            LocalChanges.Free;
          end;
        end
        else
          CopyFile(PChar(Path), PChar(DestPath), False);
      end;
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

procedure AddFindings(const Root: string; Findings: TStrings);
var
  Search: TSearchRec;
  Path: string;
  Text: string;
begin
  if FindFirst(IncludeTrailingPathDelimiter(Root) + '*.*', faAnyFile, Search) <> 0 then
    Exit;
  try
    repeat
      if (Search.Name <> '.') and (Search.Name <> '..') then
      begin
        Path := IncludeTrailingPathDelimiter(Root) + Search.Name;
        if (Search.Attr and faDirectory) <> 0 then
        begin
          if not IsSkippedDirectory(Search.Name) then
            AddFindings(Path, Findings);
        end
        else if IsSourceFile(Search.Name) then
        begin
          Text := ReadTextFile(Path);
          if Pos('SizeOf(Char)', Text) > 0 then
            Findings.Add(Path + ' | REVIEW: SizeOf(Char) now means 2 bytes');
          if Pos('Length(', LowerCase(Text)) > 0 then
            Findings.Add(Path + ' | REVIEW: Length() is character count, not byte count');
          if Pos('Move(', LowerCase(Text)) > 0 then
            Findings.Add(Path + ' | REVIEW: Move() byte counts must be checked');
          if Pos('FillChar(', LowerCase(Text)) > 0 then
            Findings.Add(Path + ' | REVIEW: FillChar() byte counts must be checked');
          if Pos('AnsiString', Text) > 0 then
            Findings.Add(Path + ' | REVIEW: intentional ANSI storage is preserved');
        end;
      end;
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
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
      Writeln('Usage: Delphi2007Converter.exe "C:PathToProject"');
      Writeln('Creates a separate _Converted copy. The original is never modified.');
      Halt(1);
    end;

    SourceDir := ExcludeTrailingPathDelimiter(ExpandFileName(ParamStr(1)));
    if not DirectoryExists(SourceDir) then
      raise Exception.Create('Project directory does not exist: ' + SourceDir);

    OutputDir := SourceDir + '_Converted';
    if DirectoryExists(OutputDir) then
      raise Exception.Create('Conversion directory already exists: ' + OutputDir);

    ForceDirectories(OutputDir);
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
      Report.Add('Count: ' + IntToStr(Changes.Count));
      Report.AddStrings(Changes);
      Report.Add('');
      Report.Add('REVIEW ITEMS');
      Report.Add('Count: ' + IntToStr(Findings.Count));
      Report.AddStrings(Findings);
      Report.Add('');
      Report.Add('Notes:');
      Report.Add('- string/Char/PChar are made explicit as UnicodeString/WideChar/PWideChar.');
      Report.Add('- AnsiString, AnsiChar and PAnsiChar are intentionally preserved.');
      Report.Add('- Byte-count operations such as Move, FillChar and Length are reported for review.');
      Report.Add('- The Delphi IDE may still need to upgrade the legacy .dproj/project settings.');

      Report.SaveToFile(IncludeTrailingPathDelimiter(OutputDir) + 'conversion-report.txt');

      Writeln('Converted project created: ' + OutputDir);
      Writeln('Automatic conversion entries: ' + IntToStr(Changes.Count));
      Writeln('Review items: ' + IntToStr(Findings.Count));
      Writeln('Report: ' + IncludeTrailingPathDelimiter(OutputDir) + 'conversion-report.txt');
    finally
      Changes.Free;
      Findings.Free;
      Report.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.Message);
      Halt(1);
    end;
  end;
end.
