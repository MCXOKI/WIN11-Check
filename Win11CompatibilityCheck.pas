unit Win11CompatibilityCheck;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, System.Win.Registry,
  System.Generics.Collections, Winapi.ActiveX, ComObj,
  Winapi.ShlObj, System.IOUtils, System.StrUtils;

type
  TCompatibilityCheck = record
    IsCompatible: Boolean;
    Messages: TArray<string>;
  end;

  TWin11CompatibilityChecker = class
  private
    FMessages: TList<string>;
    FIsCompatible: Boolean;

    procedure AddMessage(const Msg: string; const ACompatible: Boolean = False);

    function GetCPUInfo: string;

    function CheckTPM20: Boolean;
    function CheckSecureBoot: Boolean;
    function CheckCPU: Boolean;
    function CheckRAM: Boolean;
    function CheckDiskSpace: Boolean;
    function CheckArchitecture: Boolean;
    function CheckDisplay: Boolean;
    function CheckBIOSMode: Boolean;
    function CheckStorageType: Boolean;

  public
    constructor Create;
    destructor Destroy; override;
    function GetBIOSInfo: string;

    function CheckCompatibility: TCompatibilityCheck;
  end;

function CheckWin11Compatibility: TCompatibilityCheck;

implementation

function CheckWin11Compatibility: TCompatibilityCheck;
var
  Checker: TWin11CompatibilityChecker;
begin
  Checker := TWin11CompatibilityChecker.Create;
  try
    Result := Checker.CheckCompatibility;
  finally
    Checker.Free;
  end;
end;

{ TWin11CompatibilityChecker }

constructor TWin11CompatibilityChecker.Create;
begin
  inherited;
  FMessages := TList<string>.Create;
  FIsCompatible := True;
end;

destructor TWin11CompatibilityChecker.Destroy;
begin
  FMessages.Free;
  inherited;
end;

procedure TWin11CompatibilityChecker.AddMessage(const Msg: string; const ACompatible: Boolean);
begin
  if ACompatible then
    FMessages.Add('✓ ' + Msg)
  else
  begin
    FMessages.Add('✗ ' + Msg);
    FIsCompatible := False;
  end;
end;

function TWin11CompatibilityChecker.CheckTPM20: Boolean;
var
  Locator, WMIService, Collection, Item: OLEVariant;
  Enum: IEnumVariant;
  Value: LongWord;
  Version: string;
begin
  Result := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    WMIService := Locator.ConnectServer('.', 'root\cimv2');
    Collection := WMIService.ExecQuery('SELECT * FROM Win32_Tpm');

    Enum := IUnknown(Collection._NewEnum) as IEnumVariant;
    while Enum.Next(1, Item, Value) = 0 do
    begin
      Version := Item.SpecVersion;
      if Pos('2.0', Version) > 0 then
      begin
        Result := True;
        Break;
      end;
    end;

    AddMessage('TPM 2.0: ' + IfThen(Result, 'обнаружен', 'не обнаружен или ниже 2.0'), Result);
  except
    on E: Exception do
      AddMessage('Ошибка при проверке TPM: ' + E.Message, False);
  end;
end;

function TWin11CompatibilityChecker.CheckSecureBoot: Boolean;
var
  Reg: TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.KeyExists('SYSTEM\CurrentControlSet\Control\SecureBoot\State') and
       Reg.OpenKeyReadOnly('SYSTEM\CurrentControlSet\Control\SecureBoot\State') then
    begin
      Result := Reg.ReadInteger('UEFISecureBootEnabled') = 1;
      Reg.CloseKey;
    end;

    AddMessage('Secure Boot: ' + IfThen(Result, 'включён', 'отключён или не поддерживается'), Result);
  finally
    Reg.Free;
  end;
end;

function TWin11CompatibilityChecker.CheckCPU: Boolean;
var
  SysInfo: TSystemInfo;
  CPUName: string;
  Is64Bit: Boolean;
begin
  GetSystemInfo(SysInfo);
  CPUName := GetCPUInfo;
  Is64Bit := (SysInfo.wProcessorArchitecture = PROCESSOR_ARCHITECTURE_AMD64);

  AddMessage('Процессор: ' + CPUName, Is64Bit);
  AddMessage('Архитектура CPU: ' + IfThen(Is64Bit, 'x64 (поддерживается)', 'не поддерживается'), Is64Bit);

  Result := Is64Bit;
end;

function TWin11CompatibilityChecker.CheckRAM: Boolean;
var
  MemStatus: TMemoryStatusEx;
  TotalGB: Double;
begin
  FillChar(MemStatus, SizeOf(MemStatus), 0);
  MemStatus.dwLength := SizeOf(MemStatus);
  GlobalMemoryStatusEx(MemStatus);

  TotalGB := MemStatus.ullTotalPhys / 1024 / 1024 / 1024;
  Result := TotalGB >= 4;

  AddMessage(Format('ОЗУ: %.2f ГБ (минимум 4 ГБ)', [TotalGB]), Result);
end;

function TWin11CompatibilityChecker.CheckDiskSpace: Boolean;
var
  FreeBytes, TotalBytes, TotalFree: ULARGE_INTEGER;
  TotalGB: Double;
  Drive: string;
begin
  Result := False;
  Drive := ExtractFileDrive(GetCurrentDir);

  if GetDiskFreeSpaceEx(PChar(Drive + '\'), @FreeBytes, @TotalBytes, @TotalFree) then
  begin
    TotalGB := TotalBytes.QuadPart / 1024 / 1024 / 1024;
    Result := TotalGB >= 64;
    AddMessage(Format('Объём диска: %.2f ГБ (минимум 64 ГБ)', [TotalGB]), Result);
  end
  else
    AddMessage('Ошибка определения объёма диска', False);
end;

function TWin11CompatibilityChecker.CheckArchitecture: Boolean;
begin
  Result := TOSVersion.Architecture = arIntelX64;
  AddMessage('Системная архитектура: ' + IfThen(Result, 'x64 (совместима)', 'не совместима'), Result);
end;

function TWin11CompatibilityChecker.CheckDisplay: Boolean;
var
  DevMode: TDevMode;

const
  ENUM_CURRENT_SETTINGS = Cardinal(-1);
begin
  Result := False;
  if EnumDisplaySettings(nil, ENUM_CURRENT_SETTINGS, DevMode) then
  begin
    Result := (DevMode.dmPelsWidth >= 800) and (DevMode.dmPelsHeight >= 600);
    AddMessage(Format('Разрешение экрана: %dx%d (минимум 800x600)',
      [DevMode.dmPelsWidth, DevMode.dmPelsHeight]), Result);
  end
  else
    AddMessage('Ошибка определения разрешения экрана');
end;

function TWin11CompatibilityChecker.CheckBIOSMode: Boolean;
var
  Reg: TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('SYSTEM\CurrentControlSet\Control\SecureBoot\State') then
    begin
      Result := Reg.ValueExists('UEFISecureBootEnabled');
      Reg.CloseKey;
    end;
    AddMessage('Режим загрузки BIOS: ' + IfThen(Result, 'UEFI (совместим)', 'Legacy (не совместим)'), Result);
  finally
    Reg.Free;
  end;
end;

function TWin11CompatibilityChecker.CheckStorageType: Boolean;
var
  DriveType: UINT;
  Drive: string;
  Message: string;
begin
  Drive := ExtractFileDrive(GetCurrentDir);
  DriveType := GetDriveType(PChar(Drive + '\'));
  Result := DriveType = DRIVE_FIXED;

  case DriveType of
    DRIVE_FIXED:    Message := 'Жёсткий диск или SSD (совместим)';
    DRIVE_REMOVABLE:Message := 'Съёмный накопитель (возможны проблемы)';
    DRIVE_CDROM:    Message := 'CD/DVD привод (не совместим)';
  else
    Message := 'Неизвестный тип накопителя';
  end;
  AddMessage('Тип накопителя: ' + Message, Result);
end;

function TWin11CompatibilityChecker.GetCPUInfo: string;
var
  Reg: TRegistry;
begin
  Result := 'Неизвестный процессор';
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('HARDWARE\DESCRIPTION\System\CentralProcessor\0') then
      Result := Reg.ReadString('ProcessorNameString');
  finally
    Reg.Free;
  end;
end;

function TWin11CompatibilityChecker.GetBIOSInfo: string;
var
  Reg: TRegistry;
begin
  Result := 'BIOS неизвестен';
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('HARDWARE\DESCRIPTION\System\BIOS') then
    begin
      Result := Reg.ReadString('BIOSVersion') + ' - ' + Reg.ReadString('BIOSReleaseDate');
    end;
  finally
    Reg.Free;
  end;
end;

function TWin11CompatibilityChecker.CheckCompatibility: TCompatibilityCheck;
begin
  FMessages.Clear;
  FIsCompatible := True;

  AddMessage('=== Проверка совместимости с Windows 11 ===', True);

  CheckArchitecture;
  CheckCPU;
  CheckRAM;
  CheckDiskSpace;
  CheckDisplay;
  CheckBIOSMode;
  CheckStorageType;
  CheckTPM20;
  CheckSecureBoot;

  AddMessage('=== Результат проверки ===', True);
  if FIsCompatible then
    AddMessage('Система совместима с Windows 11 ✔️', True)
  else
    AddMessage('Система НЕ совместима с Windows 11 ❌', False);

  Result.IsCompatible := FIsCompatible;
  Result.Messages := FMessages.ToArray;
end;

end.
