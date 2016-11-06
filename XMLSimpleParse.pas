// -----------------------------------------------------------------------------
unit XMLSimpleParse;
// -----------------------------------------------------------------------------
interface
// -----------------------------------------------------------------------------
uses Generics.Collections, Classes, SysUtils;
// -----------------------------------------------------------------------------
type
        TXMLDoc = class
        private
                fAttributes : TDictionary<String, String>;
                KeyValues : TDictionary<String, String>;
                BuildKeyValues : Boolean;
                procedure TrimRoot();
                function AddChild() : TXMLDoc;
                procedure BuildFromString(const FS : String; var Position : Int64);
                procedure ConstructFrom(const Source : String);
                procedure DoReportNonLatinChars();
                function GetAttribute(const Key : String) : String;
                procedure AutoDetectEncoding(const FileName : String);

        public
                Encoding: TEncoding;
                ParentNode : TXMLDoc;
                NodeName : String;
                NodeValue : String;
                Childs : TList<TXMLDoc>;

                property Attributes[const Key : String] : String read GetAttribute;
                function HasAttribute(const Key : String) : Boolean;

                constructor Create(const ParentNode : TXMLDoc; const BuildKeyValues : Boolean = False);
                destructor Destroy(); override;

                procedure LoadFromFile(const FileName : String; const ReportNonLatinChars : Boolean = False);
                procedure LoadFromStream(const Stream : TMemoryStream; const ReportNonLatinChars : Boolean = False);
                function FindChild(NodeName : String) : TXMLDoc;
                function NextSibling() : TXMLDoc;
                function GetAttribDef(const Name : String; const Def : Boolean) : Boolean; overload;
                function GetAttribDef(const Name : String; const Def : String) : String; overload;
                function GetAttribDef(const Name : String; const Def : Integer) : Integer; overload;
                function GetAttribDef(const Name : String; const Def : Single) : Single; overload;

                function GetValByKey(const Name : string; const DefaultValue : Boolean) : Boolean; overload;
                function GetValByKey(const Name : string; const DefaultValue : String) : String; overload;
                function GetValByKey(const Name : string; const DefaultValue : Integer) : Integer; overload;
                function GetValByKey(const Name : string; const DefaultValue : Single) : Single; overload;
        end;
// -----------------------------------------------------------------------------
implementation
// -----------------------------------------------------------------------------
procedure log_AddLine(name, str: string);
begin
        //MainForm.DebugMemo.Lines.Add(name + ': ' + str);
end;

// -----------------------------------------------------------------------------
// TXMLDoc
// -----------------------------------------------------------------------------
function TXMLDoc.AddChild(): TXMLDoc;
begin
        Result := TXMLDoc.Create(Self, BuildKeyValues);
        Childs.Add(Result);
end;

// -----------------------------------------------------------------------------
procedure TXMLDoc.TrimRoot();
var
        tmp : TXMLDoc;
        tmpChilds : TList<TXMLDoc>;
        tmpAttributes : TDictionary<String, String>;
        tmpKeyValues : TDictionary<String, String>;
begin
        if (Self.Childs.Count = 1) then begin
                tmp := Childs[0];
                tmpChilds := Self.Childs;
                Self.Childs := Self.Childs[0].Childs;

                tmpAttributes := tmp.fAttributes;
                tmp.fAttributes := Self.fAttributes;
                Self.fAttributes := tmpAttributes;

                tmpKeyValues := tmp.KeyValues;
                tmp.KeyValues := Self.KeyValues;
                Self.KeyValues := tmpKeyValues;

                Self.NodeName := tmp.NodeName;
                Self.NodeValue := tmp.NodeValue;

                tmp.Childs := tmpChilds;
                tmpChilds.Clear();
                tmp.Free();

                for tmp in Childs do begin
                        tmp.ParentNode := Self;
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure TXMLDoc.LoadFromStream(const Stream: TMemoryStream; const ReportNonLatinChars: Boolean);
var
        FS : TStringStream;
        str : String;
        pos : Int64;
begin
        FS := TStringStream.Create('', Encoding);
        FS.LoadFromStream(Stream);
        str := FS.DataString;
        FS.Free();
        pos := 1;
        BuildFromString(str, pos);

        TrimRoot();

        if (ReportNonLatinChars) then begin
                DoReportNonLatinChars();
        end;
end;

// -----------------------------------------------------------------------------
procedure TXMLDoc.LoadFromFile(const FileName: String; const ReportNonLatinChars : Boolean = False);
var
        FS : TStringStream;
        str : String;
        pos : Int64;
begin
        AutoDetectEncoding(FileName);
        FS := TStringStream.Create('', Encoding);
        FS.LoadFromFile(FileName);
        str := FS.DataString;
        FS.Free();
        pos := 1;
        BuildFromString(str, pos);

        TrimRoot();

        if (ReportNonLatinChars) then begin
                DoReportNonLatinChars();
        end;
end;

// -----------------------------------------------------------------------------
procedure TXMLDoc.AutoDetectEncoding(const FileName: String);
var
        F : TextFile;
        s : String;
        op, cl : Integer;
begin
        AssignFile(F, FileName);
        Reset(F);
        Readln(F, s);
        CloseFile(F);

        S := LowerCase(S);
        if (Pos('<?', s) > 0) then begin
                op := Pos('encoding', s);
                if (op > 0) then begin
                        while (op <= Length(S)) and (S[op] <> '"') do begin
                                Inc(op);
                        end;

                        cl := op + 1;

                        while (cl <= Length(S)) and (S[cl] <> '"') do begin
                                Inc(cl);
                        end;

                        if (cl <> op + 1) then
                        if (cl <= Length(S)) and (S[cl] = '"') then begin
                                s := Copy(s, op + 1, cl - op - 1);
                                Encoding := TEncoding.GetEncoding(s);
                        end;
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure TXMLDoc.BuildFromString(const FS : String; var Position : Int64);
var
        opt, clt, t : Integer;
        child : TXMLDoc;

        function Find(const From : Integer; const SubChar : Char) : Integer;
        var
                in_safe_zone : Boolean;
        begin
                Result := From;
                in_safe_zone := False;
                while (Result < Length(FS)) do begin
                        if (FS[Result] = '"') then begin
                                in_safe_zone := not in_safe_zone;
                        end;

                        if (FS[Result] = SubChar) then
                        if (in_safe_zone = False) then begin
                                Exit(Result);
                        end;
                        Inc(Result);
                end;
        end;

        function FindBack(const From : Integer; const SubChar : Char) : Integer;
        var
                in_safe_zone : Boolean;
        begin
                Result := From;
                in_safe_zone := False;
                while (Result > 0) do begin
                        if (FS[Result] = '"') then begin
                                in_safe_zone := not in_safe_zone;
                        end;

                        if (FS[Result] = SubChar) then
                        if (in_safe_zone = False) then begin
                                Exit(Result);
                        end;
                        Dec(Result);
                end;
        end;
begin
        clt := Position;
        while (clt < Length(FS)) do begin
                opt := clt;

                // find open tag
                opt := Find(opt, '<');

                // finish
                if (opt + 1 >= Length(FS)) then begin
                        Position := opt + 1;
                        Exit;
                end;

                if (opt + 1 < Length(FS)) and (FS[opt + 1] = '/') then begin
                        // try get value
                        t := FindBack(opt - 1, '>');
                        if (t <> opt - 1) then begin
                                NodeValue := Trim(Copy(FS, t + 1, opt - t - 1));
                        end;

                        // get out here
                        Position := opt + 1;
                        Exit;
                end;

                // skip
                while (opt + 1 < Length(FS)) and (charinset(FS[opt + 1], ['?', '!'])) do begin
                        if (opt + 3 < Length(FS)) and (FS[opt + 2] = '-') and (FS[opt + 3] = '-') then begin
                                inc(opt, 3);
                                while (opt <= Length(FS)) do begin
                                        inc(opt);
                                        opt := Find(opt, '>');
                                        if (FS[opt - 1] = '-') and (FS[opt - 2] = '-') then begin
                                                opt := Find(opt, '<');
                                                Break;
                                        end;
                                end;
                        end else begin
                                inc(opt);
                                opt := Find(opt, '<');
                        end;
                end;

                // find close tag
                clt := Find(opt + 1, '>');

                if (FS[clt - 1] = '/') then begin
                        AddChild().ConstructFrom(Copy(FS, opt + 1, clt - opt - 2));
                        Position := clt + 1;
                end else begin
                        child := AddChild();
                        child.ConstructFrom(Copy(FS, opt + 1, clt - opt - 1));
                        Position := clt + 1;
                        child.BuildFromString(FS, Position);
                end;

                clt := Position;
        end;
end;

// -----------------------------------------------------------------------------
procedure TXMLDoc.ConstructFrom(const Source: String);
type
        TState = (tsSearchName, tsSearchAtrrName, tsSearchAttrValue);
var
        attrName, attrValue, keyName, keyValue : String;
        s, c : Integer;
        state : TState;
        last_e : Integer;

        procedure XTrimLeft();
        begin
                while (c < Length(Source)) and (charinset(Source[c], [#9 ,#10, #13, ' ', '=']) = True) do begin
                        Inc(c);
                        Inc(s);
                end;
        end;

        procedure XTrimRight();
        begin
                while (c < Length(Source)) and (charinset(Source[c], [#9, #10, #13, ' ', '=']) = False) do begin
                        Inc(c);
                end;
        end;

        function CheckForEqual() : Boolean;
        begin
                last_e := c;
                while (last_e < Length(Source)) and (charinset(Source[last_e], [#9, #10, #13, ' '])) do begin
                        Inc(last_e);
                end;

                Result := (Source[last_e] = '=');
        end;
begin
        if (Source = '') then begin
                log_AddLine('XMLDoc', 'Void group detected');
                Exit;
        end;

        keyName := '';
        keyValue := '';
        c := 1;
        state := tsSearchName;

        while (c < Length(Source)) do begin
                s := c;
                case State of
                        tsSearchName : begin
                                XTrimLeft();
                                XTrimRight();
                                if (c + 1 < Length(Source)) and (CheckForEqual()) then begin
                                        state := tsSearchAttrValue;
                                        attrName := LowerCase(Copy(Source, s, c - s));
                                        c := last_e;
                                end else begin
                                        state := tsSearchAtrrName;
                                        if (c = Length(Source)) then begin
                                                NodeName := LowerCase(Copy(Source, s, c - s + 1));
                                        end else begin
                                                NodeName := LowerCase(Copy(Source, s, c - s));
                                        end;
                                end;
                        end;

                        tsSearchAtrrName: begin
                                XTrimLeft();
                                XTrimRight();
                                if (c + 1 < Length(Source)) and (CheckForEqual()) then begin
                                        state := tsSearchAttrValue;
                                        attrName := LowerCase(Copy(Source, s, c - s));
                                        c := last_e;
                                end else begin
                                        // void attrib
                                        state := tsSearchAtrrName;
                                        attrName := LowerCase(Copy(Source, s, c - s));
                                        attrValue := '';
                                        fAttributes.Add(attrName, attrValue);
                                end;
                        end;

                        tsSearchAttrValue: begin
                                XTrimLeft();
                                if (Source[s] <> '"') then begin
                                        log_AddLine('XMLDoc', 'Expected value not found');
                                        state := tsSearchAtrrName;
                                end else begin
                                        if (c + 1 <= Length(Source)) then begin
                                                inc(c);
                                        end else begin
                                                log_AddLine('XMLDoc', 'Value not closed');
                                                Exit;
                                        end;
                                        while (c < Length(Source)) and (Source[c] <> '"') do begin
                                                Inc(c);
                                        end;

                                        if (Source[c] <> '"') then begin
                                                log_AddLine('XMLDoc', 'Value not closed');
                                                Exit;
                                        end else begin
                                                attrValue := Copy(Source, s + 1, c - s - 1);
                                                attrValue := StringReplace(attrValue, '&quot;', '"', [rfReplaceAll, rfIgnoreCase]);
                                                fAttributes.Add(attrName, attrValue);
                                                if (BuildKeyValues) then begin
                                                        if (attrName = 'key') then begin
                                                                keyName := LowerCase(attrValue);
                                                        end;

                                                        if (attrName = 'val') then begin
                                                                keyValue := attrValue;
                                                        end;
                                                end;

                                                state := tsSearchAtrrName;
                                                Inc(c);
                                        end;
                                end;
                        end;
                end;
        end;

        if (ParentNode <> nil) then        
        if (BuildKeyValues) then begin
                if (keyName <> '') then begin
                        ParentNode.KeyValues.AddOrSetValue(keyName, keyValue);
                end;
        end;
end;

// -----------------------------------------------------------------------------
constructor TXMLDoc.Create(const ParentNode: TXMLDoc; const BuildKeyValues : Boolean);
begin
        Self.ParentNode := ParentNode;
        Self.BuildKeyValues := BuildKeyValues;

        Encoding := TEncoding.UTF8;
        NodeName := '';
        NodeValue := '';
        Childs := TList<TXMLDoc>.Create();
        fAttributes := TDictionary<String, String>.Create();
        KeyValues := TDictionary<String, String>.Create();
end;

// -----------------------------------------------------------------------------
destructor TXMLDoc.Destroy;
var
        P : TXMLDoc;
begin
        fAttributes.Free();
        KeyValues.Free();
        for P in Childs do begin
                P.Free();
        end;
        Childs.Free();
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetAttribDef(const Name: String; const Def: Boolean): Boolean;
var
        tmp : String;
begin
        if (fAttributes.TryGetValue(LowerCase(Name), tmp) = False) then begin
                Result := Def;
        end else begin
                Result := StrToBoolDef(tmp, Def);
        end;
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetAttribDef(const Name: String; const Def: Integer): Integer;
var
        tmp : String;
begin
        if (fAttributes.TryGetValue(LowerCase(Name), tmp) = False) then begin
                Result := Def;
        end else begin
                Result := StrToIntDef(tmp, Def);
        end;
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetAttribDef(const Name: String; const Def: Single): Single;
var
        tmp : String;
begin
        if (fAttributes.TryGetValue(LowerCase(Name), tmp) = False) then begin
                Result := Def;
        end else begin
                Result := StrToFloatDef(tmp, Def);
        end
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetAttribute(const Key: String): String;
begin
        fAttributes.TryGetValue(LowerCase(Key), Result);
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetValByKey(const Name, DefaultValue: String): String;
var
        tmp : String;
begin
        if (KeyValues.TryGetValue(LowerCase(Name), tmp) = False) then begin
                Result := DefaultValue;
        end else begin
                Result := tmp;
        end
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetValByKey(const Name: string; const DefaultValue: Boolean): Boolean;
var
        tmp : String;
begin
        if (KeyValues.TryGetValue(LowerCase(Name), tmp) = False) then begin
                Result := DefaultValue;
        end else begin
                Result := StrToBoolDef(tmp, DefaultValue);
        end;
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetValByKey(const Name: string; const DefaultValue: Single): Single;
var
        tmp : String;
begin
        if (KeyValues.TryGetValue(LowerCase(Name), tmp) = False) then begin
                Result := DefaultValue;
        end else begin
                Result := StrToFloatDef(tmp, DefaultValue);
        end
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetValByKey(const Name: string; const DefaultValue: Integer): Integer;
var
        tmp : String;
begin
        if (KeyValues.TryGetValue(LowerCase(Name), tmp) = False) then begin
                Result := DefaultValue;
        end else begin
                Result := StrToIntDef(tmp, DefaultValue);
        end;
end;

// -----------------------------------------------------------------------------
function TXMLDoc.HasAttribute(const Key: String): Boolean;
begin
        Result := fAttributes.ContainsKey(LowerCase(Key));
end;

// -----------------------------------------------------------------------------
function TXMLDoc.NextSibling(): TXMLDoc;
var
        i : Integer;
begin
        Result := nil;
        if (ParentNode = nil) then begin
                Exit;
        end;

        i := ParentNode.Childs.IndexOf(Self);
        if (i = -1) then begin
                Exit;
        end;
        inc(i);
        if (i >= ParentNode.Childs.Count) then begin
                Exit;
        end;
        Result := ParentNode.Childs[i];
end;

// -----------------------------------------------------------------------------
procedure TXMLDoc.DoReportNonLatinChars();
var
        tmp : TXMLDoc;
        ch : Integer;
        sn, sv : String;
        function Check(const Source : String; var ch : Integer) : Boolean;
        var
                i : Integer;
        begin
                Result := False;
                if (Length(Source) = 0) then begin
                        Exit(False);
                end;

                for i := 1 to Length(Source) do begin
                        if (Source[i] > #$7F) then begin
                                ch := i;
                                Exit(True);
                        end;
                end;
        end;

        function LocateMe : String;
        var
                P : TXMLDoc;
        begin
                Result := '';
                P := Self;
                while (P.ParentNode <> nil) do begin
                        Result := P.NodeName + '->' + Result;
                        if (fAttributes.ContainsKey('id')) then begin
                                Result := Result + '[' + P.fAttributes['id'] + ']';
                        end else begin
                                if (fAttributes.ContainsKey('name')) then begin
                                        Result := Result + '[' + P.fAttributes['name'] + ']';
                                end;
                        end;
                        P := P.ParentNode;
                end;
        end;
begin
        if Check(NodeName, ch) then begin
                log_AddLine('XMLReport', NodeName + '(' + IntToStr(ch) + '): ' + LocateMe);
        end;

        if Check(NodeValue, ch) then begin
                log_AddLine('XMLReport', NodeValue + '(' + IntToStr(ch) + '): ' + LocateMe);
        end;

        for sn in fAttributes.Keys do begin
                if Check(sn, ch) then begin
                        log_AddLine('XMLReport', sn + '(' + IntToStr(ch) + '): ' + LocateMe);
                end;

                sv := fAttributes[sn];
                if Check(sv, ch) then begin
                        log_AddLine('XMLReport', sv + '(' + IntToStr(ch) + '): ' + LocateMe);
                end;
        end;

        for tmp in Childs do begin
                tmp.DoReportNonLatinChars();
        end;
end;

// -----------------------------------------------------------------------------
function TXMLDoc.FindChild(NodeName: String): TXMLDoc;
var
        p : TXMLDoc;
begin
        Result := nil;
        if (Childs.Count = 0) then begin
                Exit;
        end;

        NodeName := LowerCase(NodeName);
        for P in Childs do begin
                if (P.NodeName = NodeName) then begin
                        Exit(P);
                end;
        end;
end;

// -----------------------------------------------------------------------------
function TXMLDoc.GetAttribDef(const Name, Def: String): String;
begin
        if (fAttributes.TryGetValue(LowerCase(Name), Result) = False) then begin
                Result := Def;
        end;
end;

// -----------------------------------------------------------------------------
end.
