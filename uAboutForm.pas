// -----------------------------------------------------------------------------
unit uAboutForm;
// -----------------------------------------------------------------------------
interface
// -----------------------------------------------------------------------------
uses Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Imaging.pngimage;
// -----------------------------------------------------------------------------
type
        TAboutForm = class(TForm)
                HowToUseLabel: TLabel;
                FullscreenLabel: TLabel;
                FullscreenImage: TImage;
                HotkeyLabel: TLabel;
                HotkeyImage1: TImage;
                HotkeyImage2: TImage;
                ButtonAnumationTimer: TTimer;
                HowToSendTextLabel: TLabel;
                HowToSendTextImage: TImage;
                DividerPanel: TPanel;
                CloseButton: TButton;
                PathOfExileIconImage: TImage;
                AuthorLabel: TLabel;
                AuthorOnPoELabel: TLabel;
                RedditIconImage: TImage;
                AuthorOnRedditLabel: TLabel;
                procedure ButtonAnumationTimerTimer(Sender: TObject);
                procedure FormCreate(Sender: TObject);
                procedure CloseButtonClick(Sender: TObject);
                procedure PathOfExileLinkLabelClick(Sender: TObject);
                procedure AuthorOnPoELabelMouseEnter(Sender: TObject);
                procedure AuthorOnPoELabelMouseLeave(Sender: TObject);
                procedure AuthorOnRedditLabelClick(Sender: TObject);
        end;
// -----------------------------------------------------------------------------
var
        AboutForm: TAboutForm = nil;
// -----------------------------------------------------------------------------
implementation
// -----------------------------------------------------------------------------
{$R *.dfm}
// -----------------------------------------------------------------------------
uses main, Constants, ShellApi, System.UITypes;
// -----------------------------------------------------------------------------
procedure TAboutForm.AuthorOnPoELabelMouseEnter(Sender: TObject);
begin
        with Sender as TLabel do begin
                Font.Style := Font.Style + [fsUnderline];
        end;
end;

// -----------------------------------------------------------------------------
procedure TAboutForm.AuthorOnPoELabelMouseLeave(Sender: TObject);
begin
        with Sender as TLabel do begin
                Font.Style := Font.Style - [fsUnderline];
        end;
end;

// -----------------------------------------------------------------------------
procedure TAboutForm.ButtonAnumationTimerTimer(Sender: TObject);
begin
        HotkeyImage1.Visible := not HotkeyImage1.Visible;
        HotkeyImage2.Visible := not HotkeyImage2.Visible;
end;

// -----------------------------------------------------------------------------
procedure TAboutForm.CloseButtonClick(Sender: TObject);
begin
        Close();
end;

// -----------------------------------------------------------------------------
procedure TAboutForm.FormCreate(Sender: TObject);
begin
        Caption := TOOL_NAME + ' v' + TOOL_VERSION + ' - About';

        case GetWorkingMode() of
                WORKING_MODE_HOVER : begin
                        HowToSendTextLabel.Caption := '3. Hover element and release F2. No need to click!';
                end;
                WORKING_MODE_CLICK : begin
                        HowToSendTextLabel.Caption := '3. Send message in one click!';
                end;
        end;
end;

// -----------------------------------------------------------------------------
procedure TAboutForm.PathOfExileLinkLabelClick(Sender: TObject);
begin
        ShellExecute(self.Handle, 'open', PChar('https://www.pathofexile.com/account/view-profile/' + AuthorOnPoELabel.Caption), nil, nil, SW_NORMAL);
end;

// -----------------------------------------------------------------------------
procedure TAboutForm.AuthorOnRedditLabelClick(Sender: TObject);
begin
        ShellExecute(self.Handle, 'open', PChar('https://www.reddit.com/user/' + AuthorOnRedditLabel.Caption), nil, nil, SW_NORMAL);
end;

// -----------------------------------------------------------------------------
end.
