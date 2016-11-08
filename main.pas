// -----------------------------------------------------------------------------
unit main;
// -----------------------------------------------------------------------------
interface
// -----------------------------------------------------------------------------
uses Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
PopupMenuElement, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Imaging.pngimage,
PngImageList, XMLSimpleParse, Utils, Vcl.Menus;
// -----------------------------------------------------------------------------
type
        TMainForm = class(TForm)
                MainTimer: TTimer;
                ImagesCollection: TPngImageCollection;
                DelayedHidePopupTimer: TTimer;
                TrayIcon: TTrayIcon;
                TrayPopupMenu: TPopupMenu;
                procedure MainTimerTimer(Sender: TObject);
                procedure FormCreate(Sender: TObject);
                procedure DelayedHidePopupTimerTimer(Sender: TObject);

                procedure BuildPopupMenu();
                procedure ShowAboutWindowMenuClick(Sender: TObject);
                procedure ReloadAndActivateMenuClick(Sender: TObject);
                procedure EditOptionsXMLMenuClick(Sender: TObject);
                procedure EditRepliesXMLMenuClick(Sender: TObject);
                procedure ExitMenuClick(Sender: TObject);

        protected
                procedure CreateParams(var Params: TCreateParams); override;
        end;
// -----------------------------------------------------------------------------
type
        TImageID = (
                  IMAGE_GROUP_ICON                             = 0
                , IMAGE_GROUP_ICON_SELECTED                    = 1
                , IMAGE_CHAT_CHANNEL_UNDERLAY_ICON             = 2
        );

        TWorkingMode = (
                  WORKING_MODE_CLICK                           = 0
                , WORKING_MODE_HOVER                           = 1
        );

        TPopupMethod = (
                  POPUP_METHOD_TO_PARENT                       = 0
                , POPUP_METHOD_CENTERED
        );

        TStartingPositionAlign = (
                  ALIGN_TO_CENTER                              = 0
                , ALIGN_TO_START
        );

        TGUISkin = record
                width, height : integer;

                  back_color
                , outer_frame_color
                , caption_color
                , hover_color
                : TColor;
        end;

// -----------------------------------------------------------------------------
var
        MainForm: TMainForm;
        MainDir : string = '';
        GUISkin : TGUISkin;

// -----------------------------------------------------------------------------
function IfPopupFormExists(depth, parent_node_id: integer): boolean;
function IsAtLeastOneThisDeepPopupFormExists(depth: integer): boolean;
procedure HidePopupForms(minimum_depth, allowed_parent_node_id: integer);
procedure HideAllPopupFormsDelayed(minimum_depth: integer);
procedure PopupForm(nodes: TXMLDoc; depth, parent_node_id: integer);
procedure ForImage(image_id: TImageID; callback: TCallbackProcedure<TPngImage>);
procedure InvalidateAllPopupComponents();
function GetDelayedHideMinimumDepth(): integer;
procedure ForSelectedElement(callback: TCallbackProcedure<TPOEPopupMenuElement>);
procedure SetSelectedElement(element: TPOEPopupMenuElement);
procedure InvalidateSelectedElement();
function GetEnterChatKey(): Cardinal;
function GetSendTextKey(): Cardinal;
function GetWorkingMode(): TWorkingMode;
procedure ExecutePopupWindowLogic(need_send_element_data_to_chat: boolean);
procedure SetNeedWaitToPopupHotkeyRelease();
function IsPopupHotkeyInToggleMode(): boolean;
procedure ReloadAndActivateConfig(config_folder_name : string);
// -----------------------------------------------------------------------------
implementation
// -----------------------------------------------------------------------------
uses Generics.Collections, uPopupForm, Constants, Types, uAboutForm, ShellAPI;
// -----------------------------------------------------------------------------
{$R *.dfm}
// -----------------------------------------------------------------------------
var
        OptionsDatabase : TXMLDoc = nil;
        ConfigRepliesDatabase : TXMLDoc = nil;

        ChatChannelsDatabase : TXMLDoc = nil;
        ElementsDatabase : TXMLDoc = nil;

        ActivePopupForms : TList<TPopupForm> = nil;

        WorkingMode : TWorkingMode = WORKING_MODE_CLICK;
        StartingPositionAlignX : TStartingPositionAlign = ALIGN_TO_CENTER;
        StartingPositionAlignY : TStartingPositionAlign = ALIGN_TO_CENTER;
        PopupMethod : TPopupMethod = POPUP_METHOD_CENTERED;

        SelectedElement : TPOEPopupMenuElement = nil;

        RestoreCursorPos : boolean = false;
        SavedCursorPos : TPoint;
        CursorSafeOffset : integer = -1;

        TargetWindowTitle : string = '';
        FocusedWindowBorder : TRect;

        DelayedHideMinimumDepth : integer = 0;

        SavedForegroundWindowHandle : THandle = 0;

        AvailableConfigFolders : TStringList = nil;

        // This hook only used when PopupHotkey "exclusive" value set to true.
        // This is usefull when you assign PopupKey to VK_LWIN, VK_RWIN, VK_APPS etc
        LowLevelKyboardHook : HHOOK = 0;
        PopupHotkey : Cardinal = 0;
        PopupHotkeyInToggleMode : boolean = false;
        EnterChatKey : Cardinal = 0;
        SendTextKey : Cardinal = 0;
        KeyPressedInExclusiveMode : boolean = false;
        NeedWaitToPopupHotkeyRelease : boolean = false;

// -----------------------------------------------------------------------------
function LowLevelKeyBoardProc(nCode: Integer; awParam: WPARAM; alParam: LPARAM): LRESULT; stdcall;
var
        p : PKBDLLHOOKSTRUCT;
        need_to_eat_keystroke : boolean;
begin
        need_to_eat_keystroke := false;

        if (nCode = HC_ACTION) then begin
                p := PKBDLLHOOKSTRUCT(alParam);

                if (p^.vkCode = PopupHotkey) then begin
                        case awParam  of
                                WM_KEYDOWN, WM_SYSKEYDOWN : begin
                                        KeyPressedInExclusiveMode := true;

                                        need_to_eat_keystroke := true;
                                end;
                                WM_KEYUP, WM_SYSKEYUP : begin
                                        KeyPressedInExclusiveMode := false;
                                        NeedWaitToPopupHotkeyRelease := false;

                                        need_to_eat_keystroke := true;
                                end;
                        end;
                end;
        end;

        if (need_to_eat_keystroke) then begin
                Result := 1;
        end else begin
                Result := CallNextHookEx(LowLevelKyboardHook, nCode, awParam, alParam);
        end;
end;

// -----------------------------------------------------------------------------
procedure InstallExclusiveHook();
begin
        // Hook already installed?
        if (LowLevelKyboardHook <> 0) then begin
                exit;
        end;

        LowLevelKyboardHook := SetWindowsHookEx(WH_KEYBOARD_LL, @LowLevelKeyboardProc, hInstance, 0);
end;

// -----------------------------------------------------------------------------
procedure UninstallExclusiveHook();
begin
        // Hook already uninstalled?
        if (LowLevelKyboardHook = 0) then begin
                exit;
        end;

        UnhookWindowsHookEx(LowLevelKyboardHook);
        LowLevelKyboardHook := 0;
end;

// -----------------------------------------------------------------------------
procedure SetNeedWaitToPopupHotkeyRelease();
begin
        NeedWaitToPopupHotkeyRelease := true;
end;

// -----------------------------------------------------------------------------
function IsPopupHotkeyInToggleMode(): boolean;
begin
        result := PopupHotkeyInToggleMode;
end;

// -----------------------------------------------------------------------------
function GetEnterChatKey(): Cardinal;
begin
        result := EnterChatKey;
end;

// -----------------------------------------------------------------------------
function GetSendTextKey(): Cardinal;
begin
        result := SendTextKey;
end;

// -----------------------------------------------------------------------------
function GetWorkingMode(): TWorkingMode;
begin
        result := WorkingMode;
end;

// -----------------------------------------------------------------------------
function GetFocusedWindowTitle(): string;
var
        Handle: THandle;
        Len: LongInt;
        Title: string;
begin
        Result := '';

        Handle := GetForegroundWindow();

        if (Handle <> 0) then begin
                Len := GetWindowTextLength(Handle) + 1;
                SetLength(Title, Len);
                GetWindowText(Handle, PChar(Title), Len);

                Result := TrimRight(Title);
        end;
end;

// -----------------------------------------------------------------------------
procedure UpdateFocusedWindowBorder();
var
        Handle: THandle;
        window_info : TWindowInfo;
begin
        FocusedWindowBorder := Bounds(0, 0, Screen.Width, Screen.Height);

        Handle := GetForegroundWindow();

        if (Handle <> 0) then begin
                if (GetWindowInfo(Handle, window_info)) then begin
                        FocusedWindowBorder := window_info.rcClient;
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure InvalidateSelectedElement();
begin
        SelectedElement := nil;
end;

// -----------------------------------------------------------------------------
procedure ForSelectedElement(callback: TCallbackProcedure<TPOEPopupMenuElement>);
begin
        if (Assigned(SelectedElement)) then begin
                callback(SelectedElement);
        end;
end;

// -----------------------------------------------------------------------------
procedure SetSelectedElement(element: TPOEPopupMenuElement);
begin
        SelectedElement := element;
end;

// -----------------------------------------------------------------------------
function GetPopupComponentScreenYPos(depth, target_node_id: integer): integer;
var
        PopupForm : TPopupForm;
        i : integer;
begin
        for PopupForm in ActivePopupForms do begin
                if (PopupForm.depth = depth) then begin
                        with PopupForm do begin
                                if (ComponentCount > 0) then begin
                                        for i := 0 to ComponentCount - 1 do begin
                                                if (Components[i] is TPOEPopupMenuElement) then begin
                                                        with (Components[i] as TPOEPopupMenuElement) do begin
                                                                if (node_id = 0) then begin
                                                                        exit(ClientToScreen(Point(0, Top)).Y + (target_node_id * GUISkin.height) - (target_node_id * 1));
                                                                end;
                                                        end;
                                                end;
                                        end;
                                end;
                        end;
                end;
        end;

        result := 0;
end;

// -----------------------------------------------------------------------------
procedure InvalidateAllPopupComponents();
var
        i : integer;
        PopupForm : TPopupForm;
begin
        InvalidateSelectedElement();

        if (ActivePopupForms.Count > 0) then begin
                for PopupForm in ActivePopupForms do begin
                        with PopupForm do begin
                                if (ComponentCount > 0) then begin
                                        for i := 0 to ComponentCount - 1 do begin
                                                if (Components[i] is TPOEPopupMenuElement) then begin
                                                        with (Components[i] as TPOEPopupMenuElement) do begin
                                                                MouseOnMe := false;
                                                                Invalidate();
                                                        end;
                                                end;
                                        end;
                                end;
                        end;
                end;
        end;
end;

// -----------------------------------------------------------------------------
function GetDelayedHideMinimumDepth(): integer;
begin
        result := DelayedHideMinimumDepth;
end;

// -----------------------------------------------------------------------------
procedure ForImage(image_id: TImageID; callback: TCallbackProcedure<TPngImage>);
begin
        if ((integer(image_id) >= 0) and (integer(image_id) < MainForm.ImagesCollection.Items.Count)) then begin
                callback(MainForm.ImagesCollection.Items.Items[integer(image_id)].PngImage);
        end;
end;

// -----------------------------------------------------------------------------
procedure HideAllPopupForms();
var
        PopupForm : TPopupForm;
begin
        InvalidateSelectedElement();

        if (ActivePopupForms.Count > 0) then begin
                for PopupForm in ActivePopupForms do begin
                        PopupForm.Destroy();
                end;

                ActivePopupForms.Clear();
        end;
end;

// -----------------------------------------------------------------------------
function IfPopupFormExists(depth, parent_node_id: integer): boolean;
var
        PopupForm : TPopupForm;
begin
        for PopupForm in ActivePopupForms do begin
                if ((PopupForm.depth = depth) and (PopupForm.parent_node_id = parent_node_id)) then begin
                        exit(true);
                end;
        end;

        result := false;
end;

// -----------------------------------------------------------------------------
function IsAtLeastOneThisDeepPopupFormExists(depth: integer): boolean;
var
        PopupForm : TPopupForm;
begin
        for PopupForm in ActivePopupForms do begin
                if (PopupForm.depth >= depth) then begin
                        exit(true);
                end;
        end;

        result := false;

end;

// -----------------------------------------------------------------------------
procedure HidePopupForms(minimum_depth, allowed_parent_node_id: integer);
var
        i : integer;
begin
        if (ActivePopupForms.Count > 0) then begin
                for i := ActivePopupForms.Count - 1 downto 0 do begin
                        with ActivePopupForms.Items[i] do begin
                                if ((depth > minimum_depth) or ((depth = minimum_depth) and (parent_node_id <> allowed_parent_node_id))) then begin
                                        Destroy();
                                        ActivePopupForms.Delete(i);
                                end;
                        end;
                end;
        end;

        InvalidateAllPopupComponents();
end;

// -----------------------------------------------------------------------------
procedure HideAllPopupFormsDelayed(minimum_depth: integer);
begin
        DelayedHideMinimumDepth := minimum_depth;

        MainForm.DelayedHidePopupTimer.Enabled := true;
end;

// -----------------------------------------------------------------------------
procedure PopupForm(nodes: TXMLDoc; depth, parent_node_id: integer);
var
        PopupForm : TPopupForm;
        PopupElement : TPOEPopupMenuElement;
        total_elements_count : integer;
        i : integer;
        offset_y : integer;
begin
        if (IfPopupFormExists(depth, parent_node_id)) then begin
                exit;
        end;
        HidePopupForms(depth, parent_node_id);

        if (nodes.Childs.Count = 0) then begin
                exit;
        end;

        // Prepare popup form
        PopupForm := TPopupForm.Create(MainForm);

        total_elements_count := 0;
        offset_y := 0;

        for i := 0 to nodes.Childs.Count - 1 do begin
                // Add elements to popup form
                PopupElement := TPOEPopupMenuElement.Create(PopupForm);
                with PopupElement do begin
                        Left := 0;
                        Top := offset_y;

                        // Caption
                        Caption := nodes.Childs[i].GetAttribDef('value', '');

                        if (Caption = '') then begin
                                Continue;
                        end;

                        // Special elements
                        Caption := StringReplace(Caption, '%TOOL_POE_FORUM_THREAD_ID%', TOOL_POE_FORUM_THREAD_ID, [rfReplaceAll, rfIgnoreCase]);
                        Caption := StringReplace(Caption, '%TOOL_VERSION%', TOOL_VERSION, [rfReplaceAll, rfIgnoreCase]);

                        // Default channel
                        try
                                target_channel := TChatChannelID(nodes.Childs[i].GetAttribDef('channel', integer(GetDefaultChatChannel())));
                        except
                                target_channel := GetDefaultChatChannel();
                        end;

                        // Allow to change channels?
                        allow_channel_change := nodes.Childs[i].GetAttribDef('allow_channel_change', false);

                        Visible := true;
                        Parent := PopupForm;
                        Config := nodes.Childs[i];
                        node_id := i;

                        UpdateValues();
                end;

                inc(total_elements_count);
                inc(offset_y, GUISkin.height - 1);
        end;

        PopupForm.depth := depth;
        PopupForm.parent_node_id := parent_node_id;
        with PopupForm do begin
                Width  := GUISkin.width;
                Height := (total_elements_count * GUISkin.height) - ((total_elements_count - 1) * 1);

                case StartingPositionAlignX of
                        ALIGN_TO_START : begin
                                Left := FocusedWindowBorder.Left;
                        end;
                        else begin // ALIGN_TO_CENTER
                                Left := FocusedWindowBorder.Left + FocusedWindowBorder.Width div 2 - Width div 2;
                        end;
                end;
                case StartingPositionAlignY of
                        ALIGN_TO_START : begin
                                Top := FocusedWindowBorder.Top;
                        end;
                        else begin // ALIGN_TO_CENTER
                                Top := FocusedWindowBorder.Top + FocusedWindowBorder.Height div 2 - Height div 2;
                        end;
                end;

                if (depth <> 0) then begin
                        Left := Left + (depth * GUISkin.width) - (depth * 1);
                        Top := GetPopupComponentScreenYPos(depth - 1, parent_node_id);

                        case PopupMethod of
                                POPUP_METHOD_CENTERED : begin
                                        Top := Top - Height div 2 + GUISkin.height div 2;
                                end;
                                POPUP_METHOD_TO_PARENT : begin
                                        // Do nothing
                                end;
                        end;
                end;

                // Correct top pos
                if (Top + Height > Screen.Height) then begin
                        Top := Screen.Height - Height;
                end;
                if (Top < 0) then begin
                        Top := 0;
                end;

                // Popup without losing focus
                ShowWindow(Handle, SW_SHOWNOACTIVATE);
                Visible := true;
        end;

        // Register form
        ActivePopupForms.Add(PopupForm);
end;

// -----------------------------------------------------------------------------
function IsKeyPressed(const VirtKeyCode: Integer): Boolean;
begin
        Result := GetKeyState(VirtKeyCode) < 0;
end;

// -----------------------------------------------------------------------------
procedure TMainForm.CreateParams(var Params: TCreateParams);
begin
        inherited;

        // Hide from taskbar
        Params.ExStyle := Params.ExStyle and (not WS_EX_APPWINDOW);
        Params.WndParent := Application.Handle;
end;

// -----------------------------------------------------------------------------
procedure TMainForm.MainTimerTimer(Sender: TObject);
var
        key_pressed : boolean;
        need_show : boolean;
begin
        // Delete about form...
        if (Assigned(AboutForm)) then begin
                if (not AboutForm.Visible) then begin
                        AboutForm.Free();
                        AboutForm := nil;
                end;
        end;

        if (PopupHotkeyInToggleMode) then begin
                if (KeyPressedInExclusiveMode) then begin
                        // If waiting for hotkey release?
                        if (NeedWaitToPopupHotkeyRelease) then begin
                                exit;
                        end;

                        SetNeedWaitToPopupHotkeyRelease();

                        need_show := ActivePopupForms.Count = 0;
                end else begin
                        NeedWaitToPopupHotkeyRelease := false;

                        exit;
                end;
        end else begin
                key_pressed := IsKeyPressed(PopupHotkey);
                if (key_pressed or KeyPressedInExclusiveMode) then begin
                        // If waiting for hotkey release?
                        if (NeedWaitToPopupHotkeyRelease) then begin
                                exit;
                        end;

                        need_show := true;
                end else begin
                        KeyPressedInExclusiveMode := false;
                        NeedWaitToPopupHotkeyRelease := false;

                        need_show := false;
                end;
        end;

        if (need_show) then begin
                if (Assigned(AboutForm)) then begin
                        if (AboutForm.Visible) then begin
                                AboutForm.Free();
                                AboutForm := nil;
                        end;
                end;

                if (ActivePopupForms.Count = 0) then begin
                        // Check for target window
                        if ((TargetWindowTitle <> '') and (GetFocusedWindowTitle() <> TargetWindowTitle)) then begin
                                exit;
                        end else begin
                                UpdateFocusedWindowBorder();
                        end;

                        // Save focused window handle
                        SavedForegroundWindowHandle := GetForegroundWindow();

                        if (CursorSafeOffset <> -1) then begin
                                // Save cursor pos
                                GetCursorPos(SavedCursorPos);

                                // Adjust cursor
                                SetCursorPos(FocusedWindowBorder.Left + FocusedWindowBorder.Width div 2 - GUISkin.width div 2 - CursorSafeOffset, FocusedWindowBorder.Top + FocusedWindowBorder.Height div 2);
                        end;

                        // Popup form
                        PopupForm(ElementsDatabase, 0, -1);
                end;
        end else begin
                ExecutePopupWindowLogic(WorkingMode = WORKING_MODE_HOVER);
        end;
end;

// -----------------------------------------------------------------------------
procedure TMainForm.ShowAboutWindowMenuClick(Sender: TObject);
begin
        HideAllPopupForms();

        if (Assigned(AboutForm)) then begin
                AboutForm.Free();
        end;

        AboutForm := TAboutForm.Create(MainForm);
        AboutForm.Show();
end;

// -----------------------------------------------------------------------------
procedure ForAvailableConfig(config_index: integer; callback: TCallbackProcedure<string>);
var
        index : integer;
        config_folder_name : string;
begin
        index := 0;
        for config_folder_name in AvailableConfigFolders do begin
                if (index = config_index) then begin
                        callback(config_folder_name);
                        exit;
                end;

                inc(index);
        end;
end;

// -----------------------------------------------------------------------------
procedure TMainForm.ReloadAndActivateMenuClick(Sender: TObject);
begin
        ForAvailableConfig((Sender as TMenuItem).Parent.Tag, procedure(config_folder_name : string)
        begin
                ReloadAndActivateConfig(config_folder_name);
        end);
end;

// -----------------------------------------------------------------------------
procedure TMainForm.EditOptionsXMLMenuClick(Sender: TObject);
begin
        ForAvailableConfig((Sender as TMenuItem).Parent.Tag, procedure(config_folder_name : string)
        begin
                ShellExecute(self.Handle, 'open', PChar(MainDir + '\' + config_folder_name + '\' + CONFIG_OPTIONS_FILENAME), nil, nil, SW_NORMAL);
        end);
end;

// -----------------------------------------------------------------------------
procedure TMainForm.EditRepliesXMLMenuClick(Sender: TObject);
begin
        ForAvailableConfig((Sender as TMenuItem).Parent.Tag, procedure(config_folder_name : string)
        begin
                ShellExecute(self.Handle, 'open', PChar(MainDir + '\' + config_folder_name + '\' + CONFIG_REPLIES_FILENAME), nil, nil, SW_NORMAL);
        end);
end;

// -----------------------------------------------------------------------------
procedure TMainForm.ExitMenuClick(Sender: TObject);
begin
        Close();
end;

// -----------------------------------------------------------------------------
procedure TMainForm.BuildPopupMenu();
var
        at_least_one_config_found : boolean;
        config_folder_name : string;
        temp_menu_item : TMenuItem;
        index_tag : integer;
        // ---------------------------------------------------------------------
        function GetPopupMenuItem(param_caption: string; on_click: TNotifyEvent = nil): TMenuItem;
        begin
                result := TMenuItem.Create(Self);
                with result do begin
                        Caption := param_caption;
                        OnClick := on_click;
                end;
        end;
        // ---------------------------------------------------------------------
        procedure EnumAllConfigFolders(foldername : string);
        var
                search_result : TSearchRec;
        begin
                AvailableConfigFolders.Clear();

                if (foldername[Length(foldername)] <> '\') then begin
                        foldername := foldername + '\';
                end;

                if (FindFirst(foldername + '*', faDirectory, search_result) = 0) then begin
                        repeat
                                if ((search_result.Name = '.') or (search_result.Name = '..')) then begin
                                        Continue;
                                end;

                                if ((search_result.attr and faDirectory) <> faDirectory) then begin
                                        Continue;
                                end;

                                AvailableConfigFolders.Add(search_result.Name);
                        until (FindNext(search_result) <> 0);

                        FindClose(search_result);
                end;
        end;
        // ---------------------------------------------------------------------
begin
        EnumAllConfigFolders(MainDir);
        at_least_one_config_found := AvailableConfigFolders.Count > 0;

        TrayPopupMenu.Items.Add(GetPopupMenuItem('About', ShowAboutWindowMenuClick));

        if (at_least_one_config_found) then begin
                TrayPopupMenu.Items.Add(GetPopupMenuItem('-'));
        end;

        index_tag := 0;
        for config_folder_name in AvailableConfigFolders do begin
                temp_menu_item := GetPopupMenuItem('Config for ' + config_folder_name);
                with temp_menu_item do begin
                        Tag := index_tag;

                        Add(GetPopupMenuItem('Reload and activate', ReloadAndActivateMenuClick));
                        Add(GetPopupMenuItem('Edit ''Options.xml''', EditOptionsXMLMenuClick));
                        Add(GetPopupMenuItem('Edit ''Replies.xml''', EditRepliesXMLMenuClick));
                end;

                TrayPopupMenu.Items.Add(temp_menu_item);

                inc(index_tag);
        end;

        if (at_least_one_config_found) then begin
                TrayPopupMenu.Items.Add(GetPopupMenuItem('-'));
        end;
        TrayPopupMenu.Items.Add(GetPopupMenuItem('Exit', ExitMenuClick));
end;

// -----------------------------------------------------------------------------
procedure TMainForm.FormCreate(Sender: TObject);
begin
        MainDir := ExtractFilePath(ParamStr(0));

        AvailableConfigFolders := TStringList.Create();

        TrayIcon.Icon.Assign(Application.Icon);
        TrayIcon.Hint := TOOL_NAME + ' v' + TOOL_VERSION;

        FocusedWindowBorder := Bounds(0, 0, Screen.Width, Screen.Height);

        // Create list
        ActivePopupForms := TList<TPopupForm>.Create();

        // Prepare popup menu
        BuildPopupMenu();

        // Load first config
        ForAvailableConfig(0, procedure(config_folder_name : string)
        begin
                ReloadAndActivateConfig(config_folder_name);
        end);
end;

// -----------------------------------------------------------------------------
procedure TMainForm.DelayedHidePopupTimerTimer(Sender: TObject);
begin
        HidePopupForms(DelayedHideMinimumDepth, -1);

        DelayedHidePopupTimer.Enabled := false;
end;

// -----------------------------------------------------------------------------
procedure ExecutePopupWindowLogic(need_send_element_data_to_chat: boolean);
begin
        if (ActivePopupForms.Count > 0) then begin
                // Restore focused window handle
                if (SavedForegroundWindowHandle <> 0) then begin
                        // Still valid window?
                        if (IsWindow(SavedForegroundWindowHandle)) then begin
                                SetForegroundWindow(SavedForegroundWindowHandle);

                                // Wait for window to restore
                                while (GetForegroundWindow() <> SavedForegroundWindowHandle) do begin
                                        Application.ProcessMessages();
                                        Sleep(100);
                                end;
                        end;
                end;

                // Do we need to send something?
                if (need_send_element_data_to_chat) then begin
                        Sleep(100);
                        ForSelectedElement(procedure(element : TPOEPopupMenuElement)
                        begin
                                element.SendToChat();
                        end);
                end;

                // Hide all popup forms
                HideAllPopupForms();

                // Restore cursor if we need
                if (CursorSafeOffset <> -1) then begin
                        if (RestoreCursorPos) then begin
                                // Restore cursor pos
                                SetCursorPos(SavedCursorPos.X, SavedCursorPos.Y);
                        end;
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure ReloadAndActivateConfig(config_folder_name : string);
var
        OptionChild : TXMLDoc;
        exclusive_mode : boolean;
        // ---------------------------------------------------------------------
        function ConvertTextToStartingPositionAlign(text: string): TStartingPositionAlign;
        begin
                text := LowerCase(text);

                if (text = 'center') then begin
                        result := ALIGN_TO_CENTER;
                end else if (text = 'start') then begin
                        result := ALIGN_TO_START;
                end else begin
                        result := ALIGN_TO_CENTER;
                end;
        end;
        // ---------------------------------------------------------------------
begin
        HideAllPopupForms();
        UninstallExclusiveHook();

        // Unload databases
        if (Assigned(OptionsDatabase)) then begin
                OptionsDatabase.Free();
                OptionsDatabase := nil;
        end;
        if (Assigned(ConfigRepliesDatabase)) then begin
                ConfigRepliesDatabase.Free();
                ConfigRepliesDatabase := nil;
        end;

        // Load options database
        OptionsDatabase := TXMLDoc.Create(nil, true);
        OptionsDatabase.LoadFromFile(MainDir + '\' + config_folder_name + '\' + CONFIG_OPTIONS_FILENAME);

        // WorkingMode
        OptionChild := OptionsDatabase.FindChild('WorkingMode');
        if (Assigned(OptionChild)) then begin
                WorkingMode := TWorkingMode(OptionChild.GetAttribDef('value', integer(WORKING_MODE_CLICK)));
        end;

        // PopupMethod
        OptionChild := OptionsDatabase.FindChild('PopupMethod');
        if (Assigned(OptionChild)) then begin
                PopupMethod := TPopupMethod(OptionChild.GetAttribDef('value', integer(POPUP_METHOD_TO_PARENT)));
        end;

        // StartingPositionAlign
        OptionChild := OptionsDatabase.FindChild('StartingPositionAlign');
        if (Assigned(OptionChild)) then begin
                StartingPositionAlignX := ConvertTextToStartingPositionAlign(OptionChild.GetAttribDef('x', 'center'));
                StartingPositionAlignY := ConvertTextToStartingPositionAlign(OptionChild.GetAttribDef('y', 'center'));
        end;

        // PopupDelay
        OptionChild := OptionsDatabase.FindChild('PopupDelay');
        if (Assigned(OptionChild)) then begin
                MainForm.DelayedHidePopupTimer.Interval := OptionChild.GetAttribDef('value', 115);
        end;

        // PopupHotkey
        OptionChild := OptionsDatabase.FindChild('PopupHotkey');
        if (Assigned(OptionChild)) then begin
                PopupHotkey := StrToInt(OptionChild.GetAttribDef('value', '0x0'));

                exclusive_mode := OptionChild.GetAttribDef('exclusive', false);

                PopupHotkeyInToggleMode := OptionChild.GetAttribDef('toggle', false);
                if (WorkingMode = WORKING_MODE_HOVER) then begin
                        PopupHotkeyInToggleMode := false;
                end;
                if (PopupHotkeyInToggleMode) then begin
                        exclusive_mode := true;
                end;

                KeyPressedInExclusiveMode := false;
                NeedWaitToPopupHotkeyRelease := false;

                if (exclusive_mode) then begin
                        InstallExclusiveHook();
                end;
        end else begin
                PopupHotkey := 0;
        end;

        // EnterChatKey
        OptionChild := OptionsDatabase.FindChild('EnterChatKey');
        if (Assigned(OptionChild)) then begin
                EnterChatKey := StrToInt(OptionChild.GetAttribDef('value', '0x0'));
        end;

        // SendTextKey
        OptionChild := OptionsDatabase.FindChild('SendTextKey');
        if (Assigned(OptionChild)) then begin
                SendTextKey := StrToInt(OptionChild.GetAttribDef('value', '0x0'));
        end;

        // RestoreCursorPos
        OptionChild := OptionsDatabase.FindChild('RestoreCursorPos');
        if (Assigned(OptionChild)) then begin
                RestoreCursorPos := OptionChild.GetAttribDef('value', false);
        end;

        // CursorSafeOffset
        OptionChild := OptionsDatabase.FindChild('CursorSafeOffset');
        if (Assigned(OptionChild)) then begin
                CursorSafeOffset := OptionChild.GetAttribDef('value', CursorSafeOffset);
        end;

        // TargetWindowTitle
        OptionChild := OptionsDatabase.FindChild('TargetWindowTitle');
        if (Assigned(OptionChild)) then begin
                TargetWindowTitle := OptionChild.GetAttribDef('value', '');
        end;

        // GUISkin
        OptionChild := OptionsDatabase.FindChild('GUISkin');
        if (Assigned(OptionChild)) then begin
                with GUISkin do begin
                        width             := StrToInt(OptionChild.GetAttribDef('width', '250')).Clamp(110, 400);
                        height            := StrToInt(OptionChild.GetAttribDef('height', '70')).Clamp(30, 125);

                        back_color        := StrToInt(OptionChild.GetAttribDef('back_color', '0x0'));
                        outer_frame_color := StrToInt(OptionChild.GetAttribDef('outer_frame_color', '0x0'));
                        caption_color     := StrToInt(OptionChild.GetAttribDef('caption_color', '0x0'));
                        hover_color       := StrToInt(OptionChild.GetAttribDef('hover_color', '0x0'));
                end;
        end;

        // Load replies database
        ConfigRepliesDatabase := TXMLDoc.Create(nil, true);
        ConfigRepliesDatabase.LoadFromFile(MainDir + '\' + config_folder_name + '\' + CONFIG_REPLIES_FILENAME);

        // Load chat channels
        ChatChannelsDatabase := ConfigRepliesDatabase.FindChild('ChatChannels');
        LoadChatChannels(ChatChannelsDatabase);

        // Load elements
        ElementsDatabase := ConfigRepliesDatabase.FindChild('Elements');
end;

// -----------------------------------------------------------------------------
end.
