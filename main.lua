-- main.lua — Simple UI
-- Plugin entry point. Registers the plugin and delegates to specialised modules.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")
local logger          = require("logger")

-- i18n MUST be installed before any other plugin module is require()'d.
-- All modules capture local _ = require("gettext") at load time — if we
-- replace package.loaded["gettext"] here, every subsequent require("gettext")
-- in this plugin receives our wrapper automatically.
local I18n = require("i18n")
I18n.install()

local Config    = require("config")
local UI        = require("ui")
local Bottombar = require("bottombar")
local Topbar    = require("topbar")
local Patches   = require("patches")

local SimpleUIPlugin = WidgetContainer:new{
    name = "simpleui",

    active_action             = nil,
    _rebuild_scheduled        = false,
    _topbar_timer             = nil,
    _power_dialog             = nil,

    _orig_uimanager_show      = nil,
    _orig_uimanager_close     = nil,
    _orig_booklist_new        = nil,
    _orig_menu_new            = nil,
    _orig_menu_init           = nil,
    _orig_fmcoll_show         = nil,
    _orig_rc_remove           = nil,
    _orig_rc_rename           = nil,
    _orig_fc_init             = nil,
    _orig_fm_setup            = nil,

    _makeNavbarMenu           = nil,
    _makeTopbarMenu           = nil,
    _makeQuickActionsMenu     = nil,
    _goalTapCallback          = nil,
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function SimpleUIPlugin:init()
    local ok, err = pcall(function()
        Config.applyFirstRunDefaults()
        Config.migrateOldCustomSlots()
        Config.sanitizeQASlots()  -- remove orphaned custom QA ids from all slots
        self.ui.menu:registerToMainMenu(self)
        if G_reader_settings:nilOrTrue("simpleui_enabled") then
            Patches.installAll(self)
            if G_reader_settings:nilOrTrue("navbar_topbar_enabled") then
                Topbar.scheduleRefresh(self, 0)
            end
            -- Pre-load desktop modules during boot idle time so the first
            -- Homescreen open has no perceptible freeze. scheduleIn(2) runs
            -- after the FileManager UI is fully painted and stable.
            UIManager:scheduleIn(2, function()
                pcall(require, "desktop_modules/moduleregistry")
            end)
        end
    end)
    if not ok then logger.err("simpleui: init failed:", tostring(err)) end
end

function SimpleUIPlugin:onTeardown()
    if self._topbar_timer then
        UIManager:unschedule(self._topbar_timer)
        self._topbar_timer = nil
    end
    Patches.teardownAll(self)
    I18n.uninstall()
end

-- ---------------------------------------------------------------------------
-- System events
-- ---------------------------------------------------------------------------

function SimpleUIPlugin:onScreenResize()
    UI.invalidateDimCache()
    UIManager:scheduleIn(0.2, function()
        self:_rewrapAllWidgets()
        self:_refreshCurrentView()
    end)
end

function SimpleUIPlugin:onNetworkConnected()
    Bottombar.refreshWifiIcon(self)
end

function SimpleUIPlugin:onNetworkDisconnected()
    Bottombar.refreshWifiIcon(self)
end

function SimpleUIPlugin:onSuspend()
    if self._topbar_timer then
        UIManager:unschedule(self._topbar_timer)
        self._topbar_timer = nil
    end
end

function SimpleUIPlugin:onResume()
    if G_reader_settings:nilOrTrue("navbar_topbar_enabled") then
        Topbar.scheduleRefresh(self, 0)
    end
    local RUI = package.loaded["apps/reader/readerui"]
    local reader_active = RUI and RUI.instance
    -- Outside the reader: invalidate stat caches and restore the Homescreen.
    if not reader_active then
        local ok_rg, RG = pcall(require, "desktop_modules/module_reading_goals")
        if ok_rg and RG and RG.invalidateCache then RG.invalidateCache() end
        local ok_rs, RS = pcall(require, "desktop_modules/module_reading_stats")
        if ok_rs and RS and RS.invalidateCache then RS.invalidateCache() end
        -- If the Homescreen is already visible, force a rebuild so the freshly
        -- invalidated stats are reflected immediately (e.g. after marking a book
        -- as read inside the reader and returning here).
        -- If it's not visible, showHSAfterResume will open it and onShow will
        -- run _buildContent from scratch anyway.
        local HS = package.loaded["homescreen"]
        if HS and HS._instance then
            HS.refresh(false)
        end
        -- Re-open the Homescreen on wakeup when "Start with Homescreen" is set.
        if G_reader_settings:nilOrTrue("simpleui_enabled") then
            Patches.showHSAfterResume(self)
        end
    end
end

function SimpleUIPlugin:onFrontlightStateChanged()
    if not G_reader_settings:nilOrTrue("navbar_topbar_enabled") then return end
    Topbar.scheduleRefresh(self, 0)
end

-- ---------------------------------------------------------------------------
-- Topbar delegation
-- ---------------------------------------------------------------------------

function SimpleUIPlugin:_registerTouchZones(fm_self)
    Bottombar.registerTouchZones(self, fm_self)
    Topbar.registerTouchZones(self, fm_self)
end

function SimpleUIPlugin:_scheduleTopbarRefresh(delay)
    Topbar.scheduleRefresh(self, delay)
end

function SimpleUIPlugin:_refreshTopbar()
    Topbar.refresh(self)
end

-- ---------------------------------------------------------------------------
-- Bottombar delegation
-- ---------------------------------------------------------------------------

function SimpleUIPlugin:_onTabTap(action_id, fm_self)
    Bottombar.onTabTap(self, action_id, fm_self)
end

function SimpleUIPlugin:_navigate(action_id, fm_self, tabs, force)
    Bottombar.navigate(self, action_id, fm_self, tabs, force)
end

function SimpleUIPlugin:_refreshCurrentView()
    local tabs      = Config.loadTabConfig()
    local action_id = self.active_action or tabs[1] or "home"
    self:_navigate(action_id, self.ui, tabs)
end

function SimpleUIPlugin:_rebuildAllNavbars()
    Bottombar.rebuildAllNavbars(self)
end

function SimpleUIPlugin:_rewrapAllWidgets()
    Bottombar.rewrapAllWidgets(self)
end

function SimpleUIPlugin:_restoreTabInFM(tabs, prev_action)
    Bottombar.restoreTabInFM(self, tabs, prev_action)
end

function SimpleUIPlugin:_setPowerTabActive(active, prev_action)
    Bottombar.setPowerTabActive(self, active, prev_action)
end

function SimpleUIPlugin:_showPowerDialog(fm_self)
    Bottombar.showPowerDialog(self, fm_self)
end

function SimpleUIPlugin:_doWifiToggle()
    Bottombar.doWifiToggle(self)
end

function SimpleUIPlugin:_doRotateScreen()
    Bottombar.doRotateScreen()
end

function SimpleUIPlugin:_showFrontlightDialog()
    Bottombar.showFrontlightDialog()
end

function SimpleUIPlugin:_scheduleRebuild()
    if self._rebuild_scheduled then return end
    self._rebuild_scheduled = true
    UIManager:scheduleIn(0.1, function()
        self._rebuild_scheduled = false
        self:_rebuildAllNavbars()
    end)
end

function SimpleUIPlugin:_updateFMHomeIcon() end

-- ---------------------------------------------------------------------------
-- Main menu entry (menu.lua is lazy-loaded on first access)
-- ---------------------------------------------------------------------------

-- Derive the absolute path to menu.lua from this file's own source path.
-- This is the same technique used by config.lua for icon paths and is robust
-- across all platforms (Kindle, Kobo, Android) regardless of working directory.
-- Using dofile() instead of require() sidesteps two problems:
--   1. require("menu") collides with KOReader's own ui/menu module, which is
--      already registered in package.loaded["menu"] as a table — calling it
--      as a function produces "attempt to call a table value".
--   2. require("plugins/simpleui.koplugin/menu") depends on package.path and
--      the process working directory, which are not guaranteed on all devices.
local _plugin_dir = debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"
local _menu_path  = _plugin_dir .. "menu.lua"

local menu_module_loaded = false

function SimpleUIPlugin:addToMainMenu(menu_items)
    if not menu_module_loaded then
        menu_module_loaded = true
        -- Capture the stub reference NOW, before the installer overwrites it.
        -- The installer sets SimpleUIPlugin.addToMainMenu = new_fn (rawset on the
        -- class), so after dofile() both rawget(SimpleUIPlugin, ...) and
        -- self.addToMainMenu resolve to the same new function — comparing them
        -- would always be equal and the menu would never open.
        -- Comparing against the stub captured here is the correct check.
        local stub_fn = rawget(SimpleUIPlugin, "addToMainMenu")
        -- dofile() always re-executes the file (no package.loaded cache),
        -- so retries after a failed load work automatically.
        local ok, result = pcall(function()
            local installer = dofile(_menu_path)
            installer(SimpleUIPlugin)
        end)
        if not ok then
            menu_module_loaded = false
            logger.err("simpleui: menu.lua failed to load: " .. tostring(result))
            menu_items.simpleui = { sorting_hint = "tools", text = "Simple UI", sub_item_table = {} }
            return
        end
        -- Verify the installer actually replaced addToMainMenu by comparing
        -- the new raw slot against the stub we captured before the dofile.
        local real_fn = rawget(SimpleUIPlugin, "addToMainMenu")
        if type(real_fn) == "function" and real_fn ~= stub_fn then
            real_fn(self, menu_items)
        else
            menu_module_loaded = false
            logger.err("simpleui: menu installer did not replace addToMainMenu — opening menu aborted")
            menu_items.simpleui = { sorting_hint = "tools", text = "Simple UI", sub_item_table = {} }
        end
        return
    end
end

return SimpleUIPlugin