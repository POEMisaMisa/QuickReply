// -----------------------------------------------------------------------------
unit uPopupForm;
// -----------------------------------------------------------------------------
interface
// -----------------------------------------------------------------------------
uses Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls;
// -----------------------------------------------------------------------------
type
        TPopupForm = class(TForm)
        public
                depth, parent_node_id : integer;

        protected
                procedure CreateParams(var Params: TCreateParams); override;
        end;
// -----------------------------------------------------------------------------
implementation
// -----------------------------------------------------------------------------
{$R *.dfm}
// -----------------------------------------------------------------------------
uses PopupMenuElement;
// -----------------------------------------------------------------------------
{ TPopupForm }
// -----------------------------------------------------------------------------
procedure TPopupForm.CreateParams(var Params: TCreateParams);
begin
        inherited;

        Params.ExStyle := Params.ExStyle and (not WS_EX_APPWINDOW);
        Params.WndParent := Application.Handle;
end;

// -----------------------------------------------------------------------------
end.
