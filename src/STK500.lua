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

module("STK500", package.seeall)

-- STK message constants
MESSAGE_START = '\x1B'
MESSAGE_TOKEN = '\x0E'

-- STK general command constants
CMD_SIGN_ON = '\x01'
CMD_SET_PARAMETER = '\x02'
CMD_GET_PARAMETER = '\x03'
CMD_SET_DEVICE_PARAMETERS = '\x04'
CMD_OSCCAL = '\x05'
CMD_LOAD_ADDRESS = '\x06'
CMD_FIRMWARE_UPGRADE = '\x07'


-- STK ISP command constants
CMD_ENTER_PROGMODE_ISP = '\x10'
CMD_LEAVE_PROGMODE_ISP = '\x11'
CMD_CHIP_ERASE_ISP = '\x12'
CMD_PROGRAM_FLASH_ISP = '\x13'
CMD_READ_FLASH_ISP = '\x14'
CMD_PROGRAM_EEPROM_ISP = '\x15'
CMD_READ_EEPROM_ISP = '\x16'
CMD_PROGRAM_FUSE_ISP = '\x17'
CMD_READ_FUSE_ISP = '\x18'
CMD_PROGRAM_LOCK_ISP = '\x19'
CMD_READ_LOCK_ISP = '\x1A'
CMD_READ_SIGNATURE_ISP = '\x1B'
CMD_READ_OSCCAL_ISP = '\x1C'
CMD_SPI_MULTI = '\x1D'

-- STK PP command constants
CMD_ENTER_PROGMODE_PP = '\x20'
CMD_LEAVE_PROGMODE_PP = '\x21'
CMD_CHIP_ERASE_PP = '\x22'
CMD_PROGRAM_FLASH_PP = '\x23'
CMD_READ_FLASH_PP = '\x24'
CMD_PROGRAM_EEPROM_PP = '\x25'
CMD_READ_EEPROM_PP = '\x26'
CMD_PROGRAM_FUSE_PP = '\x27'
CMD_READ_FUSE_PP = '\x28'
CMD_PROGRAM_LOCK_PP = '\x29'
CMD_READ_LOCK_PP = '\x2A'
CMD_READ_SIGNATURE_PP = '\x2B'
CMD_READ_OSCCAL_PP = '\x2C'
CMD_SET_CONTROL_STACK = '\x2D'

-- STK HVSP command constants
CMD_ENTER_PROGMODE_HVSP = '\x30'
CMD_LEAVE_PROGMODE_HVSP = '\x31'
CMD_CHIP_ERASE_HVSP = '\x32'
CMD_PROGRAM_FLASH_HVSP = '\x33'
CMD_READ_FLASH_HVSP = '\x34'
CMD_PROGRAM_EEPROM_HVSP = '\x35'
CMD_READ_EEPROM_HVSP = '\x36'
CMD_PROGRAM_FUSE_HVSP = '\x37'
CMD_READ_FUSE_HVSP = '\x38'
CMD_PROGRAM_LOCK_HVSP = '\x39'
CMD_READ_LOCK_HVSP = '\x3A'
CMD_READ_SIGNATURE_HVSP = '\x3B'
CMD_READ_OSCCAL_HVSP = '\x3C'

-- STK status constants
--# Success
STATUS_CMD_OK = '\x00'
--# Warnings
STATUS_CMD_TOUT = '\x80'
STATUS_RDY_BSY_TOUT = '\x81'
STATUS_SET_PARAM_MISSING = '\x82'
--# Errors
STATUS_CMD_FAILED = '\xC0'
STATUS_CKSUM_ERROR = '\xC1'
STATUS_CMD_UNKNOWN = '\xC9'

-- STK parameter constants
PARAM_BUILD_NUMBER_LOW = '\x80'
PARAM_BUILD_NUMBER_HIGH = '\x81'
PARAM_HW_VER = '\x90'
PARAM_SW_MAJOR = '\x91'
PARAM_SW_MINOR = '\x92'
PARAM_VTARGET = '\x94'
PARAM_VADJUST = '\x95'
PARAM_OSC_PSCALE = '\x96'
PARAM_OSC_CMATCH = '\x97'
PARAM_SCK_DURATION = '\x98'
PARAM_TOPCARD_DETECT = '\x9A'
PARAM_STATUS = '\x9C'
PARAM_DATA = '\x9D'
PARAM_RESET_POLARITY = '\x9E'
PARAM_CONTROLLER_INIT = '\x9F'

-- STK answer constants
ANSWER_CKSUM_ERROR = '\xB0'

sequence = 0

function createMsg(body)
   local rv = MESSAGE_START..
              string.char(sequence)..
              string.char(bit.rshift(#body, 8))..string.char(bit.band(#body, 0xFF))..
              MESSAGE_TOKEN..
              body

   local sum = 0
   for i=1,#rv do sum = bit.bxor(sum, rv:byte(i)) end

   sequence = sequence + 1
   if sequence > 0xFF then sequence = 0 end

   return rv..string.char(sum)
end

function parseMsg(data)
end

function SIGN_ON()
   return createMsg('')
end

function SET_PARAMETER(parameterID, value)
   return createMsg(string.char(CMD_SET_PARAMETER, parameterID, value))
end

function GET_PARAMETER(parameterID)
   return createMsg(string.char(CMD_GET_PARAMETER, parameterID))
end

