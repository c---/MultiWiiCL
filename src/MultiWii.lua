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

--[[
   Globals for this module:
      cache_      - Table of values. Cleared when port is closed
      config_     - Table of configuration values
      monitor_    - Length of last line when in monitor mode
      silent_     - Do not print output of commands by default
      serialPort_ - Serial port object
      commands_   - Table of all command functions
--]]

module("MultiWii", package.seeall)

local ffi = require'ffi'
local serial = require'luaserial'
local Config = require'Config'

local cache_ = {}

config_ = {
   port = nil,
   baud = 115200,
   noident = false,
   maxhistory = 100,
   rawmode = false,
}

MSP_IDENT = 100
MSP_STATUS = 101
MSP_RAW_IMU = 102
MSP_SERVO = 103
MSP_MOTOR = 104
MSP_RC = 105
MSP_RAW_GPS = 106
MSP_COMP_GPS = 107
MSP_ATTITUDE = 108
MSP_ALTITUDE = 109
MSP_ANALOG = 110
MSP_RC_TUNING = 111
MSP_PID = 112
MSP_BOX = 113
MSP_MISC = 114
MSP_MOTOR_PINS = 115
MSP_BOXNAMES = 116
MSP_PIDNAMES = 117
MSP_WP = 118
MSP_BOXIDS = 119
MSP_SERVO_CONF = 120

MSP_SET_RAW_RC = 200
MSP_SET_RAW_GPS = 201
MSP_SET_PID = 202
MSP_SET_BOX = 203
MSP_SET_RC_TUNING = 204
MSP_ACC_CALIBRATION = 205
MSP_MAG_CALIBRATION = 206
MSP_SET_MISC = 207
MSP_RESET_CONF = 208
MSP_SET_WP = 209
MSP_SELECT_SETTING = 210
MSP_SET_HEAD = 211
MSP_SET_SERVO_CONF = 212
MSP_SET_MOTOR = 214

MSP_USBLINKER = 239

MSP_BIND = 240

MSP_EEPROM_WRITE = 250

MSP_DEBUGMSG = 253
MSP_DEBUG = 254

-------------------------------------------------------------------------------

function parseUInt8(data, start)
   start = start or 1
   return data:byte(start)
end

function parseInt8(data, start)
   local rv = parseUInt8(data, start)
   if rv > 0x80 then rv = rv - 0x100 end
   return rv
end

function parseUInt16(data, start)
   start = start or 1
   return data:byte(start) +
      data:byte(1 + start) * 0x100
end

function parseInt16(data, start)
   local rv = parseUInt16(data, start)
   if rv > 0x8000 then rv = rv - 0x10000 end
   return rv
end

function parseUInt32(data, start)
   start = start or 1
   return data:byte(start) +
      data:byte(1 + start) * 0x100 +
      data:byte(2 + start) * 0x10000 +
      data:byte(3 + start) * 0x1000000
end

function parseInt32(data, start)
   local rv = parseUInt32(data, start)
   if rv > 0x80000000 then rv = rv - 0x100000000 end
   return rv
end

function writeUInt8(v)
   return string.char(bit.band(v, 0xFF))
end

function writeInt8(v)
   if v < 0 then v = v + 0x100 end
   return writeUInt8(v)
end

function writeUInt16(v)
   return string.char(bit.band(v, 0xFF),
      bit.band(bit.rshift(v, 8), 0xFF))
end

function writeInt16(v)
   if v < 0 then v = v + 0x10000 end
   return writeUInt16(v)
end

function writeUInt32(v)
   return string.char(bit.band(v, 0xFF),
      bit.band(bit.rshift(v, 8), 0xFF),
      bit.band(bit.rshift(v, 16), 0xFF),
      bit.band(bit.rshift(v, 24), 0xFF))
end

function writeInt32(v)
   if v < 0 then v = v + 0x100000000 end
   return writeUInt32(v)
end

function parseBinary(format, data, start)
   local pos = start or 1
   local rv = {}

   for i=1,#format do
      if format:sub(i, i) == '1' then
         table.insert(rv, data:byte(pos))
         pos = pos + 1
      elseif format:sub(i, i) == '2' then
         table.insert(rv, parseUInt16(data, pos))
         pos = pos + 2
      elseif format:sub(i, i) == '4' then
         table.insert(rv, parseUInt32(data, pos))
         pos = pos + 4
      elseif format:sub(i, i) == 'c' then
         table.insert(rv, parseInt8(data, pos))
         pos = pos + 1
      elseif format:sub(i, i) == 's' then
         table.insert(rv, parseInt16(data, pos))
         pos = pos + 2
      elseif format:sub(i, i) == 'i' then
         table.insert(rv, parseInt32(data, pos))
         pos = pos + 4
      end
   end

   return rv
end

function serialize(t, indent)
   indent = indent or 1
   if type(t) == 'table' then
      local rv = '{\n'
      for k,v in pairs(t) do
         if type(k) == 'number' then
            k = '['..k..']'
         else
            k = "['"..tostring(k):gsub("'", "\\'").."']"
         end

         rv = rv..string.rep('\t', indent)..k..'='..serialize(v, indent+1)..',\n'
      end
      return rv..string.rep('\t', indent-1)..'}'
   elseif type(t) == 'number' or type(t) == 'boolean' then
      return tostring(t)
   elseif type(t) == 'string' then
      return "'"..t:gsub("'", "\\'").."'"
   else
      error("can't serialize `"..type(t).."'")
   end
end

function deserialize(s)
   return assert(loadstring("return "..s))()
end

function printTable(t)
   if not t then return '{success}' end

   local temp = {}
   if #t > 0 then
      for k,v in ipairs(t) do
         if type(v) == 'table' then
            table.insert(temp, printTable(v))
         else
            table.insert(temp, v)
         end
      end
   else
      for k,v in pairs(t) do
         if type(v) == 'table' then
            table.insert(temp, k..'='..printTable(v))
         else
            if convert[t._type] and convert[t._type][k] and type(convert[t._type][k]) == 'function' then
               table.insert(temp, k..'='..convert[t._type][k](v))
            elseif convert[t._type] and convert[t._type][k] and convert[t._type][k][v] then
               table.insert(temp, k..'='..convert[t._type][k][v])
            elseif k ~= '_type' then
               table.insert(temp, k..'='..v)
            end
         end
      end
   end

   return "{"..table.concat(temp, ",").."}"
end

-------------------------------------------------------------------------------

function flush()
end

function findResponses(data)
   local rv = {}
   if not data then return rv end

   local pos = data:find("$M[!>]")
   while pos do
      local len = data:byte(pos + 3)
      local checksum = data:byte(pos + len + 5)
      local calcsum = 0
      for i=pos+3,pos+len+4 do
         calcsum = bit.bxor(calcsum, data:byte(i))
      end

      if calcsum == checksum then
         table.insert(rv, data:sub(pos + 2, pos + len + 4))
         data = data:sub(pos + len + 6)
      else
         data = data:sub(pos + 3)
      end

      pos = data:find("$M")
   end

   return rv
end

function sendCmd(cmd, data, nowait)
   if not serialPort_ then
      error("Serial port is not open")
   end

   data = data or ''
   local out = "$M<"..string.char(#data)..string.char(cmd)..data
   local sum = 0
   for i=4,#out do
      sum = bit.bxor(sum, out:byte(i))
   end

   serialPort_:write(out..string.char(sum))
   serialPort_:flush()

   if not nowait then
      serialPort_:setTimeout(1000, 1000)
      local data = serialPort_:read(1)

      serialPort_:setTimeout(10, 500)
      data = data..serialPort_:read(4096)

      data = findResponses(data)
   
      if #data == 0 then
         error("No response or invalid response")
      end
   
      return data[#data] -- FIXME: throw away all but last response
   end
end

function parseResponse(data)
   if data:sub(1, 1) == '!' then
      error("Command is unknown")
   end

   local cmd = data:byte(3)
   data = data:sub(4)
   local field
   if cmd == MSP_IDENT then
      field = parseBinary("1114", data)
      return {
         _type = 'MSP_IDENT',
         version = field[1],
         multitype = field[2],
         msp_version = field[3],
         capability = field[4],
      }
   elseif cmd == MSP_STATUS then
      field = parseBinary("22241", data)
      return {
         _type = 'MSP_STATUS',
         cycleTime = field[1],
         i2c_errors_count = field[2],
         flags = field[3],
         boxes = field[4],
         currentSet = field[5],
      }
   elseif cmd == MSP_RAW_IMU then
      field = parseBinary("sss sss sss", data)
      return {
         _type = 'MSP_RAW_IMU',
         accSmooth = { field[1], field[2], field[3] },
         gyroData = { field[4], field[5], field[6] },
         magADC = { field[7], field[8], field[9] },
      }
   elseif cmd == MSP_SERVO then
      field = parseBinary("22222222", data)
      local rv = { _type = 'MSP_SERVO' }
      for i=1,#field do table.insert(rv, field[i]) end
      return rv
   elseif cmd == MSP_SERVO_CONF then
      local rv = { _type = 'MSP_SERVO_CONF' }
      for i=1,56,7 do
         table.insert(rv, {
            min = parseInt16(data, i),
            max = parseInt16(data, i + 2),
            middle = parseInt16(data, i + 4),
            rate = parseInt8(data, i + 6),
         })
      end
      return rv
   elseif cmd == MSP_MOTOR then
      field = parseBinary("22222222", data)
      local rv = { _type = 'MSP_MOTOR' }
      for i=1,#field do table.insert(rv, field[i]) end
      return rv
   elseif cmd == MSP_RC then
      local rv = { _type = 'MSP_RC' }
      for i=1,#data,2 do
         table.insert(rv, parseUInt16(data, i))
      end
      return rv
   elseif cmd == MSP_RAW_GPS then
      field = parseBinary("11ii222", data)
      return {
         _type = 'MSP_RAW_GPS',
         fix = field[1],
         numSat = field[2],
         coordLAT = field[3],
         coordLON = field[4],
         altitude = field[5],
         speed = field[6],
         ground_course = field[7],
      }
   elseif cmd == MSP_COMP_GPS then
      field = parseBinary("2s1", data)
      return {
         _type = 'MSP_COMP_GPS',
         distanceToHome = field[1],
         directionToHome = field[2],
         update = field[3],
      }
   elseif cmd == MSP_ATTITUDE then
      field = parseBinary("ss ss", data)
      return {
         _type = 'MSP_ATTITUDE',
         angle = { field[1], field[2] },
         heading = field[3],
         headFreeModeHold = field[4],
      }
   elseif cmd == MSP_ALTITUDE then
      field = parseBinary("is", data)
      return {
         _type = 'MSP_ALTITUDE',
         EstAlt = field[1],
         vario = field[2],
      }
   elseif cmd == MSP_ANALOG then
      field = parseBinary("122", data)
      return {
         _type = 'MSP_ANALOG',
         vbat = field[1],
         intPowerMeterSum = field[2],
         rssi = field[3],
      }
   elseif cmd == MSP_RC_TUNING then
      field = parseBinary("1111111", data)
      return {
         _type = 'MSP_RC_TUNING',
         rcRate = field[1],
         rcExpo = field[2],
         rollPitchRate = field[3],
         yawRate = field[4],
         dynThrPID = field[5],
         thrMid = field[6],
         thrExpo = field[7],
      }
   elseif cmd == MSP_PID then
      local rv = { _type = 'MSP_PID' }
      for i=1,#data,3 do
         table.insert(rv, {
            P = data:byte(i),
            I = data:byte(i + 1),
            D = data:byte(i + 2)
         })
      end
      return rv
   elseif cmd == MSP_BOX then
      local rv = { _type = 'MSP_BOX' }
      for i=1,#data,2 do
         table.insert(rv, parseUInt16(data, i))
      end
      return rv
   elseif cmd == MSP_MISC then
      field = parseBinary("2", data)
      return {
         _type = 'MSP_MISC',
         intPowerTrigger1 = field[1],
      }
   elseif cmd == MSP_MOTOR_PINS then
      field = parseBinary("11111111", data)
      local rv = { _type = 'MSP_MOTOR_PINS' }
      for i=1,#field do table.insert(rv, field[i]) end
      return rv
   elseif cmd == MSP_BOXNAMES then
      local rv = { _type = 'MSP_BOXNAMES' }
      data:gsub("([^;]*);", function(m) table.insert(rv, m) end)
      return rv
   elseif cmd == MSP_PIDNAMES then
      local rv = { _type = 'MSP_PIDNAMES' }
      data:gsub("([^;]*);", function(m) table.insert(rv, m) end)
      return rv
   elseif cmd == MSP_WP then
      field = parseBinary("1ii21", data)
      return {
         _type = 'MSP_WP',
         wp = field[1],
         GPS_homeLAT = field[2],
         GPS_homeLON = field[3],
         altitude = field[4],
         nav = field[5],
      }
   elseif cmd == MSP_BOXIDS then
      field = { _type = 'MSP_BOXIDS' }
      for i=1,#data do table.insert(field, data:byte(i)) end
      return field
   elseif cmd == MSP_DEBUG then
      field = parseBinary("2222", data)
      field._type = 'MSP_DEBUG'
      return field
   elseif cmd == MSP_DEBUGMSG then
      return {
         _type = 'MSP_DEBUGMSG',
         msg = data,
      }
   end
end

function printResult(r)
   if not silent_ then
      local out = printTable(r)
   
      if monitor_ then
         io.stdout:write("\r"..string.rep(" ", monitor_).."\r")
         monitor_ = #out
         io.stdout:write(out)
      else
         io.stdout:write(out)
         io.stdout:write('\n')
      end
   
      io.stdout:flush()
   end
end

function getPIDNames()
   if not cache_.pidnames then
      cache_.pidnames = parseResponse(sendCmd(MSP_PIDNAMES))
   end
   return cache_.pidnames
end

function getBoxNames()
   if not cache_.boxnames then
      cache_.boxnames = parseResponse(sendCmd(MSP_BOXNAMES))
   end
   return cache_.boxnames
end

function getBoxIDs()
   if not cache_.boxids then
      cache_.boxids = parseResponse(sendCmd(MSP_BOXIDS))
   end
   return cache_.boxids
end

convert = {
   MSP_IDENT = {
      capability = function(v)
         local rv = {}
         if bit.band(v, 0x01) then table.insert(rv, 'BIND_CAPABLE') end
         return table.concat(rv, "|")
      end,
      multitype = {
         'TRI',
         'QUADP',
         'QUADX',
         'BI',
         'GIMBAL',
         'Y6',
         'HEX6',
         'FLYING_WING',
         'Y4',
         'HEX6X',
         'OCTOX8',
         'OCTOFLATP',
         'OCTOFLATX',
         'AIRPLANE|SINGLECOPTER|DUALCOPTER',
         'HELI_120_CCPM',
         'HELI_90_DEG',
         'VTAIL4',
         'HEX6H',
      },
   },
   MSP_STATUS = {
      flags = function(v)
         local rv = {}
         if bit.band(v, 0x01) then table.insert(rv, 'ACC') end
         if bit.band(v, 0x02) then table.insert(rv, 'BARO') end
         if bit.band(v, 0x04) then table.insert(rv, 'MAG') end
         if bit.band(v, 0x08) then table.insert(rv, 'GPS') end
         if bit.band(v, 0x10) then table.insert(rv, 'SONAR') end
         return table.concat(rv, "|")
      end,
      --[[
      boxes = function(v)
         local rv = {}
         for i=1,32 do
            table.insert(rv, bit.band(v, bit.lshift(1, i-1)))
         end
         return rv
      end,
      --]]
   },
}

-------------------------------------------------------------------------------

commands_ = {
   help = {
      function(cmd)
         if not cmd then
            print()
            print("Use help('COMMAND') to get help on specific commands")
            print()
            print("Begin with open('portname') to open serial port")
            print()
            print("Scripting language is based on LuaJIT  http://luajit.org")
            print()
            local t = {}
            for k,v in pairs(commands_) do table.insert(t, k) end
            table.sort(t)
            local pos = 0
            for k,v in ipairs(t) do
               if pos + #v + 2 > 79 then
                  print()
                  pos = 0
               end
               pos = pos + #v + 2
               if k < #t then
                  io.stdout:write(v, ', ')
               else
                  io.stdout:write(v, '\n\n')
               end
            end
            io.stdout:flush()
         elseif not commands_[cmd] or not (commands_[cmd][2] or commands_[cmd][3]) then
            print("No help available for command `"..cmd.."'")
         else
            if commands_[cmd][2] then
               print(string.rep('-', 79))
               print(commands_[cmd][2])
               print(string.rep('-', 79))
            end
            if commands_[cmd][3] then
               print(commands_[cmd][3])
            end
         end
      end,
      "help()\nhelp(cmd)",
      "Displays usage information."
   },

   monitor = {
      function(cmd, refresh)
         pcall(function()
            refresh = refresh or 1000
            monitor_ = 1
            while true do
               cmd()
               serial.sleep(refresh)
            end
         end)

         io.stdout:write("\n")
         monitor_ = nil
      end,
      "monitor(function, [refresh])",[[
Continuously executes a command and displays the results. `function' is a
function to run and `refresh' is an optional refresh interval in milliseconds
(default 1000). Note that this command does not work well with commands that
output multiple lines of data. Use CTRL-C to stop monitoring.

   Example:
      monitor(rawimu, 1000)
]]
   },

   open = {
      function(port, noident, baud)
         if not port then
            port = config_.port or error("No previously opened port")
         end

         if noident == nil then
            noident = config_.noident or false
         end

         if not baud then
            baud = config_.baud or 115200
         end

         close()
         serialPort_ = serial.new(port, baud)
         serialPort_:setTimeout(10, 500)

         config_.port = port
         config_.baud = baud
         config_.noident = noident

         Config.save(config_)

         if not noident then
            local ok, result
            for i=1,10 do
               ok, result = pcall(sendCmd, MSP_IDENT)
               if ok then result = parseResponse(result) end
               if not (ok and result and result.version) then
                  if i==10 then
                     close()
                     error("Ident failed")
                  end
                  flush()
                  serial.sleep(500)
                  flush()
               else
                  break
               end
            end

            version = result.version
   
            if version < 210 or version > 230 then
               print("WARNING: unsupported version of MultiWii detected")
            end
         end
      end,
      "open([port], [noident], [baud])",[[
Opens serial port with path `port'.  If `noident' is true then the MultiWii
MSP_IDENT command and version checking is skipped. `baud' parameter sets the
baud rate, if not specified then the default of 115200 bps is used.  open()
with no parameters will reopen the last opened port and baud.

Unix example:
   open("/dev/ttyUSB0")

Windows:
   open("COM7")
]]
   },

   close = {
      function()
         if serialPort_ then
            flush()
            serialPort_:close()
            serialPort_ = nil
         end

         monitor_ = nil
         cache_ = {}
      end,
      "close()",[[
Closes serial port
]]
   },

   flush = {
      function()
         if serialPort_ then
            serialPort_:flush()
            serialPort_:setTimeout(10, 500)
            serialPort_:read(4096)
         end
      end,
      "flush()",[[
Flush serial port data.
]]
   },

   ident = {
      function()
         local result = parseResponse(sendCmd(MSP_IDENT))
         printResult(result)
         return result
      end,
      "ident()",[[
MSP_IDENT command
]]
   },

   status = {
      function()
         local result = parseResponse(sendCmd(MSP_STATUS))
         printResult(result)
         return result
      end,
      "status()",[[
MSP_STATUS command
]]
   },

   rawimu = {
      function()
         local result = parseResponse(sendCmd(MSP_RAW_IMU))
         printResult(result)
         return result
      end,
      "rawimu()",[[
MSP_RAW_IMU command
]]
   },

   servo = {
      function()
         local result = parseResponse(sendCmd(MSP_SERVO))
         printResult(result)
         return result
      end,
      "servo()",[[
MSP_SERVO command
]]
   },

   servoconf = {
      function()
         local result = parseResponse(sendCmd(MSP_SERVO_CONF))
         printResult(result)
         return result
      end,
      "servoconf()",[[
MSP_SERVO_CONF command
]]
   },

   motor = {
      function()
         local result = parseResponse(sendCmd(MSP_MOTOR))
         printResult(result)
         return result
      end,
      "motor()",[[
MSP_MOTOR command
]]
   },

   rc = {
      function()
         local result = parseResponse(sendCmd(MSP_RC))
         printResult(result)
         return result
      end,
      "rc()",[[
MSP_RC command
]]
   },

   rawgps = {
      function()
         local result = parseResponse(sendCmd(MSP_RAW_GPS))
         printResult(result)
         return result
      end,
      "rawgps()",[[
MSP_RAW_GPS command
]]
   },

   compgps = {
      function()
         local result = parseResponse(sendCmd(MSP_COMP_GPS))
         printResult(result)
         return result
      end,
      "compgps()",[[
MSP_COMP_GPS command
]]
   },

   attitude = {
      function()
         local result = parseResponse(sendCmd(MSP_ATTITUDE))
         printResult(result)
         return result
      end,
      "attitude()",[[
MSP_ATTITUDE command
]]
   },

   altitude = {
      function()
         local result = parseResponse(sendCmd(MSP_ALTITUDE))
         printResult(result)
         return result
      end,
      "altitude()",[[
MSP_ALTITUDE command
]]
   },

   analog = {
      function()
         local result = parseResponse(sendCmd(MSP_ANALOG))
         result.vbat = result.vbat / 10
         printResult(result)
         return result
      end,
      "analog()",[[
MSP_ANALOG command
]]
   },

   rctuning = {
      function()
         local result = parseResponse(sendCmd(MSP_RC_TUNING))
         if not config_.rawmode then
            for k,v in pairs(result) do
               if k ~= '_type' then
                  result[k] = v / 100
               end
            end
         end
         printResult(result)
         return result
      end,
      "rctuning()",[[
MSP_RC_TUNING command
]]
   },

   pid = {
      function()
         local names = getPIDNames()
         local result = parseResponse(sendCmd(MSP_PID))
         for k,v in ipairs(result) do
            if not config_.rawmode then
               v.P = v.P / 10.0
               v.I = v.I / 1000.0
               print(string.format("%12s   P=%.1f, I=%.3f, D=%.3d", names[k], v.P, v.I, v.D))
            else
               print(string.format("%12s   P=%.3d, I=%.3d, D=%.3d", names[k], v.P, v.I, v.D))
            end
         end

         return result
      end,
      "result = pid()",[[
MSP_PID command
]]
   },

   box = {
      function()
         local names = getBoxNames()
         local result = parseResponse(sendCmd(MSP_BOX))
         print("               AUX1     AUX2     AUX3     AUX4")
         print("               L M H    L M H    L M H    L M H")
         for k,v in ipairs(result) do
            io.stdout:write(string.format("%12s", names[k]))
            for i=0,15 do
               if i % 3 == 0 then io.stdout:write("   ") end
      
               if bit.band(v, bit.lshift(1, i)) > 0 then
                  io.stdout:write("* ")
               else
                  io.stdout:write("- ")
               end
            end
            print()
         end

         return result
      end,
      "box()",[[
MSP_BOX command
]]
   },

   misc = {
      function()
         local result = parseResponse(sendCmd(MSP_MISC))
         printResult(result)
         return result
      end,
      "misc()",[[
MSP_MISC command
]]
   },

   motorpins = {
      function()
         local result = parseResponse(sendCmd(MSP_MOTOR_PINS))
         printResult(result)
         return result
      end,
      "motorpins()",[[
MSP_MOTOR_PINS command
]]
   },

   boxnames = {
      function()
         local result = parseResponse(sendCmd(MSP_BOXNAMES))
         BOXNAMES = result
         printResult(result)
         return result
      end,
      "boxnames()",[[
MSP_BOXNAMES command
]]
   },

   pidnames = {
      function()
         local result = parseResponse(sendCmd(MSP_PIDNAMES))
         PIDNAMES = result
         printResult(result)
         return result
      end,
      "pidnames()",[[
MSP_PIDNAMES command
]]
   },

   wp = {
      function()
         local result = parseResponse(sendCmd(MSP_WP))
         printResult(result)
         return result
      end,
      "wp()",[[
MSP_WP command
]]
   },

   boxids = {
      function()
         local result = parseResponse(sendCmd(MSP_BOXIDS))
         printResult(result)
         return result
      end,
      "boxids()",[[
MSP_BOXIDS command
]]
   },

   -- Set

   usblinker = {
      function(cmd, param1)
         if not cmd then
            serialPort_:setTimeout(250, 250)

            local ok, result
            for i=1,3 do
               sendCmd(MSP_USBLINKER, nil, true)
               serial.sleep(500)
               flush()
               serialPort_:write("$M<")
               result = serialPort_:read(64)
               local baud
               ok, baud = result:match("(P%d+:B%d+:R(%d+):PINS:)")
               if ok then
                  if baud == 0 then baud = 115200 end
                  config_.linkerbaud = tonumber(baud)
                  break
               end
            end
            if not ok then error("Failed `"..result.."'") end
            print("{"..result:sub(1, -2).."}")
         elseif config_.linkerbaud and config_.port then
            if cmd == 'read_eeprom' then
               if not param1 then error("need filename") end
               close()
               sleep(1000)
               os.execute("avrdude -c stk500v2 -b "..config_.linkerbaud.." -P "..config_.port.." -u -p m8 -U eeprom:r:"..param1..":i")
               open(nil, true)
            elseif cmd == 'read_flash' then
               if not param1 then error("need filename") end
               close()
               sleep(1000)
               os.execute("avrdude -c stk500v2 -b "..config_.linkerbaud.." -P "..config_.port.." -u -p m8 -U flash:r:"..param1..":i")
               open(nil, true)
            elseif cmd == 'write_flash' then
               if not param1 then error("need filename") end
               close()
               sleep(1000)
               os.execute("avrdude -c stk500v2 -b "..config_.linkerbaud.." -P "..config_.port.." -u -p m8 -U flash:w:"..param1..":i")
               open(nil, true)
            elseif cmd == 'write_eeprom' then
               if not param1 then error("need filename") end
               close()
               sleep(1000)
               os.execute("avrdude -c stk500v2 -b "..config_.linkerbaud.." -P "..config_.port.." -u -p m8 -U eeprom:w:"..param1..":i")
               open(nil, true)
            else
               flush()
               cmd = cmd:upper()
               serialPort_:write("$M<"..cmd)
               local result = serialPort_:read(64)
               local ok, pin, bitrate, baud = result:match("(P(%d+):B(%d+):R(%d+):PINS:)")
               if not ok then error("Response error") end
               baud = tonumber(baud)

               if cmd:sub(1,1) == 'P' then
                  if tonumber(pin) ~= tonumber(cmd:sub(2)) then error("Pin change failed") end
               elseif cmd:sub(1,1) == 'B' then
                  if tonumber(bitrate) ~= tonumber(cmd:sub(2)) then error("Bit rate change failed") end
               elseif cmd:sub(1,1) == 'R' then
                  if baud ~= tonumber(cmd:sub(2)) then error("Baud rate change failed") end
               else
                  error("Unknown command")
               end

               if baud == 0 then baud = 115200 end

               if baud ~= config_.linkerbaud then
                  close()
                  config_.baud = baud
                  open(config_.port, config_.baud)
               end
               config_.linkerbaud = baud
   
               print("{"..result:sub(1, -2).."}")
            end
         else
            error("Invalid serial state")
         end
      end,
      "usblinker()\nusblinker(cmd)",[[
Which no options this enables the Arduino USB Linker for flashing ESC.  If
`cmd' is supplied then it is sent.

Example:
   usblinker()     -- enable USB Linker mode
   usblinker("P1") -- select pin 1
]]
   },

   setrawrc = {
      function(channeldata)
         local out = {}
         for i=1,8 do
            if not channeldata[i] then error("Missing channel "..i.." data") end
            table.insert(out, writeUInt16(channeldata[i]))
         end
         
         local result = parseResponse(sendCmd(MSP_SET_RAW_RC, table.concat(out)))
         printResult(result)
      end,
      "setrawrc(channel_data)",[[
Manually sets raw RC data (emulating TX). `channeldata' should be an array of
eight 16-bit values.

Example:
   data = { 0, 0, 0, 0, 0, 0, 0, 0 }
   setrawrc(data)
]]
   },

   setrawgps = {
      function(data)
         local out = {}
         table.insert(out, string.char(data.FIX, data.numSat))
         table.insert(out, writeInt32(data.coordLAT))
         table.insert(out, writeInt32(data.coordLON))
         table.insert(out, writeUInt16(data.altitude))
         table.insert(out, writeUInt16(data.speed))

         local result = parseResponse(sendCmd(MSP_SET_RAW_GPS, table.concat(out)))
         printResult(result)
      end,
      "setrawgps(data)",[[
Manually sets raw GPS data. `data` is a table with numSat, coordLAT, coordLON, altitude, speed
]]
   },

   setpid = {
      function(data, v)
         local out = {}

         if type(data) == 'string' then
            local names = getPIDNames()
            for k,v in ipairs(names) do
               if v == data then data = k end
            end

            if type(data) == 'string' then
               error("Invalid PID name `"..data.."'")
            end

            local result = parseResponse(sendCmd(MSP_PID))
            if config_.rawmode then
               if v.P then result[data].P = v.P end
               if v.I then result[data].I = v.I end
            else
               if v.P then result[data].P = v.P * 10 end
               if v.I then result[data].I = v.I * 1000 end
            end
            if v.D then result[data].D = v.D end

            for k,v in ipairs(result) do table.insert(out, string.char(v.P, v.I, v.D)) end
         else
            if config_.rawmode then
               for k,v in ipairs(data) do table.insert(out, string.char(v.P, v.I, v.D)) end
            else
               for k,v in ipairs(data) do table.insert(out, string.char(v.P * 10, v.I * 1000, v.D)) end
            end
         end 

         local result = parseResponse(sendCmd(MSP_SET_PID, table.concat(out)))
         printResult(result)
      end,
      "setpid(data)\nsetpid(name, pid)",[[
Set PID values. There are two modes.  In the first mode `data' is an array with
PIDNAMES number entries, each with P, I, and D values. In the second you can
pass the name of the row followed by a PID value.

First mode example:
   data = {}
   data[1] = { P=4.0, I=0.030, D=23 }
   data[2] = { P=4.0, I=0.030, D=23 }
   ...
   setpid(data)

Use pid() to get the number of needed entries

Second mode example:
   setpid('ROLL', {P=4.0,I=0.030,D=23}) -- P, I, and D values set
   setpid('PITCH', {I=0.030})           -- Only I value set
]]
   },

   setbox = {
      function(data, aux, set)
         if type(data) == 'string' then
            local names = getBoxNames()
            for k,v in ipairs(names) do
               if v == data then data = k end
            end

            if type(data) == 'string' then
               error("Invalid box name `"..data.."'")
            end

            local result = parseResponse(sendCmd(MSP_BOX))

            if set then
               if set:sub(1,1) == '*' then
                  result[data] = bit.bor(result[data], bit.lshift(1, (aux-1) * 3))
               else
                  result[data] = bit.band(result[data], bit.bnot(bit.lshift(1, (aux-1) * 3)))
               end
               if set:sub(2,2) == '*' then
                  result[data] = bit.bor(result[data], bit.lshift(2, (aux-1) * 3))
               else
                  result[data] = bit.band(result[data], bit.bnot(bit.lshift(2, (aux-1) * 3)))
               end
               if set:sub(3,3) == '*' then
                  result[data] = bit.bor(result[data], bit.lshift(4, (aux-1) * 3))
               else
                  result[data] = bit.band(result[data], bit.bnot(bit.lshift(4, (aux-1) * 3)))
               end
            else
               result[data] = aux
            end

            data = result
         end

         local out = {}
         for k,v in ipairs(data) do
            table.insert(out, writeUInt16(v))
         end

         local result = parseResponse(sendCmd(MSP_SET_BOX, table.concat(out)))
         printResult(result)
      end,
      "setbox(data)\nsetbox(name, column, flags)\nsetbox(name, value)",[[
Sets activation boxes. There are three modes.  In the first mode `data' is an
array with BOXNAMES number of entries, each with a 16-bit value representing
the flags. The second mode you can pass the name of the row, the number of the
major column, and the flags specified as a string with '-' as off and '*' as
on. The third modes lets you specify a name and a raw integer value.

Example:
   setbox('BARO', 2, '-*-')  -- This sets the BARO row, AUX2, flags to 0 1 0
]]
   },

   setrctuning = {
      function(data)
         local out = {}
         if not config_.rawmode then
            table.insert(out, string.char(
               data.rcRate * 100,
               data.rcExpo * 100,
               data.rollPitchRate * 100,
               data.yawRate * 100,
               data.dynThrPID * 100,
               data.thrMid * 100,
               data.thrExpo * 100))
         else
            table.insert(out, string.char(
               data.rcRate,
               data.rcExpo,
               data.rollPitchRate,
               data.yawRate,
               data.dynThrPID,
               data.thrMid,
               data.thrExpo))
         end

         local result = parseResponse(sendCmd(MSP_SET_RC_TUNING, table.concat(out)))
         printResult(result)
      end,
      "setrctuning(data)",[[
Sets RC tuning values. `data` is a table with entries rcRate, rcExpo,
rollPitchRate, yawRate, dynThrPID, thrMid, thrExpo.
]]
   },

   acccalibration = {
      function()
         local result = parseResponse(sendCmd(MSP_ACC_CALIBRATION))
         printResult(result)
      end,
      "acccalibration()",[[
Perform accelerometer calibration
]]
   },

   magcalibration = {
      function()
         local result = parseResponse(sendCmd(MSP_MAG_CALIBRATION))
         printResult(result)
      end,
      "magcalibration()",[[
Perform magnetometer calibration
]]
   },

   setmisc = {
      function(powerTrigger)
         local out = {}
         table.insert(out, writeUInt16(powerTrigger))

         local result = parseResponse(sendCmd(MSP_SET_MISC, table.concat(out)))
         printResult(result)
      end,
      "setmisc(powerTrigger)",[[
`powerTrigger' is a 16-bit integer
]]
   },

   resetconf = {
      function()
         local result = parseResponse(sendCmd(MSP_RESET_CONF))
         printResult(result)
      end,
      "resetconf()",[[
Reset all configuration data to default values
]]
   },

   setwp = {
      function(data)
         local out = {}
         table.insert(out, string.char(data.no))
         if data.no == 0 then
            table.insert(out, writeUInt32(data.homeLAT))
            table.insert(out, writeUInt32(data.homeLON))
            table.insert(out, writeUInt32(0)) -- future: to set altitude
            table.insert(out, string.char(0))  -- future: to set nav flag
         end

         local result = parseResponse(sendCmd(MSP_SET_WP, table.concat(out)))
         printResult(result)
      end,
      "setwp(data)",[[
`data' is a table with entries 'no' (must be 0), 'homeLAT', 'homeLON'
]]
   },

   selectsetting = {
      function(setting)
         local out = {}
         table.insert(out, string.char(setting))

         local result = parseResponse(sendCmd(MSP_SELECT_SETTING, table.concat(out)))
         printResult(result)
      end,
      "selectsetting(config_number)",[[
Select configuration number `config_number'.  Number can be 0, 1, or 2.
]]
   },

   sethead = {
      function(magHold)
         local out = {}
         table.insert(out, writeUInt16(magHold))

         local result = parseResponse(sendCmd(MSP_SET_HEAD, table.concat(out)))
         printResult(result)
      end,
      "sethead(magHold)",[[
MSP_SET_HEAD
]]
   },

   setservoconf = {
      function(data)
         local out = {}
         for i=1,8 do
            if not data[i] then error("Missing #"..i.." entry") end
            if not data[i].min then error("Missing #"..i.." min value") end
            if not data[i].max then error("Missing #"..i.." max value") end
            if not data[i].middle then error("Missing #"..i.." middle value") end
            if not data[i].rate then error("Missing #"..i.." rate value") end
            table.insert(out, writeInt16(data[i].min))
            table.insert(out, writeInt16(data[i].max))
            table.insert(out, writeInt16(data[i].middle))
            table.insert(out, writeInt8(data[i].rate))
         end

         local result = parseResponse(sendCmd(MSP_SET_SERVO_CONF, table.concat(out)))
         printResult(result)
      end,
      "setservoconf(data)",[[
MSP_SET_SERVO_CONF
`data' should be an array with 8 entries consisting of min, max, middle,
and rate values. Same format as returned from the servoconf() command.

Example:
   data = {
      { min = 0, max = 0, middle = 0, rate = 0 },
      { min = 0, max = 0, middle = 0, rate = 0 },
      { min = 0, max = 0, middle = 0, rate = 0 },
      { min = 0, max = 0, middle = 0, rate = 0 },
      { min = 0, max = 0, middle = 0, rate = 0 },
      { min = 0, max = 0, middle = 0, rate = 0 },
      { min = 0, max = 0, middle = 0, rate = 0 },
      { min = 0, max = 0, middle = 0, rate = 0 },
   }
   setservoconf(data)
]]
   },

   setmotor = {
      function(data)
         local out = {}
         for i=1,8 do
            if not data[i] then error("Missing motor "..i.." data") end
            table.insert(out, writeInt16(data[i]))
         end
         
         local result = parseResponse(sendCmd(MSP_SET_MOTOR, table.concat(out)))
         printResult(result)
      end,
      "setmotor(motor_data)",[[
MSP_SET_MOTOR
`motor_data' should be an array of eight 16-bit values.

Example:
   data = { 0, 0, 0, 0, 0, 0, 0, 0 }
   setmotor(data)
]]
   },

   bind = {
      function()
         local result = parseResponse(sendCmd(MSP_BIND))
         printResult(result)
      end,
      "bind()",[[
MSP_BIND command
]]
   },


   eepromwrite = {
      function()
         local result = parseResponse(sendCmd(MSP_EEPROM_WRITE))
         printResult(result)
      end,
      "eepromwrite()",[[
Save all settings to EEPROM
]]
   },


   debugmsg = {
      function()
         local result = parseResponse(sendCmd(MSP_DEBUGMSG))
         printResult(result)
      end,
      "debugmsg()",[[
MSP_DEBUGMSG command
]]
   },

   mwdebug = {
      function()
         local result = parseResponse(sendCmd(MSP_DEBUG))
         printResult(result)
      end,
      "debug()",[[
MSP_DEBUG command
]]
   },

   savesettings = {
      function(filename)
         local pid = parseResponse(sendCmd(MSP_PID))
         local box = parseResponse(sendCmd(MSP_BOX))
         local tune = parseResponse(sendCmd(MSP_RC_TUNING))
         tune._type = nil
         local data = {pid={},box={},tune=tune}
         local names = getPIDNames()
         for k,v in ipairs(pid) do data.pid[names[k]] = v end
         names = getBoxNames()
         for k,v in ipairs(box) do data.box[names[k]] = v end

         local fp = io.open(filename, "wb")
         fp:write(serialize(data))
         fp:close()
         print("{success}")
      end,
      "savesettings(filename)",[[
Saves the current settings to a file.
]]
   },

   loadsettings = {
      function(filename)
         local data = deserialize(io.open(filename, "rb"):read("*a"))
         local oldrawmode = config_.rawmode
         config_.rawmode = true

         if data.pid then
            for k,v in pairs(data.pid) do commands_.setpid[1](k, v) end
         end
         if data.box then
            for k,v in pairs(data.box) do commands_.setbox[1](k, v) end
         end
         if data.tune then
            commands_.setrctuning[1](data.tune)
         end

         config_.rawmode = oldrawmode
      end,
      "loadsettings(filename)",[[
Loads the current settings from a file.
]]
   },

   cmd = {
      function(cmd)
         local result = parseResponse(sendCmd(cmd))
         return result
      end,
      "cmd(cmd)\ncmd(cmd, data)",[[
Sends a raw command to MultiWii and returns the result. Does not print anything
on screen. If `data' is provided then it is sent in the data portion of the
MultiWii command.

Example:
   names = cmd(MultiWii.MSP_BOXNAMES)
]]
   },

   sleep = {
      function(milliseconds)
         serial.sleep(milliseconds)
      end,
      "sleep(milliseconds)",[[
Sleeps for specified milliseconds.
]]
   },

   quit = {
      function()
         Prompt.systemExit_ = true
         if ffi.os == 'Windows' then os.exit(0) end
      end,
      "quit()",[[
Exits the program.
]]
   }
}

-- Copy all commands to global space
for k,v in pairs(commands_) do
   _G[k] = v[1]
end

-- Read config
config_ = Config.read() or config_

