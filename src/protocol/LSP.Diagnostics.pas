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

unit LSP.Diagnostics;

{$mode objfpc}{$H+}

interface

uses
  { RTL }
  Classes,
  { Protocol }
  LSP.BaseTypes, LSP.Base, LSP.Basic, LSP.Messages;

type

  { TPublishDiagnosticsParams }

  TPublishDiagnosticsParams = class(TLSPStreamable)
  private
    fUri: TDocumentUri;
    fDiagnostics: TDiagnosticItems;
    procedure SetDiagnostics(AValue: TDiagnosticItems);
  published
    // The URI for which diagnostic information is reported.
    property uri: TDocumentUri read fUri write fUri;

    // The version number of the document the diagnostics are published for.
    // todo: this must be optional
    //property version: integer read fVersion write fVersion;

    // An array of diagnostic information items.
    property diagnostics: TDiagnosticItems read fDiagnostics write SetDiagnostics;
  public
    Constructor Create; override;
    Destructor Destroy; override;
  end;

  { TPublishDiagnostics }

  { Diagnostics notification are sent from the server to the client to signal results of validation runs.

    Diagnostics are “owned” by the server so it is the server’s responsibility to clear them if necessary. 
    The following rule is used for VS Code servers that generate diagnostics:

    if a language is single file only (for example HTML) then diagnostics are cleared by the server when the file is closed.
    if a language has a project system (for example C#) diagnostics are not cleared when a file closes. When a project is 
    opened all diagnostics for all files are recomputed (or read from a cache).
    When a file changes it is the server’s responsibility to re-compute diagnostics and push them to the client. If the 
    computed set is empty it has to push the empty array to clear former diagnostics. Newly pushed diagnostics always replace 
    previously pushed diagnostics. There is no merging that happens on the client side. }

  TPublishDiagnostics = class(TNotificationMessage)
  private
    fCodeToolErrors: TDiagnosticItems;
    fUserMessages: TDiagnosticItems;
    fParserErrors: TDiagnosticItems;
    function GetDiagnosticParams: TPublishDiagnosticsParams;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Send(aTransport : TMessageTransport); override;
    function HaveDiagnostics : Boolean;
    Property DiagnosticParams : TPublishDiagnosticsParams Read GetDiagnosticParams;
    procedure AddCodeToolErrorDiagnostic(fileName, message: string; line, column, code: integer; severity: TDiagnosticSeverity);
    procedure AddUserMessage(message: string; line, column, code: integer; severity: TDiagnosticSeverity);
    procedure Add(fileName, message: string; line, column, code: integer; severity: TDiagnosticSeverity);
    procedure ClearUserMessages;
    procedure ClearCodeToolErrors(fileName: string);
    procedure Clear(fileName: string);
  end;


implementation

uses SysUtils;

{ TPublishDiagnostics }

procedure TPublishDiagnostics.ClearUserMessages;
begin
  DiagnosticParams.uri := '';
  fUserMessages.Clear;
end;

procedure TPublishDiagnostics.ClearCodeToolErrors(fileName: string);
begin
  DiagnosticParams.uri := PathToURI(fileName);
  fCodeToolErrors.Clear;
end;

procedure TPublishDiagnostics.Clear(fileName: string);
begin
  DiagnosticParams.uri := PathToURI(fileName);
  DiagnosticParams.diagnostics.Clear;
end;

procedure TPublishDiagnostics.AddUserMessage(message: string; line, column, code: integer; severity: TDiagnosticSeverity);
var
  Diagnostic: TDiagnostic;
begin
  DiagnosticParams.uri := PathToURI(fileName);
  Diagnostic := fUserMessages.Add;
  Diagnostic.range.SetRange(line, column);
  Diagnostic.severity := severity;
  Diagnostic.code := code;
  Diagnostic.source := 'Free Pascal Compiler';
  Diagnostic.message := message;
end;

procedure TPublishDiagnostics.Add(fileName, message: string; line, column, code: integer; severity: TDiagnosticSeverity);
var
  Diagnostic: TDiagnostic;
begin
  DiagnosticParams.uri := PathToURI(fileName);
  Diagnostic := DiagnosticParams.diagnostics.Add;
  Diagnostic.range.SetRange(line, column);
  Diagnostic.severity := severity;
  Diagnostic.code := code;
  Diagnostic.source := 'Free Pascal Compiler';
  Diagnostic.message := message;
end;

function TPublishDiagnostics.GetDiagnosticParams: TPublishDiagnosticsParams;

begin
  Result:=Params as TPublishDiagnosticsParams;
end;

constructor TPublishDiagnostics.Create;
begin  
  fCodeToolErrors := TDiagnosticItems.Create;
  fUserMessages := TDiagnosticItems.Create;
  fParserErrors := TDiagnosticItems.Create;
  
  params := TPublishDiagnosticsParams.Create;
  method := 'textDocument/publishDiagnostics';
end;

destructor TPublishDiagnostics.Destroy; 
begin
  params.Free;
  fCodeToolErrors.Free;
  fUserMessages.Free;
  fParserErrors.Free;
  
  inherited;
end;

procedure TPublishDiagnostics.Send(aTransport : TMessageTransport);
begin
  
end;

function TPublishDiagnostics.HaveDiagnostics: Boolean;
begin
  Result:=(fUserMessages.Count + fCodeToolErrors.Count + fParserErrors.Count)>0;
end;

{ TPublishDiagnosticsParams }

procedure TPublishDiagnosticsParams.SetDiagnostics(AValue: TDiagnosticItems);
begin
  if fDiagnostics=AValue then Exit;
  fDiagnostics.Assign(AValue);
end;

constructor TPublishDiagnosticsParams.Create;
begin
  inherited;
  fdiagnostics := TDiagnosticItems.Create;
end;

destructor TPublishDiagnosticsParams.Destroy;
begin
  FreeAndNil(fDiagnostics);
  inherited Destroy;
end;


end.
