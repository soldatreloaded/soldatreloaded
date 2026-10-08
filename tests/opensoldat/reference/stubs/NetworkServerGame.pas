// The reference's stand-in for the server's game messages: nothing is sent.
unit NetworkServerGame;

interface

procedure ServerMapChange(ID: Byte);
procedure ServerFlagInfo(Style, Who: Byte);
procedure ServerIdleAnimation(Num: Byte; Style: SmallInt);
procedure ServerSendVoteOff;

implementation

procedure ServerMapChange(ID: Byte); begin end;
procedure ServerFlagInfo(Style, Who: Byte); begin end;
procedure ServerIdleAnimation(Num: Byte; Style: SmallInt); begin end;
procedure ServerSendVoteOff; begin end;

end.
