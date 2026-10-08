// The reference's stand-in for the server's connection messages: nothing is sent.
unit NetworkServerConnection;

interface

procedure ServerSendNewPlayerInfo(Num: Byte; JoinType: Byte);

implementation

procedure ServerSendNewPlayerInfo(Num: Byte; JoinType: Byte); begin end;

end.
