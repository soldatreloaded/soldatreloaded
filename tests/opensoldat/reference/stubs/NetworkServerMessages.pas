// The reference's stand-in for the server's chat messages: nothing is sent.
unit NetworkServerMessages;

interface

procedure ServerSendStringMessage(Text: WideString; ToNum: Byte; From: Byte; MsgType: Byte);

implementation

procedure ServerSendStringMessage(Text: WideString; ToNum: Byte; From: Byte; MsgType: Byte); begin end;

end.
