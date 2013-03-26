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

local infile, name = ...

local data = io.open(infile):read("*a")

io.stdout:write("static unsigned char "..name.."[] = {\n")
   
local lnsize = 0
   
for i=1, #data, 1 do
   local num = ""..data:byte(i)
   lnsize = lnsize + #num
   if i ~= #data then
      io.stdout:write(num..",")
      lnsize = lnsize + 1
   else
      io.stdout:write(num)
   end

   if lnsize > 75 then io.stdout:write("\n"); lnsize = 0 end
end

io.stdout:write(",0};\n")

