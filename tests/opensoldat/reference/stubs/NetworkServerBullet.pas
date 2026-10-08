// The reference's stand-in for the server's bullet messages: nothing is sent.
unit NetworkServerBullet;

interface

procedure ServerBulletSnapshot(i: Byte; ToNum: Byte; Forced: Boolean);

implementation

procedure ServerBulletSnapshot(i: Byte; ToNum: Byte; Forced: Boolean); begin end;

end.
