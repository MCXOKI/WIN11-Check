unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, sButton, sMemo, Win11CompatibilityCheck;

type
  TForm1 = class(TForm)
    sMemo1: TsMemo;
    sButton1: TsButton;
    procedure sButton1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.sButton1Click(Sender: TObject);
var
  Result: TCompatibilityCheck;
  Msg: string;
begin
  Result := CheckWin11Compatibility;
  Msg := '';
  for var S in Result.Messages do
    Msg := Msg + S + sLineBreak;

  sMemo1.Text := Msg;

end;

end.
