// OpenSoldat's simulation as the comparison sees it: a library with a scene to make, a
// tick to run and a probe of the world, as tests/compare/reference.c is for the C game.
// It is OpenSoldat's own server code (shared/ and shared/mechanics/ at the pinned
// commit, built by build.sh), with the network, the console and the file system stood in
// for by the units in stubs/; this file is what the server's Server.pas and
// ServerLoop.pas would do around it.
//
// OpenSoldat keeps its world in globals, so there is one scene at a time: the
// comparison loads the library afresh for each.
library reference;

uses
  SysUtils,
  Math,
  Vector,
  Constants,
  Anims,
  Parts,
  PolyMap,
  Util,
  Weapons,
  Cvar,
  Net,
  Server,
  ServerHelper,
  Game,
  Sprites,
  Bullets,
  Things,
  PhysFS;

{$INCLUDE probe.inc}

// ---------------------------------------------------------------------------------
// The scene

// What OpenSoldat's server does before it plays (ActivateServer, StartServer), less the
// network and the files it writes: its settings at their defaults, the data loaded, the
// map, the weapons; then two soldiers placed as `setup` says, driven as dummy bots
// (server-run, with no AI), so every move and shot is the server's own. Nonzero if made.
function os_scene(data, map_name: PChar; seed: LongWord; setup: PSetup): LongInt; cdecl;
var
  i: Integer;
  info: TMapInfo;
  player: TPlayer;
  n: Integer;
begin
  Result := 0;
  Set8087CW($133F);
  DefaultFormatSettings.DecimalSeparator := '.';
  PhysFSRoot := IncludeTrailingPathDelimiter(string(data));
  RandSeed := seed;
  MainTickCounter := 0;

  DummyPlayer := TPlayer.Create;
  for i := 1 to MAX_SPRITES do
    Sprite[i].Player := DummyPlayer;

  CvarInit;
  sv_gamemode.SetValue(GAMESTYLE_CTF);
  bots_chat.SetValue(False); // a bot's chat rolls the dice
  log_enable.SetValue(False);
  CvarsInitialized := True;

  for i := 1 to 14 do
    WeaponActive[i] := 1;
  LoadAnimObjects('');
  if Stand.NumFrames = 0 then // a missing file is skipped without a word
    Exit;

  info := Default(TMapInfo);
  info.Name := map_name;
  info.MapName := map_name;
  if not Map.LoadMap(info) then
    Exit;

  CreateWeapons(False);
  // No spread: OpenSoldat rolls its own dice for it and the port its own, so the shots
  // could never agree. With none, the rolls are multiplied by nothing (Sprites.pas,
  // TSprite.Fire), and the shots fly where they are aimed in both.
  for i := Low(Guns) to High(Guns) do
  begin
    Guns[i].MovementAcc := 0;
    Guns[i].BulletSpread := 0;
  end;
  for i := 1 to MAX_SPRITES do
    for n := 1 to MAIN_WEAPONS do
      WeaponSel[i][n] := WeaponActive[n];
  MapChangeCounter := -60;
  UpdateWaveRespawnTime;
  WaveRespawnCounter := WaveRespawnTime;

  for i := 0 to 1 do
  begin
    player := TPlayer.Create;
    player.Team := TEAM_ALPHA + i;
    player.ControlMethod := BOT;
    n := CreateSprite(setup^.at[i], Default(TVector2), 1, 255, player, True);
    Sprite[n].Dummy := True;
    Sprite[n].Respawn;
    place(n, setup^.at[i]);
    Sprite[n].ApplyWeaponByNum(os_weapon(setup^.weapons[i]), 1);
    Sprite[n].ApplyWeaponByNum(COLT_NUM, 2);
  end;
  Result := 1;
end;

// ---------------------------------------------------------------------------------
// A tick

// One of the server's frames (ServerLoop's AppOnIdle and UpdateFrame), each soldier
// pressing what `commands` says first.
procedure os_tick(commands: PCommands); cdecl;
var
  i, j: Integer;
begin
  Inc(MainTickCounter);
  for j := 1 to 2 do
    press(j, commands^[j - 1]);

  if MapChangeCounter < 0 then
  begin
    for j := 1 to MAX_SPRITES do
      if Sprite[j].Active and not Sprite[j].DeadMeat then
        if Sprite[j].IsNotSpectator() then
        begin
          for i := MAX_OLDPOS downto 1 do
            OldSpritePos[j, i] := OldSpritePos[j, i - 1];
          OldSpritePos[j, 0] := SpriteParts.Pos[j];
        end;

    for j := 1 to MAX_SPRITES do
      if Sprite[j].Active then
        if Sprite[j].IsNotSpectator() then
          SpriteParts.DoEulerTimeStepFor(j);

    for j := Low(Sprite) to High(Sprite) do
      if Sprite[j].Active then
        Sprite[j].Update;

    for j := 1 to MAX_BULLETS do
      if Bullet[j].Active then
        Bullet[j].Update;

    BulletParts.DoEulerTimeStep;

    for j := 1 to MAX_THINGS do
      if Thing[j].Active then
        Thing[j].Update;
  end;
end;

exports
  os_scene,
  os_tick,
  os_probe,
  os_probe_size;

end.
