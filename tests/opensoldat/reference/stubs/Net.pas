// Net for the reference: OpenSoldat's shared/network/Net.pas without the network. Its
// constants, TPlayer and globals as they are there (copied at the pinned commit), and
// none of the Steam networking classes, which the simulation doesn't touch.
unit Net;

interface

uses
  Classes,
  fgl,
  SysUtils,
  Vector,
  Constants,
  Weapons;



const
  // Binary ops
  B1  =     1;
  B2  =     2;
  B3  =     4;
  B4  =     8;
  B5  =    16;
  B6  =    32;
  B7  =    64;
  B8  =   128;
  B9  =   256;
  B10 =   512;
  B11 =  1024;
  B12 =  2048;
  B13 =  4096;
  B14 =  8192;
  B15 = 16384;
  B16 = 32768;

  // MESSAGE IDs
  MsgID_Custom                     = 0;
  MsgID_HeartBeat                  = MsgID_Custom +  2;
  MsgID_ServerSpriteSnapshot       = MsgID_Custom +  3;
  MsgID_ClientSpriteSnapshot       = MsgID_Custom +  4;
  MsgID_BulletSnapshot             = MsgID_Custom +  5;
  MsgID_ChatMessage                = MsgID_Custom +  6;
  MsgID_ServerSkeletonSnapshot     = MsgID_Custom +  7;
  MsgID_MapChange                  = MsgID_Custom +  8;
  MsgID_ServerThingSnapshot        = MsgID_Custom +  9;
  MsgID_ThingTaken                 = MsgID_Custom + 12;
  MsgID_SpriteDeath                = MsgID_Custom + 13;
  MsgID_PlayerInfo                 = MsgID_Custom + 15;
  MsgID_PlayersList                = MsgID_Custom + 16;
  MsgID_NewPlayer                  = MsgID_Custom + 17;
  MsgID_ServerDisconnect           = MsgID_Custom + 18;
  MsgID_PlayerDisconnect           = MsgID_Custom + 19;
  MsgID_Delta_Movement             = MsgID_Custom + 21;
  MsgID_Delta_Weapons              = MsgID_Custom + 25;
  MsgID_Delta_Helmet               = MsgID_Custom + 26;
  MsgID_Delta_MouseAim             = MsgID_Custom + 29;
  MsgID_Ping                       = MsgID_Custom + 30;
  MsgID_Pong                       = MsgID_Custom + 31;
  MsgID_FlagInfo                   = MsgID_Custom + 32;
  MsgID_ServerThingMustSnapshot    = MsgID_Custom + 33;
  MsgID_IdleAnimation              = MsgID_Custom + 37;
  MsgID_ServerSpriteSnapshot_Major = MsgID_Custom + 41;
  MsgID_ClientSpriteSnapshot_Mov   = MsgID_Custom + 42;
  MsgID_ClientSpriteSnapshot_Dead  = MsgID_Custom + 43;
  MsgID_UnAccepted                 = MsgID_Custom + 44;
  MsgID_VoteOn                     = MsgID_Custom + 45;
  MsgID_VoteMap                    = MsgID_Custom + 46;
  MsgID_VoteMapReply               = MsgID_Custom + 47;
  MsgID_VoteKick                   = MsgID_Custom + 48;
  MsgID_RequestThing               = MsgID_Custom + 51;
  MsgID_ServerVars                 = MsgID_Custom + 52;
  MsgID_ServerSyncMsg              = MsgID_Custom + 54;
  MsgID_ClientFreeCam              = MsgID_Custom + 55;
  MsgID_VoteOff                    = MsgID_Custom + 56;
  MsgID_FaeData                    = MsgID_Custom + 57;
  MsgID_RequestGame                = MsgID_Custom + 58;
  MsgID_ForcePosition              = MsgID_Custom + 60;
  MsgID_ForceVelocity              = MsgID_Custom + 61;
  MsgID_ForceWeapon                = MsgID_Custom + 62;
  MsgID_ChangeTeam                 = MsgID_Custom + 63;
  MsgID_SpecialMessage             = MsgID_Custom + 64;
  MsgID_WeaponActiveMessage        = MsgID_Custom + 65;
  MsgID_JoinServer                 = MsgID_Custom + 68;
  MsgID_PlaySound                  = MsgID_Custom + 70;
  MsgID_SyncCvars                  = MsgID_Custom + 71;
  MsgID_VoiceData                  = MsgID_Custom + 72;

  MAX_PLAYERS = 32;

  VERSION_PACKET_CHARS = 24;

  // ControlMethod
  HUMAN = 1;
  BOT   = 2;

  // Request Reply States
  OK                 =  1;
  WRONG_VERSION      =  2;
  WRONG_PASSWORD     =  3;
  BANNED_IP          =  4;
  SERVER_FULL        =  5;
  INVALID_HANDSHAKE  =  8;
  WRONG_CHECKSUM     =  9;
  ANTICHEAT_REQUIRED = 10;
  ANTICHEAT_REJECTED = 11;
  STEAM_ONLY         = 12;

  LAN      = 1;
  INTERNET = 0;

  // FLAG INFO
  RETURNRED   = 1;
  RETURNBLUE  = 2;
  CAPTURERED  = 3;
  CAPTUREBLUE = 4;

  // Kick/Ban Why's
  KICK_UNKNOWN         =  0;
  KICK_NORESPONSE      =  1;
  KICK_NOCHEATRESPONSE =  2; // TODO remove?
  KICK_CHANGETEAM      =  3; // TODO remove?
  KICK_PING            =  4;
  KICK_FLOODING        =  5;
  KICK_CONSOLE         =  6;
  KICK_CONNECTCHEAT    =  7; // TODO remove?
  KICK_CHEAT           =  8;
  KICK_LEFTGAME        =  9;
  KICK_VOTED           = 10;
  KICK_AC              = 11;
  KICK_SILENT          = 12;
  KICK_STEAMTICKET     = 13;
  _KICK_END            = 14;

  // Join types
  JOIN_NORMAL = 0;
  JOIN_SILENT = 1;

  // RECORD
  NETW = 0;
  REC  = 1;

  CLIENTPLAYERRECIEVED_TIME = 3 * 60;

  FLOODIP_MAX  = 18;
  MAX_FLOODIPS = 1000;
  MAX_BANIPS   = 1000;

  PLAYERNAME_CHARS = 24;
  PLAYERHWID_CHARS = 11;
  MAPNAME_CHARS    = 64;
  REASON_CHARS     = 26;

  ACTYPE_NONE = 0;
  ACTYPE_FAE  = 1;

  MSGTYPE_CMD   = 0;
  MSGTYPE_PUB   = 1;
  MSGTYPE_TEAM  = 2;
  MSGTYPE_RADIO = 3;

type
  HSteamNetConnection = LongWord; // only a field's type here

  TPlayer = class
  public
    // (!!!) When extending this class also extend its clone method, else ScriptCore breaks (maybe).

    // client/server shared stuff:
    // TODO stuff here that is relevant for the sprite (color, team, ...) should be moved to
    // a template object instead. When a sprite is created, then copy the template to it and apply
    // modifications depending on the game mode (eg. change the shirt color to match the team.)
    // That would allow switching game modes etc. without losing information about the player.
    Name: string;
    ShirtColor, PantsColor, SkinColor, HairColor, JetColor: LongWord;
    Kills, Deaths: Integer;
    Flags: Byte;
    PingTicks, PingTicksB, PingTime, Ping: Integer;
    RealPing: Word;
    ConnectionQuality: Byte;
    Team: Byte;
    ControlMethod: Byte;
    Chain, HeadCap, HairStyle: Byte;
    SecWep: Byte;
    Camera: Byte;
    Muted: Byte;
    SpriteNum: Byte; // 0 if no sprite exists yet
    DemoPlayer: Boolean;
    {$IFDEF STEAM}
    SteamID: CSteamID;
    SteamStats: Boolean;
    LastReceiveVoiceTime: Integer;
    SteamFriend: Boolean;
    {$ENDIF}

    // server only below this line:
    // -----
    {$IFDEF SERVER}
    IP: string;
    Port: Integer;

    // anti-cheat client handles and state
    {$IFDEF ENABLE_FAE}
    FaeResponsePending: Boolean;
    FaeKicked: Boolean;
    FaeTicks: Integer;
    FaeSecret: TFaeSecret;
    {$ENDIF}

    Peer: HSteamNetConnection;
    HWID: string;
    PlayTime: Integer;
    GameRequested: Boolean;

    // counters for warnings:
    ChatWarnings: Byte;
    TKWarnings: Byte;

    // anti mass flag counters:
    ScoresPerSecond: Integer;
    GrabsPerSecond: Integer;
    GrabbedInBase: Boolean;  // To prevent false accusations
    StandingPolyType: Byte;  // Testing
    KnifeWarnings: Byte;

    constructor Create();
    destructor Destroy(); override;
    {$ENDIF SERVER}
    procedure ApplyShirtColorFromTeam; // TODO remove, see comment before Name
    function Clone: TPlayer;
  end;

  TPlayers = TFPGObjectList<TPlayer>;

  TStatsString = array[0..2048] of Char;
  TIPString = array[0..128] of Char;

var
  MainTickCounter: Integer;
  // Stores all network-generated TPlayer objects
  Players: TPlayers;

  {$IFNDEF SERVER}
  ClientTickCount, LastHeartBeatCounter: LongInt;
  ClientPlayerReceivedCounter: Integer;
  ClientPlayerReceived, ClientPlayerSent: Boolean;
  ClientVarsRecieved: Boolean;
  RequestingGame: Boolean;
  NoHeartbeatTime: Integer = 0;
  ReceivedUnAccepted: Boolean;
  VoteMapName: String;
  VoteMapCount: Word;
  {$ELSE}
  // We're assigning a dummy player class to all sprites that are currently not being controlled
  // by a player. This avoids nasty surprises with older code that reads .Player despite .Active
  // being false. A player object is swapped in by CreateSprite as needed. For bots we simply leave
  // the bot object and free it when it is replaced.
  // Albeit this approach is very robust I'd prefer if we get rid of this and fix all .Active
  // checks (if any) later. Alternatively we could move a good bit if info from Player to Sprite.
  DummyPlayer: TPlayer;

  ServerTickCounter: Integer;
  NoClientUpdateTime: array[1..MAX_PLAYERS] of Integer;
  MessagesASecNum:    array[1..MAX_PLAYERS] of Integer;
  FloodWarnings:      array[1..MAX_PLAYERS] of Byte;
  PingWarnings:       array[1..MAX_PLAYERS] of Byte;
  BulletTime:         array[1..MAX_PLAYERS] of Integer;
  GrenadeTime:        array[1..MAX_PLAYERS] of Integer;
  KnifeCan:           array[1..MAX_PLAYERS] of Boolean;
  {$ENDIF}

  PlayersNum, BotsNum, SpectatorsNum: Integer;
  PlayersTeamNum: array[1..4] of Integer;

  PingTicksAdd: Integer = {$IFDEF SERVER} 0 {$ELSE} 2 {$ENDIF};

  {$IFDEF SCRIPT}
  ForceWeaponCalled: Boolean;
  {$ENDIF}


implementation

uses
  Server,
  Game;

constructor TPlayer.Create();
begin
end;

destructor TPlayer.Destroy();
begin
end;

function TPlayer.Clone: TPlayer;
begin
  // NOTE that only fields used by TScriptNewPlayer really matter here, but we clone the whole
  // thing for consistency. Obviously don't clone handles etc. unless they can be duplicated.

  Result := TPlayer.Create;

  Result.Name := Self.Name;
  Result.ShirtColor := Self.ShirtColor;
  Result.PantsColor := Self.PantsColor;
  Result.SkinColor := Self.SkinColor;
  Result.HairColor := Self.HairColor;
  Result.JetColor := Self.JetColor;
  Result.Kills := Self.Kills;
  Result.Deaths := Self.Deaths;
  Result.Flags := Self.Flags;
  Result.PingTicks := Self.PingTicks;
  Result.PingTicksB := Self.PingTicksB;
  Result.PingTime := Self.PingTime;
  Result.RealPing := Self.RealPing;
  Result.ConnectionQuality := Self.ConnectionQuality;
  Result.Ping := Self.Ping;
  Result.Team := Self.Team;
  Result.ControlMethod := Self.ControlMethod;
  Result.Chain := Self.Chain;
  Result.HeadCap := Self.HeadCap;
  Result.HairStyle := Self.HairStyle;
  Result.SecWep := Self.SecWep;
  Result.Camera := Self.Camera;
  Result.Muted := Self.Muted;
  Result.SpriteNum := Self.SpriteNum;
  Result.DemoPlayer := Self.DemoPlayer;
  {$IFDEF STEAM}
  Result.SteamID := Self.SteamID;
  Result.SteamStats := Self.SteamStats;
  {$ENDIF}

  {$IFDEF SERVER}
  Result.IP := Self.IP;
  Result.Port := Self.Port;
  {$IFDEF ENABLE_FAE}
  Result.FaeResponsePending := Self.FaeResponsePending;
  Result.FaeKicked := Self.FaeKicked;
  Result.FaeTicks := Self.FaeTicks;
  Result.FaeSecret := Self.FaeSecret;
  {$ENDIF}
  Result.hwid := Self.hwid;
  Result.PlayTime := Self.PlayTime;
  Result.GameRequested := Self.GameRequested;
  Result.ChatWarnings := Self.ChatWarnings;
  Result.TKWarnings := Self.TKWarnings;
  Result.ScoresPerSecond := Self.ScoresPerSecond;
  Result.GrabsPerSecond := Self.GrabsPerSecond;
  Result.GrabbedInBase := Self.GrabbedInBase;
  Result.StandingPolyType := Self.StandingPolyType;
  Result.KnifeWarnings := Self.KnifeWarnings;
  {$ENDIF}
end;

procedure TPlayer.ApplyShirtColorFromTeam;
begin
  {$IFDEF SERVER}
  if sv_teamcolors.Value and IsTeamGame() then
    case Self.Team of
      1: Self.ShirtColor := $FFD20F05;
      2: Self.ShirtColor := $FF151FD9;
      3: Self.ShirtColor := $FFD2D205;
      4: Self.ShirtColor := $FF05D205;
    end;
  {$ENDIF}
end;

end.
