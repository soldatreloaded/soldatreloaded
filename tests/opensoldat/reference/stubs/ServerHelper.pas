// ServerHelper for the reference: the few of OpenSoldat's server/ServerHelper.pas
// routines the simulation calls, those with an effect copied as they are there (at the
// pinned commit), the rest doing nothing.
unit ServerHelper;

interface

function  FindLowestTeam(const Arr: array of Integer): Integer;
function  RGB(r, g, b: Byte): Cardinal;
function  WeaponNameByNum(Num: Integer): string;
procedure WriteConsole(ID: Byte; Text: string; Colour: UInt32);
procedure UpdateWaveRespawnTime;
procedure DoBalanceBots(LeftGame: Byte; NewTeam: Byte);

implementation

uses
  TraceLog,
  Util,
  Constants,
  Server,
  Net,
  Weapons;

function FindLowestTeam(const Arr: array of Integer): Integer;
var i, tmp: Integer;
begin
  tmp := 1;
  for i := 1 to iif(sv_gamemode.Value = GAMESTYLE_TEAMMATCH, 4, 2) do
  begin
    if Arr[tmp] > arr[i] then
      tmp := i;
  end;
  Result := tmp;
end;

function RGB(r, g, b: Byte): Cardinal;
begin
  Result := (r or (g shl 8) or (b shl 16));
end;

function WeaponNameByNum(Num: Integer): string;
var
  WeaponIndex: Integer;
begin
  Trace('WeaponNameByNum');
  Result := 'USSOCOM';

  if Num = 100 then
  begin
    Result := 'Selfkill';
    Exit;
  end;

  for WeaponIndex := Low(Guns) to High(Guns) do
  begin
    if Num = Guns[WeaponIndex].Num then
    begin
      Result := Guns[WeaponIndex].Name;
      Break;
    end;
  end;
end;

procedure UpdateWaveRespawnTime;
begin
  WaveRespawnTime := Round(PlayersNum * WAVERESPAWN_TIME_MULITPLIER) * 60;
  if WaveRespawnTime > sv_respawntime_minwave.Value then
    WaveRespawnTime := sv_respawntime_maxwave.Value;
  WaveRespawnTime := WaveRespawnTime - sv_respawntime_minwave.Value;
  if WaveRespawnTime < 1 then
    WaveRespawnTime := 1;
end;

procedure WriteConsole(ID: Byte; Text: string; Colour: UInt32); begin end;
procedure DoBalanceBots(LeftGame: Byte; NewTeam: Byte); begin end;

end.
