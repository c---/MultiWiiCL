--[[
    Copyright (C) 2013 Chris Osgood

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, version 3 of the License.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]

module("Config", package.seeall)

local function getPath()
   if jit.os ~= 'Windows' then
      return os.getenv("HOME")
   else
      local path = os.getenv("USERPROFILE").."\\Application Data\\MultiWiiCL"
      os.execute('IF NOT EXIST "'..path..'" MD "'..path..'"')
      return path
   end
end

function getHistoryPath()
   if jit.os ~= 'Windows' then
      return getPath().."/.multiwiicl_history"
   else
      return getPath().."/history"
   end
end

function getConfigPath()
   if jit.os ~= 'Windows' then
      return getPath().."/.multiwiiclrc"
   else
      return getPath().."/config"
   end
end

function read()
   local fp = io.open(getConfigPath(), "rb")
   if fp then
      local ok, config = pcall(MultiWii.deserialize, fp:read("*a"))
      if ok then return config end
   end
end

function save(config)
   local fp = io.open(getConfigPath(), "wb")
   fp:write(MultiWii.serialize(config))
   fp:close()
end

