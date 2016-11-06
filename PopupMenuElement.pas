// -----------------------------------------------------------------------------
unit PopupMenuElement;
// -----------------------------------------------------------------------------
interface
// -----------------------------------------------------------------------------
uses Windows, Types, SysUtils, Classes, Controls, Graphics, StdCtrls, Math,
Utils, XMLSimpleParse, Winapi.Messages;
// -----------------------------------------------------------------------------
const
        CHAT_CHANNEL_NULL        = 0;

type
        TChatChannelID = byte;
        TAllowedChatChannels = set of TChatChannelID;

        TChatChannel = record
                id : TChatChannelID;
                symbol : Char;
                color : TColor;
                hidden : boolean;
                config : TXMLDoc;
        end;

// -----------------------------------------------------------------------------
        TPOEPopupMenuElement = class(TCustomControl)
        private
                is_group : boolean;

        private
                GfxBmp : TBitmap;

        private
                AllowedChatChannels : TAllowedChatChannels;
                AllowedChatChannels_cached : boolean;

                procedure RefreshAllowedChatChannels();

        protected
                procedure Paint(); override;

        public
                constructor Create(AOwner: TComponent); override;
                destructor Destroy(); override;

                procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
                procedure CMMouseEnter(var msg: TMessage); message CM_MOUSEENTER;
                procedure CMMouseLeave(var msg: TMessage); message CM_MOUSELEAVE;
                procedure EventOnClick(Sender: TObject);

                procedure UpdateValues();
                procedure ElementLogic();
                procedure SendToChat();

        public
                Config : TXMLDoc;
                MouseOnMe : boolean;

        public
                node_id : integer;
                target_channel : TChatChannelID;
                allow_channel_change : boolean;

        published
                property Caption;
                property OnClick;
        end;

// -----------------------------------------------------------------------------
procedure LoadChatChannels(chat_channels_config: TXMLDoc);
function GetDefaultChatChannel(): TChatChannelID;
// -----------------------------------------------------------------------------
implementation
// -----------------------------------------------------------------------------
uses Constants, main, Vcl.Imaging.pngimage, uPopupForm, Generics.Collections;
// -----------------------------------------------------------------------------
var
        ChatChannels : DataArray<TChatChannel>;
        DefaultChatChannel : TChatChannelID = CHAT_CHANNEL_NULL;

// -----------------------------------------------------------------------------
procedure ForChatChannel(channel_id : TChatChannelID; callback: TCallbackProcedure<TChatChannel>);
begin
        ChatChannels.ForEach(procedure(ChatChannel: TChatChannel)
        begin
                if (ChatChannel.id = channel_id) then begin
                        if (Assigned(ChatChannel.config)) then begin // Make sure that config is valid
                                callback(ChatChannel);
                        end;
                end;
        end);
end;

// -----------------------------------------------------------------------------
constructor TPOEPopupMenuElement.Create(AOwner: TComponent);
begin
        inherited;

        Font.Name  := 'Verdana';
        Font.Style := [];
        Font.Size  := 10;

        Width  := GUISkin.width;
        Height := GUISkin.height;

        GfxBmp := TBitmap.Create();
        GfxBmp.PixelFormat := pf32bit;

        Cursor := crArrow;

        Config := nil;

        MouseOnMe := false;
        OnClick := EventOnClick;

        AllowedChatChannels := [];
        AllowedChatChannels_cached := false;
end;

// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.UpdateValues();
begin
        is_group := Config.Childs.Count > 0;
        if (is_group) then begin
                Font.Size := 12;
        end;
end;

// -----------------------------------------------------------------------------
destructor TPOEPopupMenuElement.Destroy();
begin
        GfxBmp.Free();

        inherited;
end;
// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.Paint();
var
        ClientRect: TRect;
        draw_format : Cardinal;
        offset_x, offset_y : integer;
        sub_popup_exists : boolean;
        need_draw_hover : boolean;
        parent_depth : integer;
        show_channel_change_icons : boolean;
begin
        if (not Visible) then begin
                exit;
        end;

        parent_depth := (Parent as TPopupForm).depth;
        sub_popup_exists := is_group and (IfPopupFormExists(parent_depth + 1, node_id));
        show_channel_change_icons := allow_channel_change and MouseOnMe;

        if (is_group and sub_popup_exists) then begin
                need_draw_hover := sub_popup_exists;

                ForSelectedElement(procedure(element : TPOEPopupMenuElement)
                begin
                        need_draw_hover := MouseOnMe or ((element.Parent as TPopupForm).depth > parent_depth);
                end);
        end else begin
                need_draw_hover := MouseOnMe;
        end;

        // Resize the internal graphics if we need it
        if (GfxBmp.Width <> ClientWidth) then begin
                GfxBmp.Width := ClientWidth;
        end;
        if (GfxBmp.Height <> ClientHeight) then begin
                GfxBmp.Height := ClientHeight;
        end;

        // Calculate client rectangle
        ClientRect := Bounds(1, 1, GfxBmp.Width - 2, GfxBmp.Height - 2);

        GfxBmp.Canvas.Font.Assign(Font);

        with GfxBmp.Canvas do begin
                // Render the control underlay
                if (need_draw_hover) then begin
                        Brush.Color := GUISkin.hover_color;
                end else begin
                        Brush.Color := GUISkin.back_color;
                end;
                FillRect(ClientRect);

                if (is_group) then begin
                        offset_x := 36;
                        offset_y := 0;
                end else begin
                        offset_x := 30;
                        offset_y := 2;
                end;

                if (not is_group) then begin
                        // Draw big chat icon
                        ForChatChannel(target_channel, procedure(ChatChannel: TChatChannel)
                        var
                                char_draw_x, char_draw_y : integer;
                                previous_font : string;
                                previous_font_size : integer;
                        begin
                                with GfxBmp.Canvas, ChatChannel do begin
                                        previous_font := Font.Name;
                                        previous_font_size := Font.Size;

                                        Font.Name := 'Arial Black';
                                        Font.Size := 16;
                                        Font.Color := color;

                                        char_draw_x := 15 - TextWidth(symbol) div 2;
                                        char_draw_y := 15 - TextHeight(symbol) div 2;

                                        TextOut(char_draw_x, char_draw_y, symbol);

                                        Font.Name := previous_font;
                                        Font.Size := previous_font_size;
                                end;
                        end);
                end;

                // Render caption
                ClientRect.Offset(offset_x, offset_y);
                ClientRect.Width := ClientRect.Width - offset_x;
                ClientRect.Height := ClientRect.Height - offset_y;

                Brush.Style := bsClear;
                Font.Color := GUISkin.caption_color;

                if (is_group) then begin
                        draw_format := DT_LEFT or DT_WORDBREAK or DT_VCENTER or DT_SINGLELINE;
                end else begin
                        draw_format := DT_LEFT or DT_WORDBREAK;

                        ClientRect.Height := ClientRect.Height - 2 - integer(show_channel_change_icons) * 32;
                end;

                DrawTextEx(GfxBmp.Canvas.Handle, PChar(Caption), Length(Caption), ClientRect, draw_format, nil);
        end;

        if (is_group) then begin
                // Render group icon
                ForImage(Logic.IfThen(need_draw_hover, IMAGE_GROUP_ICON_SELECTED, IMAGE_GROUP_ICON), procedure(icon : TPngImage)
                begin
                        DrawPNGImage(icon, GfxBmp.Canvas, 10, GfxBmp.Height div 2 - icon.Height div 2);
                end);
        end else begin
                if (show_channel_change_icons) then begin
                        RefreshAllowedChatChannels();

                        // Render chat channel icon
                        ForImage(IMAGE_CHAT_CHANNEL_UNDERLAY_ICON, procedure(icon : TPngImage)
                        var
                                draw_x, draw_y : integer;
                        begin
                                draw_x := GfxBmp.Width - icon.Width - 3;
                                draw_y := GfxBmp.Height - icon.Height - 3;

                                ChatChannels.ForEachReverse(procedure(ChatChannel: TChatChannel)
                                var
                                        char_draw_x, char_draw_y : integer;
                                        previous_font : string;
                                        need_to_draw_channel_icon : boolean;
                                begin
                                        need_to_draw_channel_icon := true;

                                        if ((ChatChannel.id in AllowedChatChannels) = false) then begin
                                                need_to_draw_channel_icon := false;
                                        end;

                                        if (need_to_draw_channel_icon = false) then begin
                                                exit;
                                        end;

                                        // Draw channel icon
                                        DrawPNGImage(icon, GfxBmp.Canvas, draw_x, draw_y);

                                        with GfxBmp.Canvas, ChatChannel do begin
                                                previous_font := Font.Name;

                                                Font.Name := 'Arial Black';
                                                Font.Color := color;

                                                char_draw_x := draw_x + icon.Width div 2 - TextWidth(symbol) div 2;
                                                char_draw_y := draw_y + icon.Height div 2 - TextHeight(symbol) div 2;

                                                TextOut(char_draw_x, char_draw_y, symbol);

                                                Font.Name := previous_font;
                                        end;

                                        dec(draw_x, icon.Width + 1);
                                end);
                        end);
                end;
        end;

        // Render frame
        with GfxBmp.Canvas do begin
                Brush.Style := bsSolid;
                Brush.Color := GUISkin.outer_frame_color;

                FrameRect(Bounds(0, 0, GfxBmp.Width, GfxBmp.Height));
        end;

        // Render the graphics
        Canvas.Draw(0, 0, GfxBmp);
end;

// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.RefreshAllowedChatChannels();
begin
        if (AllowedChatChannels_cached) then begin
                exit;
        end;

        if (Assigned(Config) = false) then begin
                exit;
        end;

        AllowedChatChannels := [target_channel];

        if (Config.HasAttribute('allowed_channels')) then begin
                Config.GetAttribDef('allowed_channels', '').ForEachToken(' ', procedure(token: string)
                var
                        channel_id : TChatChannelID;
                begin
                        channel_id := TChatChannelID(StrToIntDef(token, CHAT_CHANNEL_NULL));

                        if (channel_id <> CHAT_CHANNEL_NULL) then begin
                                AllowedChatChannels := AllowedChatChannels + [channel_id];
                        end;
                end);
        end else begin
                ChatChannels.ForEach(procedure(ChatChannel: TChatChannel)
                begin
                        if (not ChatChannel.hidden) then begin
                                AllowedChatChannels := AllowedChatChannels + [ChatChannel.id];
                        end;
                end);
        end;

        Config.GetAttribDef('disallowed_channels', '').ForEachToken(' ', procedure(token: string)
        var
                channel_id : TChatChannelID;
        begin
                channel_id := TChatChannelID(StrToIntDef(token, CHAT_CHANNEL_NULL));

                if (channel_id <> CHAT_CHANNEL_NULL) then begin
                        AllowedChatChannels := AllowedChatChannels - [channel_id];
                end;
        end);

        AllowedChatChannels_cached := true;
end;

// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.EventOnClick(Sender: TObject);
begin
        if (not is_group) then begin
                if (GetWorkingMode() = WORKING_MODE_CLICK) then begin
                        ExecutePopupWindowLogic(true);

                        if (not IsPopupHotkeyInToggleMode()) then begin
                                SetNeedWaitToPopupHotkeyRelease();
                        end;
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.SendToChat();
begin
        if (is_group) then begin
                exit;
        end;

        // Don't send empty string
        if (Caption = '') then begin
                exit;
        end;

        // Null channel?
        if (target_channel = CHAT_CHANNEL_NULL) then begin
                exit;
        end;

        ForChatChannel(target_channel, procedure(ChatChannel: TChatChannel)
                // -------------------------------------------------------------
                function SetupHook(HookConfig : TXMLDoc): TSendKeysHook;
                begin
                        result := procedure(InputSequence: TList<TInput>)
                        type
                                TStepAction = (
                                          STEP_ACTION_NOT_SET                = 0
                                        , STEP_ACTION_ENTER_CHARACTER
                                        , STEP_ACTION_KEY_PRESS
                                        , STEP_ACTION_KEY_RELEASE
                                        , STEP_ACTION_KEY_PRESS_AND_RELEASE
                                );
                        var
                                i : integer;
                                step_value_char : Char;

                                step_value_key_as_string : string;
                                step_value_key : integer;

                                step_action_as_string : string;
                                step_action : TStepAction;
                        begin
                                if (not Assigned(HookConfig)) then begin
                                        exit;
                                end;

                                if (HookConfig.Childs.Count = 0) then begin
                                        exit;
                                end;

                                for i := 0 to HookConfig.Childs.Count - 1 do begin
                                        with HookConfig.Childs[i] do begin
                                                step_value_key := 0;
                                                step_value_char := ' ';

                                                step_action_as_string := LowerCase(GetAttribDef('action', ''));

                                                if (step_action_as_string = LowerCase('EnterCharacter')) then begin
                                                        step_action := STEP_ACTION_ENTER_CHARACTER;
                                                end else if (step_action_as_string = LowerCase('KeyPress')) then begin
                                                        step_action := STEP_ACTION_KEY_PRESS;
                                                end else if (step_action_as_string = LowerCase('KeyRelease')) then begin
                                                        step_action := STEP_ACTION_KEY_RELEASE;
                                                end else if (step_action_as_string = LowerCase('KeyPressAndRelease')) then begin
                                                        step_action := STEP_ACTION_KEY_PRESS_AND_RELEASE;
                                                end else begin
                                                        step_action := STEP_ACTION_NOT_SET;
                                                end;

                                                // Prepare char \ key
                                                case step_action of
                                                        STEP_ACTION_ENTER_CHARACTER : begin
                                                                try
                                                                        step_value_char := GetAttribDef('value', ' ')[1];
                                                                except
                                                                        step_value_char := ' ';
                                                                        step_action := STEP_ACTION_NOT_SET;
                                                                end;
                                                        end;
                                                        STEP_ACTION_KEY_PRESS, STEP_ACTION_KEY_RELEASE, STEP_ACTION_KEY_PRESS_AND_RELEASE : begin
                                                                try
                                                                        step_value_key_as_string := GetAttribDef('value', '0');

                                                                        step_value_key_as_string := StringReplace(step_value_key_as_string, 'EnterChatKey', IntToStr(GetEnterChatKey()), [rfIgnoreCase]);
                                                                        step_value_key_as_string := StringReplace(step_value_key_as_string, 'SendTextKey', IntToStr(GetSendTextKey()), [rfIgnoreCase]);

                                                                        step_value_key := StrToIntDef(step_value_key_as_string, 0);
                                                                except
                                                                        step_action := STEP_ACTION_NOT_SET;
                                                                end;

                                                                if (step_value_key = 0) then begin
                                                                        step_action := STEP_ACTION_NOT_SET;
                                                                end;
                                                        end;
                                                end;

                                                // Add to sequence
                                                case step_action of
                                                        STEP_ACTION_ENTER_CHARACTER : begin
                                                                InputSequence.Add(GetInputCommandCharacterPress(step_value_char));
                                                                InputSequence.Add(GetInputCommandCharacterRelease(step_value_char));
                                                        end;
                                                        STEP_ACTION_KEY_PRESS : begin
                                                                InputSequence.Add(GetInputCommandKeyPress(step_value_key));
                                                        end;
                                                        STEP_ACTION_KEY_RELEASE : begin
                                                                InputSequence.Add(GetInputCommandKeyRelease(step_value_key));
                                                        end;
                                                        STEP_ACTION_KEY_PRESS_AND_RELEASE : begin
                                                                InputSequence.Add(GetInputCommandKeyPress(step_value_key));
                                                                InputSequence.Add(GetInputCommandKeyRelease(step_value_key));
                                                        end;
                                                end;
                                        end;
                                end;
                        end;
                end;
                // -------------------------------------------------------------
        begin
                SendKeys(Caption, SetupHook(ChatChannel.config.FindChild('PreHook')), SetupHook(ChatChannel.config.FindChild('PostHook')));
        end);
end;

// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.CMMouseEnter(var msg: TMessage);
begin
        inherited;

        BringToFront();
        ElementLogic();
        MouseOnMe := true;

        InvalidateAllPopupComponents();

        SetSelectedElement(Self);
end;

// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.CMMouseLeave(var msg: TMessage);
begin
        inherited;

        InvalidateAllPopupComponents();
end;

// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.MouseMove(Shift: TShiftState; X, Y: Integer);
var
        show_channel_change_icons : boolean;
begin
        inherited;

        ElementLogic();
        MouseOnMe := true;

        SetSelectedElement(Self);

        // Channel selector
        show_channel_change_icons := allow_channel_change and MouseOnMe;
        if (not is_group) and (show_channel_change_icons) then begin
                RefreshAllowedChatChannels();

                ForImage(IMAGE_CHAT_CHANNEL_UNDERLAY_ICON, procedure(icon : TPngImage)
                const
                        OFFSET = 5;
                var
                        icon_x, icon_y : integer;
                begin
                        icon_x := GfxBmp.Width - icon.Width - 3;
                        icon_y := GfxBmp.Height - icon.Height - 3;

                        ChatChannels.ForEachReverse(procedure(ChatChannel: TChatChannel)
                        var
                                need_to_process_channel_icon : boolean;
                        begin
                                need_to_process_channel_icon := true;

                                if ((ChatChannel.id in AllowedChatChannels) = false) then begin
                                        need_to_process_channel_icon := false;
                                end;

                                if (need_to_process_channel_icon = false) then begin
                                        exit;
                                end;

                                // Is chat channel hovered by mouse?
                                if (PtInRect(Bounds(icon_x + OFFSET, icon_y + OFFSET, icon.Width - OFFSET * 2, icon.Height - OFFSET * 2), Point(x, y))) then begin
                                        target_channel := ChatChannel.id;
                                end;

                                dec(icon_x, icon.Width + 1);
                        end);
                end);
        end;

        Invalidate();
end;

// -----------------------------------------------------------------------------
procedure TPOEPopupMenuElement.ElementLogic();
var
        parent_depth : integer;
        need_to_disable_timer : boolean;
begin
        parent_depth := (Parent as TPopupForm).depth;

        if (is_group) then begin
                if (IsAtLeastOneThisDeepPopupFormExists(parent_depth + 1)) then begin
                        if (IfPopupFormExists(parent_depth + 1, node_id)) then begin
                                need_to_disable_timer := true;
                        end else begin
                                HideAllPopupFormsDelayed(parent_depth + 1);

                                need_to_disable_timer := false;
                        end;
                end else begin
                        PopupForm(Config, parent_depth + 1, node_id);

                        need_to_disable_timer := true;
                end;
        end else begin
                HideAllPopupFormsDelayed(parent_depth + 1);

                need_to_disable_timer := (IsAtLeastOneThisDeepPopupFormExists(GetDelayedHideMinimumDepth()) = false) or (parent_depth = GetDelayedHideMinimumDepth());
        end;

        if (need_to_disable_timer) then begin
                MainForm.DelayedHidePopupTimer.Enabled := false;
        end;
end;

// -----------------------------------------------------------------------------
procedure LoadChatChannels(chat_channels_config: TXMLDoc);
var
        i : integer;
        channel_already_exists : boolean;
        ChatChannel : TChatChannel;
begin
        ChatChannels.Clear();

        if (Assigned(chat_channels_config) = false) then begin
                exit;
        end;

        if (chat_channels_config.Childs.Count = 0) then begin
                exit;
        end;

        for i := 0 to chat_channels_config.Childs.Count - 1 do begin
                with ChatChannel, chat_channels_config.Childs[i] do begin
                        // Is enabled?
                        if (not GetAttribDef('enabled', true)) then begin
                                Continue;
                        end;

                        // ID
                        id := TChatChannelID(GetAttribDef('id', CHAT_CHANNEL_NULL));

                        // Channel with this ID already exists?
                        channel_already_exists := false;
                        ForChatChannel(id, procedure(ChatChannel: TChatChannel)
                        begin
                                channel_already_exists := true;
                        end);
                        if (channel_already_exists) then begin
                                Continue;
                        end;

                        // Symbol
                        try
                                symbol := GetAttribDef('symbol', 'E')[1];
                        except
                                symbol := 'E';
                        end;

                        // Color
                        color := StrToInt(GetAttribDef('color', '0x000000'));

                        // Is default?
                        if (GetAttribDef('default', false)) then begin
                                DefaultChatChannel := id;
                        end;

                        // Is hidden?
                        hidden := GetAttribDef('hidden', false);

                        // Config
                        config := chat_channels_config.Childs[i];
                end;

                ChatChannels.Append(ChatChannel);
        end;
end;

// -----------------------------------------------------------------------------
function GetDefaultChatChannel(): TChatChannelID;
begin
        result := DefaultChatChannel;
end;

// -----------------------------------------------------------------------------
end.
