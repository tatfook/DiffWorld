--[[
Title: Diff World Mod
Author(s):  Big
Date: 2021.08.09
Desc: 
use the lib:
------------------------------------------------------------
NPL.load('(gl)Mod/DiffWorld/main.lua')
local DiffWorld = commonlib.gettable('Mod.DiffWorld')
------------------------------------------------------------

CODE GUIDELINE

1. all classes and functions use upper camel case.
2. all variables use lower camel case.
3. all files use use upper camel case.
4. all templates variables and functions use underscore case.
5. single quotation marks are used for strings.

]]

local DiffWorld = commonlib.inherit(commonlib.gettable('Mod.ModBase'), commonlib.gettable('Mod.DiffWorld'))

DiffWorld:Property({'Name', 'DiffWorld', 'GetName', 'SetName', { auto = true }})
DiffWorld:Property({'Desc', 'Compare with the previous worlds to find out differents.', 'GetDesc', 'SetDesc', { auto = true }})
DiffWorld.version = '0.0.1'

LOG.std(nil, 'info', 'DiffWorld', 'Diff world mod version: %s', DiffWorld.version)

function DiffWorld:init()
    echo('from diff world init!!!!', true)
end

function DiffWorld:OnWorldLoad()

end

