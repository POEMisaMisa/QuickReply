// -----------------------------------------------------------------------------
unit Utils;
// -----------------------------------------------------------------------------
interface
// -----------------------------------------------------------------------------
uses Types, Classes, SysUtils, Graphics, Vcl.Imaging.pngimage, Generics.Collections,
Winapi.Windows;
// -----------------------------------------------------------------------------
type
        TCallbackProcedure<T> = reference to procedure(typename : T);
        TDataArrayCallback<T> = reference to procedure(var typename : T);
        TDataArrayCallbackConst<T> = reference to procedure(typename : T);
        TSendKeysHook = reference to procedure(InputSequence: TList<TInput>);

        Logic = class
        public
                class function IfThen<T>(value: boolean; atrue, afalse: T): T; static;
        end;

        DataArray<T> = record
                data: array of T;
                procedure Append(const value: T); overload;
                procedure Append(values: array of T); overload;
                procedure Assign(value: array of T);
                function Count(): integer;
                function NotEmpty(): boolean;
                procedure Clear();
                procedure ForEach(callback: TDataArrayCallback<T>); overload;
                procedure ForEachReverse(callback: TDataArrayCallback<T>); overload;
                procedure ForEach(callback: TDataArrayCallbackConst<T>); overload;
                procedure ForEachReverse(callback: TDataArrayCallbackConst<T>); overload;
        end;

        TByteHelper = record helper for Byte
                function Clamp(const Min, Max : Byte): Byte;
        end;

        TSmallIntHelper = record helper for SmallInt
                function Clamp(const Min, Max : SmallInt): SmallInt;
        end;

        TIntegerHelper = record helper for Integer
                function Clamp(const Min, Max : Integer): Integer;
        end;

        TSingleHelper = record helper for Single
                function Clamp(const Min, Max : Single): Single;
        end;

        TStringHelper = record helper for string
                procedure ForEachToken(delimiter : Char; callback : TCallbackProcedure<string>);
        end;

type
        tagKBDLLHOOKSTRUCT = record
                vkCode : DWORD;
                scanCode : DWORD;
                flags : DWORD;
                time : DWORD;
                dwExtraInfo : DWORD;
        end;
        KBDLLHOOKSTRUCT   = tagKBDLLHOOKSTRUCT;
        LPKBDLLHOOKSTRUCT = ^KBDLLHOOKSTRUCT;
        PKBDLLHOOKSTRUCT  = ^KBDLLHOOKSTRUCT;

// -----------------------------------------------------------------------------
procedure DrawPNGImage(image: TPngImage; ACanvas: TCanvas; x, y: integer);
procedure SendKeys(const value: string; PreHook, PostHook: TSendKeysHook);
function GetInputCommandCharacterPress(character: Char): TInput;
function GetInputCommandCharacterRelease(character: Char): TInput;
function GetInputCommandKeyPress(keycode: Cardinal): TInput;
function GetInputCommandKeyRelease(keycode: Cardinal): TInput;
// -----------------------------------------------------------------------------
implementation
// -----------------------------------------------------------------------------
class function Logic.IfThen<T>(value: boolean; atrue, afalse: T): T;
begin
        if (value) then begin
                result := atrue;
        end else begin
                result := afalse;
        end;
end;

// -----------------------------------------------------------------------------
procedure DrawPNGImage(image: TPngImage; ACanvas: TCanvas; x, y: integer);
begin
        image.Draw(ACanvas, Bounds(x, y, image.Width, image.Height));
end;

// -----------------------------------------------------------------------------
procedure SendKeys(const value: string; PreHook, PostHook: TSendKeysHook);
var
        character: Char;
        InputSequence: TList<TInput>;
begin
        InputSequence := TList<TInput>.Create();

        try
                if (Assigned(PreHook)) then begin
                        PreHook(InputSequence);
                end;

                for character in value do begin
                        if (character = #10) then begin // Ignore new line character
                                Continue;
                        end;

                        InputSequence.Add(GetInputCommandCharacterPress(character));
                        InputSequence.Add(GetInputCommandCharacterRelease(character));
                end;

                if (Assigned(PostHook)) then begin
                        PostHook(InputSequence);
                end;

                SendInput(InputSequence.Count, InputSequence.List[0], SizeOf(TInput));

        finally
                InputSequence.Free();
        end;
end;

// -----------------------------------------------------------------------------
function GetInputCommandCharacterPress(character: Char): TInput;
begin
        result := Default(TInput);

        result.Itype := INPUT_KEYBOARD;
        result.ki.dwFlags := KEYEVENTF_UNICODE;
        result.ki.wScan := Ord(character);
end;

// -----------------------------------------------------------------------------
function GetInputCommandCharacterRelease(character: Char): TInput;
begin
        result := Default(TInput);

        result.Itype := INPUT_KEYBOARD;
        result.ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
        result.ki.wScan := Ord(character);
end;

// -----------------------------------------------------------------------------
function GetInputCommandKeyPress(keycode: Cardinal): TInput;
begin
        result := Default(TInput);

        result.Itype := INPUT_KEYBOARD;
        result.ki.dwFlags := 0;
        result.ki.wVk := keycode;
end;

// -----------------------------------------------------------------------------
function GetInputCommandKeyRelease(keycode: Cardinal): TInput;
begin
        result := Default(TInput);

        result.Itype := INPUT_KEYBOARD;
        result.ki.dwFlags := KEYEVENTF_KEYUP;
        result.ki.wVk := keycode;
end;

// -----------------------------------------------------------------------------
{ DataArray<T> }
// -----------------------------------------------------------------------------
procedure DataArray<T>.Append(const value: T);
begin
        SetLength(data, Length(data) + 1);
        data[high(data)] := value;
end;

// -----------------------------------------------------------------------------
procedure DataArray<T>.Append(values: array of T);
var
        value: T;
begin
        for value in values do begin
                Append(value);
        end;
end;

// -----------------------------------------------------------------------------
procedure DataArray<T>.Assign(value: array of T);
var
        value_i : T;
begin
        Clear();

        for value_i in value do begin
                Append(value_i);
        end;
end;

// -----------------------------------------------------------------------------
function DataArray<T>.Count(): integer;
begin
        result := Length(data);
end;

// -----------------------------------------------------------------------------
procedure DataArray<T>.Clear();
begin
        SetLength(data, 0);
end;

// -----------------------------------------------------------------------------
function DataArray<T>.NotEmpty(): boolean;
begin
        result := Count() > 0;
end;

// -----------------------------------------------------------------------------
procedure DataArray<T>.ForEach(callback: TDataArrayCallback<T>);
var
        i : integer;
begin
        if (NotEmpty()) then begin
                for i := 0 to Count - 1 do begin
                        callback(data[i]);
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure DataArray<T>.ForEachReverse(callback: TDataArrayCallback<T>);
var
        i : integer;
begin
        if (NotEmpty()) then begin
                for i := Count - 1 downto 0 do begin
                        callback(data[i]);
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure DataArray<T>.ForEach(callback: TDataArrayCallbackConst<T>);
var
        i : integer;
begin
        if (NotEmpty()) then begin
                for i := 0 to Count - 1 do begin
                        callback(data[i]);
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure DataArray<T>.ForEachReverse(callback: TDataArrayCallbackConst<T>);
var
        i : integer;
begin
        if (NotEmpty()) then begin
                for i := Count - 1 downto 0 do begin
                        callback(data[i]);
                end;
        end;
end;

// -----------------------------------------------------------------------------
// TByteHelper
// -----------------------------------------------------------------------------
function TByteHelper.Clamp(const Min, Max: Byte): Byte;
begin
        if (Self > max) then begin
                Self := max;
        end;
        if (Self < min) then begin
                Self := min;
        end;
        result := Self;
end;

// -----------------------------------------------------------------------------
// TSmallIntHelper
// -----------------------------------------------------------------------------
function TSmallIntHelper.Clamp(const Min, Max: SmallInt): SmallInt;
begin
        if (Self > max) then begin
                Self := max;
        end;
        if (Self < min) then begin
                Self := min;
        end;
        result := Self;
end;

// -----------------------------------------------------------------------------
// TIntegerHelper
// -----------------------------------------------------------------------------
function TIntegerHelper.Clamp(const Min, Max: Integer): Integer;
begin
        if (Self > max) then begin
                Self := max;
        end;
        if (Self < min) then begin
                Self := min;
        end;
        result := Self;
end;

// -----------------------------------------------------------------------------
// TSingleHelper
// -----------------------------------------------------------------------------
function TSingleHelper.Clamp(const Min, Max: Single): Single;
begin
        if (Self > max) then begin
                Self := max;
        end;
        if (Self < min) then begin
                Self := min;
        end;
        result := Self;
end;

// -----------------------------------------------------------------------------
{ TStringHelper }
// -----------------------------------------------------------------------------
procedure TStringHelper.ForEachToken(delimiter: Char; callback : TCallbackProcedure<string>);
var
        p : integer;
        temp_str, token: string;
begin
        temp_str := self;

        repeat
                p := Pos(delimiter, temp_str);
                if (p > 0) then begin
                        // Token found
                        token := Trim(Copy(temp_str, 1, p - 1));

                        temp_str := Trim(Copy(temp_str, p + 1, Length(temp_str) - p));
                end else begin
                        // Token not found
                        token := Trim(temp_str);

                        temp_str := '';
                end;

                if (token <> '') then begin
                        callback(token);
                end;
        until temp_str = '';
end;

// -----------------------------------------------------------------------------
end.
