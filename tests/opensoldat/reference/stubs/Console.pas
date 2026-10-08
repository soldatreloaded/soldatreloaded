// The reference's stand-in for the server's console: what is written to it goes nowhere.
unit Console;

interface

type
  TConsole = object
    ScrollTick, ScrollTickMax, NewMessageWait, CountMax, AlphaCount: Integer;
    TerminalColors: Boolean;
    procedure Console(What: WideString; Col: Cardinal); overload;
    procedure Console(What: AnsiString; Col: Cardinal); overload;
    procedure Console(What: Variant; Col: Cardinal); overload;
    procedure Console(What: Variant; Col: Cardinal; Sender: Byte); overload;
    procedure ScrollConsole;
  end;

implementation

procedure TConsole.Console(What: WideString; Col: Cardinal); begin end;
procedure TConsole.Console(What: AnsiString; Col: Cardinal); begin end;
procedure TConsole.Console(What: Variant; Col: Cardinal); begin end;
procedure TConsole.Console(What: Variant; Col: Cardinal; Sender: Byte); begin end;
procedure TConsole.ScrollConsole; begin end;

end.
