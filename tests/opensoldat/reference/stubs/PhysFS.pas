// PhysFS for the reference: OpenSoldat reads its data through PhysFS, out of soldat.smod
// mounted at the root. Here the same calls read loose files under PhysFSRoot, a data
// folder laid out as that archive is (anims/, objects/, maps/): the port's own data, so
// both games play by the same files. Only what the simulation calls is here.
// PHYSFS_readBuffer and PHYSFS_ReadLn are as they are in shared/libs/PhysFS/PhysFS.pas.
unit PhysFS;

interface

uses
  SysUtils,
  Classes,
  TraceLog;

type
  PHYSFS_File = pointer;
  PHYSFS_Buffer = array of byte;

var
  PhysFSRoot: string; // with its trailing separator

function  PHYSFS_mount(newDir, mountPoint: PChar; appendToPath: LongBool): LongBool;
function  PHYSFS_openRead(filename: PChar): PHYSFS_File;
function  PHYSFS_exists(filename: PChar): LongBool;
function  PHYSFS_read(pfile: PHYSFS_File; buffer: pointer; obj_size: Longword; obj_count: Longword): Int64;
function  PHYSFS_close(pfile: PHYSFS_File): Int64;
function  PHYSFS_fileLength(pfile: PHYSFS_File): Int64;
function  PHYSFS_removeFromSearchPath(oldDir: PChar): LongBool;

function  PHYSFS_readBuffer(Name: PChar): PHYSFS_Buffer;
procedure PHYSFS_ReadLn(FileHandle: PHYSFS_File; var Line: AnsiString);

implementation

function Path(filename: PChar): string;
begin
  Result := PhysFSRoot + string(filename);
end;

// No archives here: a packed map is never asked for, the maps being loose.
function PHYSFS_mount(newDir, mountPoint: PChar; appendToPath: LongBool): LongBool;
begin
  Result := False;
end;

function PHYSFS_removeFromSearchPath(oldDir: PChar): LongBool;
begin
  Result := True;
end;

function PHYSFS_openRead(filename: PChar): PHYSFS_File;
begin
  Result := nil;
  if FileExists(Path(filename)) then
    Result := TFileStream.Create(Path(filename), fmOpenRead or fmShareDenyNone);
end;

function PHYSFS_exists(filename: PChar): LongBool;
begin
  Result := FileExists(Path(filename));
end;

function PHYSFS_read(pfile: PHYSFS_File; buffer: pointer; obj_size: Longword; obj_count: Longword): Int64;
begin
  Result := TFileStream(pfile).Read(buffer^, obj_size * obj_count) div obj_size;
end;

function PHYSFS_close(pfile: PHYSFS_File): Int64;
begin
  TFileStream(pfile).Free;
  Result := 1;
end;

function PHYSFS_fileLength(pfile: PHYSFS_File): Int64;
begin
  Result := TFileStream(pfile).Size;
end;

function PHYSFS_readBuffer(Name: PChar): PHYSFS_Buffer;
var
  FileHandle: PHYSFS_File;
  Data: PHYSFS_Buffer;
begin
  Data := Default(PHYSFS_Buffer);
  Result := nil;
  if not PHYSFS_exists(Name) then
    Exit;
  FileHandle := PHYSFS_openRead(Name);
  if FileHandle = nil then
    Exit;
  SetLength(Data, PHYSFS_fileLength(FileHandle));
  if PHYSFS_read(FileHandle, Data, 1, PHYSFS_fileLength(FileHandle)) = -1 then
    Exit;
  Result := Data;
  PHYSFS_close(FileHandle);
end;

procedure PHYSFS_ReadLn(FileHandle: PHYSFS_File; var Line: AnsiString);
var
  c: Char = ' ';
  b: ShortString = '';
begin
  Line := '';
  b[0] := #0;

  while (PHYSFS_read(FileHandle, @c, 1, 1) = 1) and (c <> #10) do
    if (c <> #13) then
    begin
      inc(b[0]);
      b[byte(b[0])]:= c;
      if b[0] = #255 then
      begin
        Line := Line + AnsiString(b);
        b[0]:= #0
      end
    end;
  Line := Line + AnsiString(b)
end;

end.
