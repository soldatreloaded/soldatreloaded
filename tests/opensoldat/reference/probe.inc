// The probe, the setup and the commands: what passes between the comparison and the
// library, mirrored by Probe, Setup and game.Command in main.odin. Every field is 4
// bytes, so the two lay out the same. Ids are given in the port's numbers.

const
  PROBE_SOLDIERS = 2;
  PROBE_BULLETS  = MAX_BULLETS; // 254: the first that many of the port's

type
  TSetup = packed record
    at: array[0..1] of TVector2;       // where each soldier stands
    weapons: array[0..1] of LongInt;   // each one's primary, the port's number
  end;
  PSetup = ^TSetup;

  // game.Command: the buttons a bit each, in the port's order, and the aim in the world
  TCommand = packed record
    sequence: LongWord;
    buttons: Word;
    pad: Word;
    aim: TVector2;
  end;
  TCommands = array[0..MAX_PLAYERS - 1] of TCommand;
  PCommands = ^TCommands;

  TProbeSoldier = packed record
    active, dead: LongInt;
    health: Single;
    pos, old_pos, vel, forces: TVector2;
    direction, stance, on_ground, jets: LongInt;
    legs_anim, legs_frame, legs_count: LongInt;
    body_anim, body_frame, body_count: LongInt;
    weapon, ammo, fire_count, reload_count, startup_count: LongInt;
    secondary, secondary_ammo, grenades: LongInt;
    cease_fire: LongInt;
  end;

  TProbeBullet = packed record
    active, style, weapon, owner: LongInt;
    pos, vel: TVector2;
    damage: Single;
    timeout: LongInt;
  end;

  TProbe = packed record
    tick: LongInt;
    soldiers: array[0..PROBE_SOLDIERS - 1] of TProbeSoldier;
    bullets: array[0..PROBE_BULLETS - 1] of TProbeBullet;
  end;
  PProbe = ^TProbe;

const
  // the port's buttons, in its order (game.Button)
  BUTTON_LEFT = 0; BUTTON_RIGHT = 1; BUTTON_JUMP = 2; BUTTON_CROUCH = 3;
  BUTTON_PRONE = 4; BUTTON_JET = 5; BUTTON_FIRE = 6; BUTTON_THROW = 7;
  BUTTON_RELOAD = 8; BUTTON_CHANGE = 9; BUTTON_SUICIDE = 10; BUTTON_DROP = 11;
  BUTTON_FLAG_THROW = 12;

// ---------------------------------------------------------------------------------
// The port's numbers. It numbers what it kept of OpenSoldat's weapons, bullet styles and
// animations its own way; -1 is what it has no number for.

function port_weapon(num: Integer): LongInt;
begin
  case num of
    COLT_NUM: Result := 11; // the USSOCOM
    EAGLE_NUM..MINIGUN_NUM: Result := num; // the Desert Eagles to the Minigun, in the same order
    KNIFE_NUM: Result := 12;
    CHAINSAW_NUM: Result := 13;
    LAW_NUM: Result := 14;
    NOWEAPON_NUM: Result := 0; // hands: the port's Punch
    FRAGGRENADE_NUM: Result := 15;
    THROWNKNIFE_NUM: Result := 16;
  else
    Result := -1;
  end;
end;

// And back: the OpenSoldat number of a port weapon.
function os_weapon(port: LongInt): Integer;
begin
  for Result := 0 to 255 do
    if port_weapon(Result) = port then
      Exit;
  Result := NOWEAPON_NUM;
end;

function port_style(style: Integer): LongInt;
begin
  case style of
    BULLET_STYLE_PLAIN: Result := 0;
    BULLET_STYLE_FRAGNADE: Result := 1;
    BULLET_STYLE_SHOTGUN: Result := 2;
    BULLET_STYLE_M79: Result := 3;
    BULLET_STYLE_PUNCH: Result := 4;
    BULLET_STYLE_KNIFE: Result := 5;
    BULLET_STYLE_LAW: Result := 6;
    BULLET_STYLE_THROWNKNIFE: Result := 7;
  else
    Result := -1;
  end;
end;

// The port has every animation but the bow's reload (20), in the same order.
function port_anim(id: Integer): LongInt;
begin
  if id = 20 then
    Result := -1
  else if id > 20 then
    Result := id - 1
  else
    Result := id;
end;

function port_stance(position: Integer): LongInt;
begin
  case position of
    POS_STAND: Result := 0;
    POS_CROUCH: Result := 1;
    POS_PRONE: Result := 2;
  else
    Result := -1;
  end;
end;

// ---------------------------------------------------------------------------------
// The scene and the controls

// Sprite `n` standing at `at`, still, its skeleton gathered there, holding nothing: as
// Respawn leaves a sprite, but where the scenario says rather than at a spawn point it
// rolled for, and with no parachute.
procedure place(n: Integer; at: TVector2);
var
  i: Integer;
begin
  SpriteParts.Pos[n] := at;
  SpriteParts.OldPos[n] := at;
  SpriteParts.Velocity[n] := Default(TVector2);
  SpriteParts.Forces[n] := Default(TVector2);
  for i := 1 to NUM_PARTICLES do
    if Sprite[n].Skeleton.Active[i] then
    begin
      Sprite[n].Skeleton.Pos[i] := at;
      Sprite[n].Skeleton.OldPos[i] := at;
    end;
  for i := 1 to MAX_THINGS do
    if Thing[i].Active then
      Thing[i].Kill;
  Sprite[n].HoldedThing := 0;
  Sprite[n].ResetSpriteOldPos;
end;

// Sprite `n`'s controls as `command` says: its buttons held, its aim where it points,
// rounded as OpenSoldat keeps it.
procedure press(n: Integer; const command: TCommand);
  function held(button: Integer): Boolean;
  begin
    Result := (command.buttons and (1 shl button)) <> 0;
  end;
begin
  with Sprite[n].Control do
  begin
    Left := held(BUTTON_LEFT);
    Right := held(BUTTON_RIGHT);
    Up := held(BUTTON_JUMP);
    Down := held(BUTTON_CROUCH);
    Fire := held(BUTTON_FIRE);
    Jetpack := held(BUTTON_JET);
    ThrowNade := held(BUTTON_THROW);
    ChangeWeapon := held(BUTTON_CHANGE);
    ThrowWeapon := held(BUTTON_DROP);
    Reload := held(BUTTON_RELOAD);
    Prone := held(BUTTON_PRONE);
    FlagThrow := held(BUTTON_FLAG_THROW);
    MouseAimX := Round(command.aim.X);
    MouseAimY := Round(command.aim.Y);
    MouseDist := 150;
  end;
end;

// ---------------------------------------------------------------------------------
// The probe

procedure probe_soldier(n: Integer; var p: TProbeSoldier);
begin
  p := Default(TProbeSoldier);
  if not Sprite[n].Active then
    Exit;
  with Sprite[n] do
  begin
    p.active := 1;
    p.dead := Ord(DeadMeat);
    p.health := Health;
    p.pos := SpriteParts.Pos[n];
    p.old_pos := SpriteParts.OldPos[n];
    p.vel := SpriteParts.Velocity[n];
    p.forces := SpriteParts.Forces[n];
    p.direction := Direction;
    p.stance := port_stance(Position);
    p.on_ground := Ord(OnGround);
    p.jets := JetsCount;
    p.legs_anim := port_anim(LegsAnimation.ID);
    p.legs_frame := LegsAnimation.CurrFrame;
    p.legs_count := LegsAnimation.Count;
    p.body_anim := port_anim(BodyAnimation.ID);
    p.body_frame := BodyAnimation.CurrFrame;
    p.body_count := BodyAnimation.Count;
    p.weapon := port_weapon(Weapon.Num);
    p.ammo := Weapon.AmmoCount;
    p.fire_count := Weapon.FireIntervalCount;
    p.reload_count := Weapon.ReloadTimeCount;
    p.startup_count := Weapon.StartUpTimeCount;
    p.secondary := port_weapon(SecondaryWeapon.Num);
    p.secondary_ammo := SecondaryWeapon.AmmoCount;
    p.grenades := TertiaryWeapon.AmmoCount;
    p.cease_fire := CeaseFireCounter;
  end;
end;

procedure os_probe(p: PProbe); cdecl;
var
  i: Integer;
begin
  p^ := Default(TProbe);
  p^.tick := MainTickCounter;
  for i := 0 to PROBE_SOLDIERS - 1 do
    probe_soldier(i + 1, p^.soldiers[i]);
  for i := 0 to PROBE_BULLETS - 1 do
    with Bullet[i + 1] do
      if Active then
      begin
        p^.bullets[i].active := 1;
        p^.bullets[i].style := port_style(Style);
        p^.bullets[i].weapon := port_weapon(OwnerWeapon);
        p^.bullets[i].owner := Owner; // a sprite's number: the port's index + 1
        p^.bullets[i].pos := BulletParts.Pos[Num];
        p^.bullets[i].vel := BulletParts.Velocity[Num];
        p^.bullets[i].damage := HitMultiply;
        p^.bullets[i].timeout := TimeOut;
      end;
end;

function os_probe_size: LongInt; cdecl;
begin
  Result := SizeOf(TProbe);
end;
