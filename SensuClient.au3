#include "Array.au3"
#include <Date.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <TreeViewConstants.au3>
#include <ColorConstants.au3>
#include <GuiTreeView.au3>
#include <EditConstants.au3>
#include <GuiStatusBar.au3>

Global $listArray[10000000], $menuInfo
Global Const $HTTP_STATUS_OK = 200
Opt("GUIOnEventMode", 1)

; Generate settings file on first run
If NOT FileExists("sensuclient.ini") Then
   Global $startup = true
   Global $serverAddress = ""
   Global $serverPort = "4567"
   Global $resolveAddress = "/resolve"
   Global $deleteAddress = "/clients/"
   Global $systemFilter = ".*"
   settingsWin($startup)
EndIf
   Global $startup = false
   readSettings()
   drawGui()

Func drawGui()
   ;Opt("GUIOnEventMode", 1)
   ;GUI
   Global $hGUI = GUICreate("Sensu Events", 456, 782, -1, -1, $WS_SIZEBOX + $WS_SYSMENU)
   Local $arrayNames[1]
   GUISetState(@SW_SHOW)
   Global $mylist = GUICtrlCreateTreeView( 5, 0, 450, 710 )
   GUICtrlSetBkColor($mylist, 0xF0F0F0)
   GUICtrlSetResizing($mylist, $GUI_DOCKAUTO)
   Global $fileMenu = GUICtrlCreateMenu("&File")
   Global $settingsMenu = GUICtrlCreateMenuItem("Settings", $fileMenu)
   Global $helpMenu = GUICtrlCreateMenuItem("About", $fileMenu)
   Global $hTimer = 30000
   While 1
	  ; Create menu on events
	  GUISetOnEvent($GUI_EVENT_CLOSE, "closeWin")
	  GUICtrlSetOnEvent($settingsMenu, "settingsWin")
	  GUICtrlSetOnEvent($helpMenu, "aboutWin")
	  If TimerDiff($hTimer) > 30000 Then
		 Global $sTemp = HttpGet("http://"&$serverAddress&":"&$serverPort&"/events")
		 Local $output = StringTrimLeft($sTemp, 1)
		 $output = StringTrimRight($output, 1)
		 ; fix decimals without qoutes around them
		 $output = StringRegExpReplace($output, ':(\d+\.\d+)', ':"$1"')
		 $output = StringRegExpReplace($output, ':(\d+)(,|\})', ':"$1"$2')
		 ; clean up empty arrays for subscribers that are for remedediation
		 $output = StringRegExpReplace($output, '"subscribers":[\"?[a-z]+?\"?]+,', '')
		 $output = StringRegExpReplace($output, '\\"', '')
		 $output = StringRegExpReplace($output, '\[(\d+,?)+\]', '[""]')
		 $splitArray = StringSplit($output, '{"id"', 1)
			Global $sClients = HttpGet("http://"&$serverAddress&":"&$serverPort&"/clients")
			; Get list of - delimited stuff
			$sClients = StringSplit($sClients, 'name', 1)
			_GUICtrlTreeView_DeleteAll($mylist)
			$sitePercent = Round((Int(UBound($splitArray)) / Int($arrayNames[0])) * 100, 2)
			$topLabel = "Total Events "&UBound($splitArray)-2& " --- Total Clients "&$sClients[0]-1
			Local $aParts[3] = [100, 175, -1]
			$g_hStatus = _GUICtrlStatusBar_Create($hGUI,0,$topLabel)
			GUICtrlSetResizing($topLabel, $GUI_DOCKHEIGHT)
			For $r=2 To $splitArray[0]-2
			   $cleanArray = StringTrimRight('{"id"'&$splitArray[$r], 1)
			   $brokenArray = _JSON_Decode($cleanArray)
			   ; Get hostname
			   $name = $brokenArray[1][1]
			   Global $arrayNames[1]
			   For $i=0 To UBound($name)-1
				  If StringInStr($name[$i][0], "name") Then
					 Local $hostNameFull = $name[$i][1]
				  EndIf
			   Next
			   ; Filter by system name
			   $filterSplit = StringSplit($systemFilter, ",")
			   For $f=1 to UBound($filterSplit)-1
				  If StringRegExp($hostNameFull, $filterSplit[$f]) Then
					 ; Get checkname
					 $check = $brokenArray[2][1]
					 For $i=0 To UBound($check)-1
						If StringInStr($check[$i][0], "name") Then
						   $checkName = $check[$i][1]
						EndIf
					 Next
					 ; Get output
					 $output = $brokenArray[2][1]
					 For $i=0 To UBound($output)-1
						If StringInStr($output[$i][0], "output") Then
						   $outputName = $output[$i][1]
						   ; Cleanup Output
						   $outputName = StringRegExpReplace($outputName, "(\\r\\n|\\n)", " ")
						   $outputName = StringRegExpReplace($outputName, "\\\\", '\\')
						EndIf
					 Next
					 $hostName = StringSplit($hostNameFull, ".")
					 Local $topName = GUICtrlCreateTreeViewItem(StringUpper($hostName[1])&": "&$checkName, $mylist)
					 $menuInfo = contextMenu($topName, $hostNameFull, $checkName)
					 $listArray[Int($menuInfo)] = $hostNameFull&","&$checkName
					 
					 For $g=0 to UBound($check)-1
						$checkName = $check[$g][0]
						$checkOutput = $check[$g][1]
						$checkOutput = StringRegExpReplace($checkOutput, "(\\r\\n|\\n)", " ")
						$checkOutput = StringRegExpReplace($checkOutput, "\\\\", '\\')
						If $checkName = "issued" OR $checkName = "executed" Then
						   $checkOutput = _DateAdd("s", Int($checkOutput)-18000, "1970/01/01 00:00:00")
						EndIf
						If NOT $checkOutput = "" Then
						   Global $treeItem = GUICtrlCreateTreeViewItem(StringUpper($checkName)&": "&$checkOutput, $topName)
						EndIf		   
					 Next
					 If StringInStr($outputName, "CRITICAL") then ; red
						GUICtrlSetBkColor($topName, 0xFF6666)
					 ElseIf StringInStr($outputName, "WARNING") Then ; yellow
						GUICtrlSetBkColor($topName, 0xFFFF99)
					 ElseIf StringInStr($outputName, "OK") Then ; green
						GUICtrlSetBkColor($topName, 0x66FF66)
					 Else ; gray
						GUICtrlSetBkColor($topName, 0xCCCCCC)
					 EndIf
				  EndIf
			   Next
			Next
		 $hTimer = TimerInit()
	  EndIf
   WEnd  
EndFunc


Func _JSON_Decode($sString)
	Local $iIndex, $aVal, $sOldStr = $sString, $b

	$sString = StringStripCR(StringStripWS($sString, 7))
	If Not StringRegExp($sString, "(?i)^\{.+}$") Then Return SetError(1, 0, 0)
	Local $aArray[1][2], $iIndex = 0
	$sString = StringMid($sString, 2)

	Do
		$b = False

		$aVal = StringRegExp($sString, '^"([^"]+)"\s*:\s*(["{[]|[-+]?\d+(?:(?:\.\d+)?[eE][+-]\d+)?|true|false|null)', 2) ; Get value & next token
		If @error Then
			ConsoleWrite("!> StringRegExp Error getting next Value." & @CRLF)
			ConsoleWrite($sString & @CRLF)
			$sString = StringMid($sString, 2) ; maybe it works when the string is trimmed by 1 char from the left ?
			ContinueLoop
		EndIf

		$aArray[$iIndex][0] = $aVal[1] ; Key
		$sString = StringMid($sString, StringLen($aVal[0]))

		Switch $aVal[2] ; Value Type (Array, Object, String) ?
			Case '"' ; String
				; Value -> Array subscript. Trim String after that.

				$aArray[$iIndex][1] = StringMid($sString, 2, StringInStr($sString, """", 1, 2) - 2)
				$sString = StringMid($sString, StringLen($aArray[$iIndex][1]) + 3)

				ReDim $aArray[$iIndex + 2][2]
				$iIndex += 1

			Case '{' ; Object
				; Recursive function call which will decode the object and return it.
				; Object -> Array subscript. Trim String after that.

				$aArray[$iIndex][1] = _JSON_Decode($sString)
				$sString = StringMid($sString, @extended + 2)
				If StringLeft($sString, 1) = "," Then $sString = StringMid($sString, 2)

				$b = True
				ReDim $aArray[$iIndex + 2][2]
				$iIndex += 1

			Case '[' ; Array
				; Decode Array
				$sString = StringMid($sString, 2)
				Local $aRet[1], $iArIndex = 0 ; create new array which will contain the Json-Array.

				Do
					$sString = StringStripWS($sString, 3) ; Trim Leading & trailing spaces
					$aNextArrayVal = StringRegExp($sString, '^\s*(["{[]|\d+(?:(?:\.\d+)?[eE]\+\d+)?|true|false|null)', 2)
					;_ArrayDisplay($aNextArrayVal)
				  If Not StringInStr($aNextArrayVal[1], '"') Then
					 MsgBox(0, "", $aNextArrayVal[1])
				  EndIf
				  	Switch $aNextArrayVal[1]
						Case '"' ; String
							; Value -> Array subscript. Trim String after that.
							$aRet[$iArIndex] = StringMid($sString, 2, StringInStr($sString, """", 1, 2) - 2)
							$sString = StringMid($sString, StringLen($aRet[$iArIndex]) + 3)

						Case "{" ; Object
							; Recursive function call which will decode the object and return it.
							; Object -> Array subscript. Trim String after that.
							$aRet[$iArIndex] = _JSON_Decode($sString)
							$sString = StringMid($sString, @extended + 2)

						Case "["
							MsgBox(0, "", "Array in Array. WTF is up with this JSON shit?")
							MsgBox(0, "", "This should not happen! Please post this!")
							Exit 0xDEADBEEF

						Case Else
							ConsoleWrite("Array Else (maybe buggy?)" & @CRLF)
							$aRet[$iArIndex] = $aNextArrayVal[1]
					EndSwitch

					ReDim $aRet[$iArIndex + 2]
					$iArIndex += 1

					$sString = StringStripWS($sString, 3) ; Leading & trailing
					If StringLeft($sString, 1) = "]" Then ExitLoop
					$sString = StringMid($sString, 2)
				Until False

				$sString = StringMid($sString, 2)
				ReDim $aRet[$iArIndex]
				$aArray[$iIndex][1] = $aRet

				ReDim $aArray[$iIndex + 2][2]
				$iIndex += 1

			Case Else ; Number, bool
				; Value (number (int/flaot), boolean, null) -> Array subscript. Trim String after that.
				$aArray[$iIndex][1] = $aVal[2]
				ReDim $aArray[$iIndex + 2][2]
				$iIndex += 1
				$sString = StringMid($sString, StringLen($aArray[$iIndex][1]) + 2)
		EndSwitch

		If StringLeft($sString, 1) = "}" Then
			StringMid($sString, 2)
			ExitLoop
		EndIf
		If Not $b Then $sString = StringMid($sString, 2)
	Until False

	ReDim $aArray[$iIndex][2]
	Return SetError(0, StringLen($sOldStr) - StringLen($sString), $aArray)
 EndFunc   ;==>_JSON_Decode

; Creating rightclick menu
Func contextMenu($MenuParent, $hostname, $checkname)
	  $contextmenu = GUICtrlCreateContextMenu($MenuParent)
	  $textitem = GUICtrlCreateMenuItem("Resolve Issue", $contextmenu)
	  $textitem2 = GUICtrlCreateMenuItem("Remove Host", $contextmenu)
	  	 GUICtrlSetOnEvent($textitem, "Resolve")
		 GUICtrlSetOnEvent($textitem2, "Delete")
	  return $MenuParent
EndFunc

; resolve issue in sensu
Func Resolve()
   $splitName = StringSplit($listArray[@GUI_CtrlId-2], ",")
   $postData = '{"client": "'&$splitName[1]&'", "check": "'&$splitName[2]&'"}'
   Local $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")
   $oHTTP.Open("POST", "http://"&$serverAddress&":"&$serverPort&$resolveAddress, False)
	  $oHTTP.SetRequestHeader("Content-Type", "application/json")
	  $oHTTP.Send($postData)
	  If $oHTTP.Status = '202' Then
		 MsgBox(0, "Success!", $splitName[2]&" on "&$splitName[1]&" was resolved successfully")
	  Else
		 MsgBox(0, "Fail!", $splitName[2]&" on "&$splitName[1]&" was not resolved successfully")
	  EndIf
EndFunc

; delete system from sensu
Func Delete()
   $splitDelete = StringSplit($listArray[@GUI_CtrlId-3], ",")
   Local $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")
   $oHTTP.Open("DELETE", "http://"&$serverAddress&":"&$serverPort&$deleteAddress&$splitDelete[1], False)
	  $oHTTP.Send()
	  If $oHTTP.Status = '202' Then
		 MsgBox(0, "Success!", $splitDelete[1]&" was deleted successfully")
	  Else
		 MsgBox(0, "Fail!", $splitDelete[1]&" was not deleted successfully")
	  EndIf
EndFunc

; generate settings window
Func settingsWin($startup = false)
   Opt("GUIOnEventMode", 1)
   If NOT WinGetTitle("SensuClient Settings") Then
	  Global $settingsWindow = GUICreate("SensuClient Settings", 440, 280, 100, 100) ; will create a dialog box
	  GUICtrlCreateLabel("Server Address", 10, 5, 30)
	  Global $ServerAddressSave = GUICtrlCreateInput($serverAddress, 10, 20, 100, 20)
	  GUICtrlSetTip(-1, "Place the sensu server address in here, excluding the http://.")
	  GUICtrlCreateLabel("Port", 150, 5, 30)
	  Global $ServerPortSave = GUICtrlCreateInput($serverPort, 150, 20, 50, 20)
	  GUICtrlSetTip(-1, "Place the sensu port here (Ex: 4567).")
	  GUICtrlCreateLabel("API Resolve Suffix", 10, 45, 100)
	  Global $ServerAPIResolveSave = GUICtrlCreateInput($resolveAddress, 10, 60, 50, 20)
	  GUICtrlSetTip(-1, "Place the sensu resolve api suffix here (Ex: /resolve).")
	  GUICtrlCreateLabel("API Delete Suffix", 150, 45, 100)
	  Global $ServerAPIDeleteSave = GUICtrlCreateInput($deleteAddress, 150, 60, 50, 20)
	  GUICtrlSetTip(-1, "Place the sensu delete api suffix here (Ex: /clients/).")
	  GUICtrlCreateLabel('Filters', 10, 85, 30)
	  Global $FiltersSave = GUICtrlCreateEdit($systemFilter, 10, 100, 420, 100, $ES_AUTOVSCROLL + $WS_VSCROLL + $ES_MULTILINE + $ES_WANTRETURN) 
	  GUICtrlSetTip(-1, "Place your regular expression filters in here, comma separated. (Ex: .*AUTO.*)")
	  $BTNSAVE = GUICtrlCreateButton("&Save", 230, 250, 100)
	  GUICtrlSetOnEvent($BTNSAVE, "saveSettings")
	  GUICtrlSetTip(-1, "Save program settings")
	  $BTNEXIT = GUICtrlCreateButton("&Cancel", 335, 250, 100)
	  GUICtrlSetOnEvent($BTNEXIT, "closeSettings")
	  GUISetState()
   EndIf
   If NOT $startup = false Then
	While 1
		Sleep(1000)
	WEnd
   EndIf
EndFunc

Func aboutWin()
   MsgBox(0, "About", "Created by Christopher Phipps 2015 (hawtdogflvrwtr@gmail.com)"&@CRLF&"Tested with sensu 0.16")
EndFunc

Func closeWin()
   Exit
EndFunc

Func closeSettings()
   GUIDelete($settingsWindow)
   If $startup = true Then
	  Exit
   EndIf
EndFunc

Func saveSettings()
   $FiltersSave = GUICtrlRead($FiltersSave)
   $ServerAddressSave = GUICtrlRead($ServerAddressSave)
   $ServerPortSave = GUICtrlRead($ServerPortSave)
   $ServerAPIResolveSave = GUICtrlRead($ServerAPIResolveSave)
   $ServerAPIDeleteSave = GUICtrlRead($ServerAPIDeleteSave)
   $writeServer = IniWrite("sensuclient.ini", "Configuration", "server", $ServerAddressSave)
   $writePort = IniWrite("sensuclient.ini", "Configuration", "port", $ServerPortSave)
   $writeFilters = IniWrite("sensuclient.ini", "Configuration", "filters", $FiltersSave)
   $writeResolve = IniWrite("sensuclient.ini", "Configuration", "resolve", $ServerAPIResolveSave)
   $writeDelete = IniWrite("sensuclient.ini", "Configuration", "delete", $ServerAPIDeleteSave)
   IF NOT $writeServer Or NOT $writePort Or NOT $writeFilters Then
	  MsgBox(0, "Error Saving", "Unable to save configuration file. Please check permissions")
   EndIf
   GUIDelete($settingsWindow)
   readSettings()
   If $startup = true Then
	  MsgBox(0, "Saved", "Configuration saved. Please relaunch this application for settings to take effect.")
	  Exit
   EndIf
   ;refresh screen
   Global $hTimer = 30000
EndFunc

Func readSettings()
   Global $serverAddress = IniRead("sensuclient.ini", "Configuration", "server", "")
   Global $serverPort = IniRead("sensuclient.ini", "Configuration", "port", "")
   Global $resolveAddress = IniRead("sensuclient.ini", "Configuration", "resolve", "/resolve")
   Global $deleteAddress = IniRead("sensuclient.ini", "Configuration", "delete", "/clients/")
   Global $systemFilter = IniRead("sensuclient.ini", "Configuration", "filters", ".*")   
EndFunc

Func HttpPost($sURL, $sData = "")
Local $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")

$oHTTP.Open("POST", $sURL, False)
If (@error) Then Return SetError(1, 0, 0)

$oHTTP.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded")

$oHTTP.Send($sData)
If (@error) Then Return SetError(2, 0, 0)

If ($oHTTP.Status <> $HTTP_STATUS_OK) Then Return SetError(3, 0, 0)

Return SetError(0, 0, $oHTTP.ResponseText)
EndFunc

Func HttpGet($sURL, $sData = "")
Local $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")

$oHTTP.Open("GET", $sURL & "?" & $sData, False)
If (@error) Then Return SetError(1, 0, 0)

$oHTTP.Send()
If (@error) Then Return SetError(2, 0, 0)

If ($oHTTP.Status <> $HTTP_STATUS_OK) Then Return SetError(3, 0, 0)

Return SetError(0, 0, $oHTTP.ResponseText)
EndFunc   
   

