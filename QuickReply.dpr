// -----------------------------------------------------------------------------
program QuickReply;
// -----------------------------------------------------------------------------


uses
  Vcl.Forms,
  Constants in 'Constants.pas',
  main in 'main.pas' {MainForm},
  PopupMenuElement in 'PopupMenuElement.pas',
  Utils in 'Utils.pas',
  uPopupForm in 'uPopupForm.pas' {PopupForm},
  XMLSimpleParse in 'XMLSimpleParse.pas',
  uAboutForm in 'uAboutForm.pas' {AboutForm};

// -----------------------------------------------------------------------------
{$R *.res}
// -----------------------------------------------------------------------------
begin
        Application.Initialize();
        Application.MainFormOnTaskbar := true;
        Application.ShowMainForm := false;
        Application.CreateForm(TMainForm, MainForm);
        Application.Run();
end.
