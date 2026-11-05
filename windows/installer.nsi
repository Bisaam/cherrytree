; CherryTree - per-user Windows installer, built by windows/msys2-build.sh
; makensis -DCT_VERSION=1.2.0 -DSTAGE_DIR=<portable folder> -DOUT_FILE=<setup.exe> -DICON_FILE=<cherrytree.ico> installer.nsi

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user
ManifestDPIAware true

!ifndef CT_VERSION
  !error "CT_VERSION not defined"
!endif

!define APP_NAME     "CherryTree"
!define APP_EXE      "ucrt64\bin\cherrytree.exe"
!define UNINST_KEY   "Software\Microsoft\Windows\CurrentVersion\Uninstall\CherryTreeKali"

Name "${APP_NAME} ${CT_VERSION}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\CherryTree"
InstallDirRegKey HKCU "Software\CherryTreeKali" "InstallDir"
Icon "${ICON_FILE}"
UninstallIcon "${ICON_FILE}"
BrandingText "CherryTree ${CT_VERSION}"

!include "MUI2.nsh"
!define MUI_ICON   "${ICON_FILE}"
!define MUI_UNICON "${ICON_FILE}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch CherryTree"

!insertmacro MUI_PAGE_LICENSE "${STAGE_DIR}\license.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

!macro AssocExt EXT PROGID DESC
  WriteRegStr HKCU "Software\Classes\${EXT}" "" "${PROGID}"
  WriteRegStr HKCU "Software\Classes\${PROGID}" "" "${DESC}"
  WriteRegStr HKCU "Software\Classes\${PROGID}\DefaultIcon" "" '"$INSTDIR\${APP_EXE}",0'
  WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open\command" "" '"$INSTDIR\${APP_EXE}" "%1"'
!macroend

!macro UnAssocExt EXT PROGID
  ReadRegStr $0 HKCU "Software\Classes\${EXT}" ""
  StrCmp $0 "${PROGID}" 0 +2
    DeleteRegKey HKCU "Software\Classes\${EXT}"
  DeleteRegKey HKCU "Software\Classes\${PROGID}"
!macroend

; Before replacing/removing files: CherryTree must not be running from $INSTDIR (asks, never kills it:
; there could be unsaved notes), and the GLib D-Bus helper (gdbus.exe) a session leaves behind for a
; little while is stopped, as it keeps the GLib DLLs locked. Only processes started from $INSTDIR.
!macro CLOSE_RUNNING_FUNC UN
Function ${UN}CloseRunning
  retry:
    IfFileExists "$INSTDIR\ucrt64\bin\cherrytree.exe" 0 done
    ClearErrors
    FileOpen $1 "$INSTDIR\ucrt64\bin\cherrytree.exe" a   ; fails while the exe is running
    IfErrors 0 not_running
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "CherryTree is running from$\r$\n$INSTDIR$\r$\n$\r$\nSave your notes, close CherryTree, then click Retry." /SD IDCANCEL IDRETRY retry
      Abort
  not_running:
    FileClose $1
    StrCpy $2 0
  gdbus_check:   ; wait (max ~10 s) until gdbus.exe is no longer running / locked
    IfFileExists "$INSTDIR\ucrt64\bin\gdbus.exe" 0 done
    ClearErrors
    FileOpen $1 "$INSTDIR\ucrt64\bin\gdbus.exe" a
    IfErrors 0 gdbus_free
      nsExec::Exec `powershell.exe -NoProfile -NonInteractive -Command "Get-Process gdbus -ErrorAction SilentlyContinue | Where-Object { $$_.Path -like '$INSTDIR\*' } | Stop-Process -Force"`
      Pop $0
      Sleep 500
      IntOp $2 $2 + 1
      IntCmp $2 20 done gdbus_check done
  gdbus_free:
    FileClose $1
  done:
FunctionEnd
!macroend
!insertmacro CLOSE_RUNNING_FUNC ""
!insertmacro CLOSE_RUNNING_FUNC "un."

Section "CherryTree" SecMain
  SectionIn RO
  Call CloseRunning
  ; replace an older install cleanly (keeps user data: that lives in %LOCALAPPDATA%\cherrytree-kali)
  RMDir /r "$INSTDIR\ucrt64"
  SetOutPath "$INSTDIR"
  File /r "${STAGE_DIR}\*.*"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  CreateShortCut "$SMPROGRAMS\CherryTree.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  Delete "$INSTDIR\CherryTree.cmd"  ; from older builds

  WriteRegStr HKCU "Software\CherryTreeKali" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "CherryTree ${CT_VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${CT_VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "Giuseppe Penone"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" '"$INSTDIR\${APP_EXE}",0'
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "https://www.giuspen.net/cherrytree/"
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1

  ; warm the fontconfig cache so the first start is fast
  DetailPrint "Building font cache..."
  nsExec::Exec '"$INSTDIR\ucrt64\bin\fc-cache.exe"'
  Pop $0
SectionEnd

Section "Open .ctb .ctx .ctd .ctz files with CherryTree" SecAssoc
  !insertmacro AssocExt ".ctb" "CherryTreeB" "CherryTree SQLite Document"
  !insertmacro AssocExt ".ctx" "CherryTreeX" "CherryTree SQLite Zipped"
  !insertmacro AssocExt ".ctd" "CherryTreeD" "CherryTree XML Document"
  !insertmacro AssocExt ".ctz" "CherryTreeZ" "CherryTree XML Zipped"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

Section /o "Desktop shortcut" SecDesktop
  CreateShortCut "$DESKTOP\CherryTree.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
SectionEnd

Section "Uninstall"
  Call un.CloseRunning
  Delete "$SMPROGRAMS\CherryTree.lnk"
  Delete "$DESKTOP\CherryTree.lnk"
  !insertmacro UnAssocExt ".ctb" "CherryTreeB"
  !insertmacro UnAssocExt ".ctx" "CherryTreeX"
  !insertmacro UnAssocExt ".ctd" "CherryTreeD"
  !insertmacro UnAssocExt ".ctz" "CherryTreeZ"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
  RMDir /r "$INSTDIR\ucrt64"
  Delete "$INSTDIR\license.txt"
  Delete "$INSTDIR\README.txt"
  Delete "$INSTDIR\CherryTree.cmd"
  Delete "$INSTDIR\CherryTree.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "Software\CherryTreeKali"
SectionEnd
