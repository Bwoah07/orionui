# OrionUI public API

Global `OrionUIAPI`, available after OrionUI has loaded. Version `OrionUIAPI.version` (currently 1)
is bumped on any breaking change. Calls that change settings refuse during combat and return
`false, "combat"`.

Stores are `"layout"` (look, positions, feature toggles) and `"reminders"` (encounter reminders,
defensive choices). They are separate on purpose: importing a new look never touches reminders.

| Call | Returns | Notes |
|---|---|---|
| `OrionUIAPI.OpenConfig(page)` | nothing | `page` is a module name (e.g. `"CombatAlert"`) or `"profiles"`; omit for the last page. |
| `OrionUIAPI.ImportProfile(store, str, name, opts)` | `ok, report` or `false, reason` | Validates the string, backs up the store, then writes profile `name`. `opts.overwrite` replaces an existing profile of that name; `opts.activate` switches the current character to it. `report` has `fixed`, `dropped`, `errors`, `modules`, `name`. |
| `OrionUIAPI.ExportProfile(store, name)` | `string` or `nil, reason` | Exports `name` (default: the active profile). Caches are never exported. |
| `OrionUIAPI.GetProfiles(store)` | `names, activeName` | Sorted list of profile names. |
| `OrionUIAPI.SetProfile(store, name)` | `ok` or `false, reason` | Switches the current character. |

## String format

`!OUI:<kind>:<version>!` followed by printable, deflated LibSerialize data. `kind` is `L` (layout),
`R` (reminders) or `C` (single custom reminder/preset, later). `version` is the wire format
version, currently 1.

## Addon compartment

The minimap addon menu entry opens the options window (`OrionUI_OnAddonCompartmentClick`).
