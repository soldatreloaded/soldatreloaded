// The reference's stand-in for the server's thing messages: nothing is sent.
unit NetworkServerThing;

interface

procedure ServerThingMustSnapshot(ThingNum: Byte);
procedure ServerThingTaken(ThingNum, Who: Byte);

implementation

procedure ServerThingMustSnapshot(ThingNum: Byte); begin end;
procedure ServerThingTaken(ThingNum, Who: Byte); begin end;

end.
