#Requires AutoHotkey v2.0
#SingleInstance Force

; Roblox ignores clicks from non-admin scripts, so relaunch as admin
if !A_IsAdmin {
    try Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp
}

CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"
SendMode "Event"
SetMouseDelay 10

; ===== StreamedATDMacro: Cast + Scan (new GUI) + Shake =====
; F3 = Start / Stop     F5 = Refresh (reload)     F1 = Close
; Phase 1: Casting | Phase 2: Shaking | Phase 3: Finished, restarting loop

global running := false
global capW := 0, capH := 0, hdcMem := 0, hbm := 0, pBits := 0
global baseBuf := 0, curBuf := 0

global gui1 := Gui("+AlwaysOnTop", "StreamedATDMacro")
gui1.SetFont("s9")

AddRow(label, default) {
    gui1.Add("Text", "xm w230", label)
    return gui1.Add("Edit", "x+5 w90", default)
}

gui1.Add("Text", "xm w330", "Presets (pick one, or type a new name and press Save)")
cmbPreset := gui1.Add("ComboBox", "xm w330")
saveBtn := gui1.Add("Button", "xm w105", "Save")
saveBtn.OnEvent("Click", (*) => SavePreset())
loadBtn := gui1.Add("Button", "x+5 w105", "Load")
loadBtn.OnEvent("Click", (*) => LoadPreset())
delBtn := gui1.Add("Button", "x+5 w105", "Delete")
delBtn.OnEvent("Click", (*) => DeletePreset())
gui1.Add("Text", "xm y+8 w330 0x10")   ; separator line

eCastHold  := AddRow("Cast hold time (ms)", "600")
ePostCast  := AddRow("Delay after cast (ms)", "1500")
eScan      := AddRow("Shake scan interval (ms)", "30")
eClick     := AddRow("Delay before shake click (ms)", "40")
eClickHold := AddRow("Shake click hold time (ms)", "40")
eNextClick := AddRow("Delay before next shake click (ms)", "100")
eTimeout   := AddRow("Stop scanning after no new GUI for (ms)", "8000")
eCycle     := AddRow("Delay before next cast (ms)", "2000")
eSens      := AddRow("Change sensitivity (0-765, higher = less)", "90")
eMin       := AddRow("Min new GUI size (changed samples)", "12")
eStep      := AddRow("Sample step (px, higher = faster)", "8")

gui1.Add("Text", "xm y+12 w330", "Shake scan area (screen pixels, empty = whole Roblox window)")
eAx := AddRow("Area left (X)", "")
eAy := AddRow("Area top (Y)", "")
eAw := AddRow("Area width", "")
eAh := AddRow("Area height", "")
selBtn := gui1.Add("Button", "xm w220", "Select area (drag with mouse)")
selBtn.OnEvent("Click", (*) => SelectArea())
rstBtn := gui1.Add("Button", "x+5 w105", "Reset area")
rstBtn.OnEvent("Click", (*) => ResetArea())
chkShow := gui1.Add("Checkbox", "xm", "Show area outline")
chkShow.OnEvent("Click", (*) => UpdateOutline())
for ctrl in [eAx, eAy, eAw, eAh]
    ctrl.OnEvent("Change", (*) => UpdateOutline())

global fields := Map(
    "castHold", eCastHold, "postCast", ePostCast, "scanInterval", eScan,
    "clickDelay", eClick, "clickHold", eClickHold, "nextClickDelay", eNextClick,
    "timeout", eTimeout, "cycleDelay", eCycle, "sensitivity", eSens,
    "minSize", eMin, "step", eStep,
    "areaX", eAx, "areaY", eAy, "areaW", eAw, "areaH", eAh, "showOutline", chkShow)
global presetFile := A_ScriptDir "\StreamedATDMacro.ini"

stText := gui1.Add("Text", "xm y+12 w330 Center", "Status: STOPPED   |   F3 start/stop  F5 refresh  F1 close")
gui1.OnEvent("Close", (*) => ExitApp())
gui1.Show()
RefreshPresets()

; ---------- phase label (top of screen) ----------
global phaseGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
phaseGui.BackColor := "1E1E1E"
phaseGui.SetFont("s14 bold cWhite")
phaseText := phaseGui.Add("Text", "w460 Center", "Phase 1: Casting")

; ---------- area outline (4 thin bars just outside the area) ----------
global bars := []
Loop 4 {
    b := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    b.BackColor := "FF2D2D"
    bars.Push(b)
}

F3:: ToggleMacro()
F5:: Reload()
F1:: ExitApp()

ToggleMacro() {
    global running
    running := !running
    if running {
        phaseGui.Show("NA y8 x" ((A_ScreenWidth - 490) // 2))
        SetPhase(1)
        SetTimer(MacroLoop, -10)
    } else {
        phaseGui.Hide()
        stText.Value := "Status: STOPPED   |   F3 start"
    }
}

SetPhase(n) {
    txt := (n = 1) ? "Phase 1: Casting"
        : (n = 2) ? "Phase 2: Shaking"
        : "Phase 3: Finished, restarting loop"
    phaseText.Value := txt
    stText.Value := "Status: RUNNING   |   " txt
}

; ---------- presets (saved next to the script in StreamedATDMacro.ini) ----------
RefreshPresets() {
    cur := cmbPreset.Text
    cmbPreset.Delete()
    if FileExist(presetFile) {
        try {
            for name in StrSplit(IniRead(presetFile), "`n") {
                if (name != "")
                    cmbPreset.Add([name])
            }
        }
    }
    cmbPreset.Text := cur
}

SavePreset() {
    name := Trim(cmbPreset.Text)
    if (name = "") {
        stText.Value := "Type a preset name first"
        return
    }
    for key, ctrl in fields
        IniWrite(ctrl.Value, presetFile, name, key)
    RefreshPresets()
    stText.Value := "Preset saved: " name
}

LoadPreset() {
    name := Trim(cmbPreset.Text)
    if (name = "" || !FileExist(presetFile)
        || IniRead(presetFile, name, "castHold", "__none__") = "__none__") {
        stText.Value := "Preset not found: " name
        return
    }
    for key, ctrl in fields
        ctrl.Value := IniRead(presetFile, name, key, ctrl.Value)
    UpdateOutline()
    stText.Value := "Preset loaded: " name
}

DeletePreset() {
    name := Trim(cmbPreset.Text)
    if (name = "" || !FileExist(presetFile)) {
        stText.Value := "Pick a preset to delete"
        return
    }
    IniDelete(presetFile, name)
    cmbPreset.Text := ""
    RefreshPresets()
    stText.Value := "Preset deleted: " name
}

Num(ctrl, fallback) {
    try
        return Integer(ctrl.Value)
    catch
        return fallback
}

; ---------- regions ----------
GetRegion(&l, &t, &w, &h) {
    if WinExist("ahk_exe RobloxPlayerBeta.exe")
        WinGetClientPos &l, &t, &w, &h, "ahk_exe RobloxPlayerBeta.exe"
    else {
        l := 0, t := 0, w := A_ScreenWidth, h := A_ScreenHeight
    }
}

GetScanArea(&sl, &st, &sw, &sh, wl, wt, ww, wh) {
    sw := Num(eAw, 0), sh := Num(eAh, 0)
    if (sw > 0 && sh > 0) {
        sl := Num(eAx, 0), st := Num(eAy, 0)
    } else {
        sl := wl, st := wt, sw := ww, sh := wh
    }
}

ResetArea() {
    eAx.Value := "", eAy.Value := "", eAw.Value := "", eAh.Value := ""
    UpdateOutline()
}

UpdateOutline() {
    w := Num(eAw, 0), h := Num(eAh, 0)
    if (!chkShow.Value || w <= 0 || h <= 0) {
        for b in bars
            b.Hide()
        return
    }
    x := Num(eAx, 0), y := Num(eAy, 0), t := 3
    bars[1].Show("NA x" (x - t) " y" (y - t) " w" (w + 2 * t) " h" t)
    bars[2].Show("NA x" (x - t) " y" (y + h) " w" (w + 2 * t) " h" t)
    bars[3].Show("NA x" (x - t) " y" y " w" t " h" h)
    bars[4].Show("NA x" (x + w) " y" y " w" t " h" h)
}

; drag a rectangle on screen to set the scan area (Esc = cancel)
SelectArea() {
    ToolTip "Drag with the left mouse button to select the scan area (Esc = cancel)"
    ov := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
    ov.BackColor := "000000"
    ov.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    WinSetTransparent 60, "ahk_id " ov.Hwnd
    box := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    box.BackColor := "FF2D2D"

    Sleep 200
    while !GetKeyState("LButton", "P") {
        if GetKeyState("Escape", "P") {
            ToolTip
            ov.Destroy(), box.Destroy()
            return
        }
        Sleep 10
    }
    MouseGetPos &x1, &y1
    box.Show("NA x" x1 " y" y1 " w2 h2")
    WinSetTransparent 130, "ahk_id " box.Hwnd
    while GetKeyState("LButton", "P") {
        MouseGetPos &x2, &y2
        box.Move(Min(x1, x2), Min(y1, y2), Abs(x2 - x1) + 2, Abs(y2 - y1) + 2)
        Sleep 10
    }
    MouseGetPos &x2, &y2
    ToolTip
    ov.Destroy(), box.Destroy()

    w := Abs(x2 - x1), h := Abs(y2 - y1)
    if (w > 5 && h > 5) {
        eAx.Value := Min(x1, x2), eAy.Value := Min(y1, y2)
        eAw.Value := w, eAh.Value := h
        UpdateOutline()
    }
}

; ---------- screen capture (fast, in memory) ----------
InitCapture(w, h) {
    global capW, capH, hdcMem, hbm, pBits, baseBuf, curBuf
    if (capW = w && capH = h && hdcMem)
        return
    if hdcMem {
        DllCall("DeleteObject", "ptr", hbm)
        DllCall("DeleteDC", "ptr", hdcMem)
    }
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", w, bi, 4)
    NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    pBits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdcS, "ptr", bi, "uint", 0, "ptr*", &pBits, "ptr", 0, "uint", 0, "ptr")
    DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    capW := w, capH := h
    baseBuf := Buffer(w * h * 4)
    curBuf := Buffer(w * h * 4)
}

Grab(l, t, w, h) {
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    DllCall("BitBlt", "ptr", hdcMem, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", hdcS, "int", l, "int", t, "uint", 0x00CC0020)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    DllCall("RtlMoveMemory", "ptr", curBuf, "ptr", pBits, "uptr", w * h * 4)
}

SaveBaseline(w, h) {
    DllCall("RtlMoveMemory", "ptr", baseBuf, "ptr", curBuf, "uptr", w * h * 4)
}

; ---------- scan: find a NEW GUI (something that wasn't there before) ----------
FindNewGui(w, h, &ox, &oy) {
    step := Max(2, Num(eStep, 8))
    sens := Num(eSens, 90)
    minArea := Num(eMin, 12)
    bs := step * 8
    xs := [], ys := []
    counts := Map()
    y := 0
    while y < h {
        row := y * w
        x := 0
        while x < w {
            off := (row + x) * 4
            a := NumGet(baseBuf, off, "uint")
            c := NumGet(curBuf, off, "uint")
            if (a != c) {
                d := Abs((a & 255) - (c & 255)) + Abs(((a >> 8) & 255) - ((c >> 8) & 255)) + Abs(((a >> 16) & 255) - ((c >> 16) & 255))
                if (d > sens) {
                    xs.Push(x), ys.Push(y)
                    k := (x // bs) * 10000 + (y // bs)
                    counts[k] := counts.Get(k, 0) + 1
                }
            }
            x += step
        }
        y += step
    }
    if (xs.Length < minArea)
        return false

    ; densest cluster of changes = the new GUI (ignores scattered noise)
    bestK := 0, best := 0
    for k, cnt in counts {
        if (cnt > best)
            best := cnt, bestK := k
    }
    mx := bestK // 10000, my := Mod(bestK, 10000)
    sx := 0, sy := 0, total := 0
    i := 1
    while i <= xs.Length {
        if (Abs(xs[i] // bs - mx) <= 1 && Abs(ys[i] // bs - my) <= 1)
            sx += xs[i], sy += ys[i], total++
        i++
    }
    if (total < minArea)
        return false
    ox := sx // total, oy := sy // total
    return true
}

; ---------- shake: click it ----------
ClickAt(x, y) {
    MouseMove x, y, 0
    Sleep 15
    MouseMove x + 1, y + 1, 0
    MouseMove x, y, 0
    Sleep Num(eClick, 40)
    Click "Down"
    Sleep Num(eClickHold, 40)
    Click "Up"
}

MacroLoop() {
    global running
    while running {
        if WinExist("ahk_exe RobloxPlayerBeta.exe")
            WinActivate
        GetRegion(&wl, &wt, &ww, &wh)

        ; ===== Phase 1: Casting (hold left mouse button) =====
        SetPhase(1)
        MouseMove wl + ww // 2, wt + wh // 2, 0
        Click "Down"
        Sleep Num(eCastHold, 600)
        Click "Up"
        Sleep Num(ePostCast, 1500)
        if !running
            break

        ; ===== Phase 2: Shaking (scan area for a new GUI, click it) =====
        SetPhase(2)
        GetScanArea(&sl, &st, &sw, &sh, wl, wt, ww, wh)
        InitCapture(sw, sh)
        Grab(sl, st, sw, sh)
        SaveBaseline(sw, sh)
        lastSeen := A_TickCount
        timeout := Num(eTimeout, 8000)
        while running && (A_TickCount - lastSeen < timeout) {
            Grab(sl, st, sw, sh)
            if FindNewGui(sw, sh, &cx, &cy) {
                stText.Value := "Status: RUNNING   |   Phase 2: Shaking - new GUI at " (sl + cx) ", " (st + cy)
                lastSeen := A_TickCount
                ClickAt(sl + cx, st + cy)
                Sleep Num(eNextClick, 100)   ; delay before the next shake click
            } else {
                SaveBaseline(sw, sh)
            }
            Sleep Num(eScan, 30)
        }
        if !running
            break

        ; ===== Phase 3: Finished, restarting loop =====
        SetPhase(3)
        Sleep Num(eCycle, 2000)
    }
}
