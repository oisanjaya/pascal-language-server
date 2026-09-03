// Pascal Language Server
// Copyright 2020 Ryan Joseph

// This file is part of Pascal Language Server.

// Pascal Language Server is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation, either version 3 of
// the License, or (at your option) any later version.

// Pascal Language Server is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with Pascal Language Server.  If not, see
// <https://www.gnu.org/licenses/>.

unit PasLS.GotoDefinition;

{$mode objfpc}{$H+}

interface

uses
  { RTL }
  Classes, sysutils,
  { Code Tools }
  CodeToolManager, CodeCache, BasicCodeTools, CodeTree,
  { Protocol }
  LSP.Base , LSP.Basic;

type
  
  { TGotoDefinition }
  
  TGotoDefinition = class(specialize TLSPRequest<TTextDocumentPositionParams, TLocation>)
    function Process(var Params: TTextDocumentPositionParams): TLocation; override;
  end;

implementation

uses
  PasLS.Diagnostics, PasLS.CodeUtils;
  
function TGotoDefinition.Process(var Params: TTextDocumentPositionParams): TLocation;
var
  Code: TCodeBuffer;
  NewCode: TCodeBuffer;
  X, Y, AbsPos: Integer;
  NewX, NewY, NewTopLine: integer;

  IsString, IsComment, isKeyword: Boolean;

  procedure GetContextAtPosition(CodeBuffer: TCodeBuffer; CaretX, CaretY: Integer; 
    out IsString, IsComment, isKeyword: Boolean);
  const
    // A comprehensive list of Free Pascal / Delphi reserved keywords
    PascalKeywords: array[0..67] of string = (
      'absolute', 'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
      'constructor', 'destructor', 'dispose', 'div', 'do', 'downto', 'else',
      'end', 'except', 'exports', 'file', 'finalization', 'finally', 'for',
      'function', 'goto', 'if', 'implementation', 'in', 'inherited',
      'initialization', 'inline', 'interface', 'is', 'label', 'library', 'mod',
      'new', 'nil', 'not', 'object', 'of', 'operator', 'or', 'out', 'packed',
      'procedure', 'program', 'property', 'raise', 'record', 'repeat',
      'resourcestring', 'set', 'shl', 'shr', 'string', 'then', 'threadvar',
      'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor'
    );
  var
    RealPos, i: Integer;
    StartWord, EndWord: Integer;
    InStr, InLineComment, InBlock1, InBlock2: Boolean;
    Src, CurrentWord, TestWord: String;
  begin
    IsString := False;
    IsComment := False;
    isKeyword := False;

    CodeBuffer.LineColToPosition(CaretY, CaretX, RealPos);
    
    if RealPos < 1 then 
      Exit;
  
    Src := CodeBuffer.Source;
    InStr := False;
    InLineComment := False; //  // ...
    InBlock1 := False;      //  { ... }
    InBlock2 := False;      //  (* ... *)
    
    i := 1;
    while i <= RealPos do
    begin
      // Line comments terminate at line breaks
      if Src[i] in [#13, #10] then 
        InLineComment := False;
  
      if not InBlock1 and not InBlock2 and not InLineComment then
      begin
        if Src[i] = '''' then
        begin
          InStr := not InStr
        end
        else 
        begin 
          if not InStr then
          begin
            if Src[i] = '{' then 
              InBlock1 := True
            else if (i < Length(Src)) and (Src[i] = '(') and (Src[i+1] = '*') then
            begin
              InBlock2 := True;
              Inc(i); // Skip the '*'
            end
            else if (i < Length(Src)) and (Src[i] = '/') and (Src[i+1] = '/') then
            begin
              InLineComment := True;
              Inc(i); // Skip the second '/'
            end;
          end;
        end;
      end
      else
      begin
        // Trick: If we've reached the caret position exactly, break out early.
        // This ensures that clicking exactly on a closing '}' still registers 
        // as being "inside" the comment block.
        if i = RealPos then Break; 
  
        // Check for block comment terminators
        if InBlock1 and (Src[i] = '}') then
          InBlock1 := False
        else if InBlock2 and (i < Length(Src)) and (Src[i] = '*') and (Src[i+1] = ')') then
        begin
          InBlock2 := False;
          Inc(i); // Skip the ')'
        end;
      end;
  
      Inc(i);
    end;
  
    // Final evaluation
    IsComment := InBlock1 or InBlock2 or InLineComment;
    IsString := InStr;

    if not (IsString or IsComment) then
      begin
        if Src[RealPos] in ['a'..'z', 'A'..'Z', '0'..'9', '_'] then
        begin
          StartWord := RealPos;
          while (StartWord > 1) and (Src[StartWord - 1] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
            Dec(StartWord);
    
          EndWord := RealPos;
          while (EndWord < Length(Src)) and (Src[EndWord + 1] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
            Inc(EndWord);
    
          CurrentWord := Copy(Src, StartWord, EndWord - StartWord + 1);
        end;
        
        for TestWord in PascalKeywords do
          begin
            if CompareTextCT(TestWord, CurrentWord) = 0 then
              begin
                isKeyword := True;
                break;
              end;
          end;
      end;
  end;

begin with Params do
  begin
    Code := CodeToolBoss.FindFile(textDocument.localPath);
    X := position.character;
    Y := position.line;

    GetContextAtPosition(Code, X + 1, Y + 1, IsString, IsComment, isKeyword);

    { 
      NOTE: Use FindMainDeclaration to skip forward declarations and find
      the main/complete declaration. This is the correct behavior for
      "Go to Definition" as opposed to "Go to Declaration".
      
      For example, with:
        type
          IDocList = interface;  // forward declaration
          ...
          IDocList = interface(IDocAny)  // main declaration
            ...
          end;
      
      FindMainDeclaration returns the main declaration location.
    }
    if not IsString and not IsComment then
      if CodeToolBoss.FindMainDeclaration(Code, X + 1, Y + 1, NewCode, NewX, NewY, NewTopLine) then
        begin
          Result := TLocation.Create;
          Result.uri := PathToURI(NewCode.Filename);
          Result.range := GetIdentifierRangeAtPos(NewCode, NewX, NewY - 1);
        end
      else
        begin
          Result := nil;
            PublishCodeToolsError(Transport,'');
        end;
  end;
end;

end.

