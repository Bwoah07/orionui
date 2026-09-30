# Copies Stig's RaidControl into OrionUI/RaidControl (his own addon, free to reuse; see
# docs/raidcontrol-inventory.md). Leaves out notes and RaidControl's settings windows.
# Re-runnable: it rebuilds OrionUI/RaidControl from the installed RaidControl each time.
import os, re, shutil

SRC = "C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/Raidcontrol/"
DST = "C:/OrionUI/OrionUI/RaidControl/"
LIBS = "C:/OrionUI/OrionUI/Libs/"
B = chr(92)

KEEP = ["FrameScaling", "Workspace", "AutoMarker", "AutoInvite", "CombatLogger", "SynergyAnalyzer",
        "KeySync", "ConsumableChecker", "RaidLeadTools", "TankAssist", "TankAssistMidnight",
        "TankAssistAlertHUD", "TankAssistCountdownAudio", "Roles", "RaidSplit", "ActionStrip",
        "LayoutMode", "RaidDemo", "Control", "Screenshot", "MarkerBar", "AutoVendor",
        "ReadyTracker", "AutoAssist"]  # TOC order from Raidcontrol.toc, minus the dropped ones
DROPPED = ["BossNotes", "NoteReminders", "NSRTInterop", "OrionImport", "Settings", "SettingsV2/*", "BlizzardOptions"]

def transform(text, name):
    bs = B + B  # a Lua-escaped backslash as it appears in source: \\
    text = text.replace("Interface" + bs + "AddOns" + bs + "Raidcontrol" + bs,
                        "Interface" + bs + "AddOns" + bs + "OrionUI" + bs + "RaidControl" + bs)
    text = text.replace('"Interface' + bs + 'AddOns' + bs + '" .. addonName .. "' + bs + 'Media' + bs,
                        '"Interface' + bs + 'AddOns' + bs + '" .. addonName .. "' + bs + 'RaidControl' + bs + 'Media' + bs)
    text = text.replace('NewLocale("RaidControl"', 'NewLocale("OrionUIRaidControl"')
    text = text.replace('GetLocale("RaidControl")', 'GetLocale("OrionUIRaidControl")')
    text = text.replace('NewAddon("RaidControl"', 'NewAddon("OrionUIRaidControl"')
    text = text.replace('"RaidControlDB"', '"OrionUIRaidControlDB"')
    text = text.replace('_G.RaidControlDB', '_G.OrionUIRaidControlDB')
    # Every file but Core starts with `local RC = ns.RC`; stay silent when the standalone
    # RaidControl addon is enabled (Core then doesn't create ns.RC).
    text = re.sub(r"^(local RC = ns\.RC)\s*$", r"\1\nif not RC then return end -- standalone RaidControl is enabled",
                  text, count=1, flags=re.M)
    return text

def copy(rel, dst_rel=None):
    src = SRC + rel
    dst = DST + (dst_rel or rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if rel.endswith(".lua"):
        text = open(src, encoding="utf-8").read()
        open(dst, "w", encoding="utf-8", newline="\n").write(transform(text, rel))
    else:
        shutil.copyfile(src, dst)

# Since 2026-09-30 OrionUI/RaidControl is edited directly (the standalone addon is uninstalled);
# this script only documents how the copy was made. Never wipe the copy without a source.
if not os.path.exists(SRC + "Core.lua"):
    raise SystemExit("RaidControl source not installed; OrionUI/RaidControl is maintained in place now.")

if os.path.isdir(DST):
    for sub in ("Modules", "Locales", "Media"):
        shutil.rmtree(DST + sub, ignore_errors=True)
    for f in ("Core.lua",):
        if os.path.exists(DST + f): os.remove(DST + f)

copy("Core.lua")
for f in os.listdir(SRC + "Locales"):
    if f.endswith(".lua"): copy("Locales/" + f)
copy("Media/Media.lua")
for root, _, files in os.walk(SRC + "Media"):
    for f in files:
        rel = os.path.relpath(os.path.join(root, f), SRC).replace(B, "/")
        if rel != "Media/Media.lua" and not rel.endswith("settings-nav.png") and not rel.endswith(".png") or rel.endswith("role.png") or rel.endswith("icons.png") or rel.endswith("settings-shell.png") or rel.endswith("role icon.png"):
            if rel != "Media/Media.lua": copy(rel)
for m in KEEP:
    copy("Modules/%s.lua" % m)

# Libraries for local dev (release builds get them from .pkgmeta externals; Libs/ is gitignored).
for lib in ("Ace3", "LibSharedMedia-3.0"):
    if not os.path.isdir(LIBS + lib):
        shutil.copytree(SRC + "Libs/" + lib, LIBS + lib)
print("copied", len(KEEP), "modules; dropped:", ", ".join(DROPPED))


# ---- second pass ----
import os
DST = "C:/OrionUI/OrionUI/RaidControl/"

p = DST + "Core.lua"
s = open(p, encoding="utf-8").read()
old = 'local addonName, addonTable = ...\n'
new = '''local addonName, addonTable = ...
-- OrionUI's built-in copy of RaidControl (Stig's own addon). It stays off while the standalone
-- RaidControl addon is enabled for this character, so the two never fight over frames,
-- bindings and slash commands. Every other RaidControl file returns early when ns.RC is nil.
do
    local exists = C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("Raidcontrol")
    if exists and C_AddOns.GetAddOnEnableState("Raidcontrol", UnitName("player")) > 0 then
        return
    end
end
'''
assert s.startswith(old)
s = s.replace(old, new, 1)
# Version shown in RaidControl's UI: ours, not the standalone addon's.
s = s.replace('C_AddOns.GetAddOnMetadata("Raidcontrol", "Version")', 'C_AddOns.GetAddOnMetadata(addonName, "Version")')
open(p, "w", encoding="utf-8", newline="\n").write(s)

# Workspace: Raid Split used to be hosted inside RaidControl's settings window. That window is
# gone (OrionUI's /oui replaces it), so pages no longer require it.
p = DST + "Modules/Workspace.lua"
s = open(p, encoding="utf-8").read()
old = '''    if key ~= "settings" and self.host and not self:EnsureSettingsShell() then
        return false
    end
'''
assert old in s
s = s.replace(old, '''    -- OrionUI: no settings shell any more; pages open in the plain workspace host.
''', 1)
open(p, "w", encoding="utf-8", newline="\n").write(s)

f = DST + "Media/role icon.png"
if os.path.exists(f): os.remove(f)
print("ok")
