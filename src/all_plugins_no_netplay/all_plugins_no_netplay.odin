package all_plugins_no_netplay

// Every code plugin except netplay, for the web build: static linking without
// runtime library loading, and UDP sockets don't work in browsers.
//
// Netplay is excluded by not importing it. The game sees exactly which plugins
// are registered (sim.registered_plugins), so the web build offers what it has.

import _ "dr:plugins/accent"
import _ "dr:plugins/accent/view"
import _ "dr:plugins/chaingun"
import _ "dr:plugins/chaingun/view"
import _ "dr:plugins/easy_mode"
import _ "dr:plugins/easy_mode/view"
import _ "dr:plugins/extra_prefs"
import _ "dr:plugins/extra_prefs/view"
import _ "dr:plugins/fps_unlock"
import _ "dr:plugins/fps_unlock/view"
import _ "dr:plugins/hitstop"
import _ "dr:plugins/hitstop/view"
import _ "dr:plugins/lighting"
import _ "dr:plugins/lighting/view"
import _ "dr:plugins/loadout"
import _ "dr:plugins/loadout/view"
import _ "dr:plugins/new_weapon_passives"
import _ "dr:plugins/new_weapon_passives/view"
import _ "dr:plugins/new_weapons"
import _ "dr:plugins/new_weapons/view"
import _ "dr:plugins/passives"
import _ "dr:plugins/passives/view"
import _ "dr:plugins/water"
import _ "dr:plugins/water/view"
import _ "dr:plugins/wind"
import _ "dr:plugins/wind/view"
