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

module("Prompt", package.seeall)

print('MultiWii Command Line '..MULTIWIICL_VERSION..'  Copyright (C) 2013 Chris Osgood')
print('Type help() to get started')

function runPrompt()
   local L = require 'linenoise'
   local history = Config.getHistoryPath()

   L.historysetmaxlen(MultiWii.config_.maxhistory or 100)
   L.historyload(history)

   L.setcompletion(function(c, line)
      for k,v in pairs(MultiWii.commands_) do
         if k:match("^"..line) then
            L.addcompletion(c, k.."()")
         end
      end
   end)

   local prompt = '> '
   local line = L.linenoise(prompt)
   while not systemExit_ and line do
      if #line > 0 then
         L.historyadd(line)
         L.historysave(history)
         local ok, msg = loadstring(line)
         if ok then ok, msg = pcall(ok) end
         if not ok then
            if msg then print(msg) end
            --print(debug.traceback())
         end
      end
      if systemExit_ then break end
      line = L.linenoise(prompt)
   end
end

while not systemExit_ do
   local ok, msg = pcall(runPrompt)
   --if not ok then print(msg) end
end

