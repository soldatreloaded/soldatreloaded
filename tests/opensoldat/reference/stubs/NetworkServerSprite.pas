// The reference's stand-in for the server's sprite messages: nothing is sent.
unit NetworkServerSprite;

interface

procedure ServerSpriteSnapshotMajor(r: Byte);
procedure ServerSpriteSnapshotMajorSingle(Who: Byte; r: Byte);
procedure ServerSpriteDeltasMouse(i: Byte);
procedure ServerSpriteDeath(Who, Killer, BulletNum, Where: Integer);

implementation

procedure ServerSpriteSnapshotMajor(r: Byte); begin end;
procedure ServerSpriteSnapshotMajorSingle(Who: Byte; r: Byte); begin end;
procedure ServerSpriteDeltasMouse(i: Byte); begin end;
procedure ServerSpriteDeath(Who, Killer, BulletNum, Where: Integer); begin end;

end.
