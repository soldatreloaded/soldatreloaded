// The reference's stand-in for demo recording: nothing is recorded.
unit Demo;

interface

type
  TDemoRecorder = class
  public
    Active: Boolean;
    function StartRecord(Filename: string): Boolean;
    procedure StopRecord;
    procedure SaveNextFrame;
  end;

var
  DemoRecorder: TDemoRecorder;

implementation

function TDemoRecorder.StartRecord(Filename: string): Boolean; begin Result := False; end;
procedure TDemoRecorder.StopRecord; begin end;
procedure TDemoRecorder.SaveNextFrame; begin end;

initialization
  DemoRecorder := TDemoRecorder.Create;

end.
