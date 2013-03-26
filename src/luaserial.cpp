/*
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
*/

#define LUA_LIB

extern "C" {

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

}

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

#include "serial/serial.h"

using namespace serial;

#ifndef LUA_USE_MUSERDATA
#ifdef _MSC_VER
#pragma message("Using slow user-data type checking")
#else
#warning "Using slow user-data type checking"
#endif
#define luaL_checkmudata(a,b,c,d) luaL_checkudata(a,b,c)
#define luaL_testmudata(a,b,c,d) luaL_testudata(a,b,c)
#endif

static const void* serialtype;

static int gc_(lua_State* L)
{
   Serial** s = (Serial**)luaL_checkmudata(L, 1, "serial", serialtype);
   if (*s != 0)
   {
      (*s)->close();
      delete *s;
      *s = 0;
   }

   return 0;
}

static int new_(lua_State* L)
{
   try
   {
      const char* port =  luaL_checkstring(L, 1);
      int baud = luaL_checkint(L, 2);
   
      Serial** s = (Serial**)lua_newuserdata(L, sizeof(Serial*));
   
      *s = new Serial(port, baud);
   
      luaL_getmetatable(L, "serial");
      lua_setmetatable(L, -2);
   }
   catch (std::exception& e)
   {
      luaL_error(L, e.what());
   }
   catch (...)
   {
      luaL_error(L, "exception");
   }

   return 1;
}

static int open_(lua_State* L)
{
   try
   {
      Serial** s = (Serial**)luaL_checkmudata(L, 1, "serial", serialtype);
      (*s)->open();
   }
   catch (std::exception& e)
   {
      luaL_error(L, e.what());
   }
   catch (...)
   {
      luaL_error(L, "exception");
   }

   return 0;
}

static int close_(lua_State* L)
{
   try
   {
      Serial** s = (Serial**)luaL_checkmudata(L, 1, "serial", serialtype);
      (*s)->close();
   }
   catch (std::exception& e)
   {
      luaL_error(L, e.what());
   }
   catch (...)
   {
      luaL_error(L, "exception");
   }

   return 0;
}

static int read_(lua_State* L)
{
   try
   {
      Serial** s = (Serial**)luaL_checkmudata(L, 1, "serial", serialtype);
      size_t n = luaL_checkint(L, 2);
      uint8_t* buf = (uint8_t*)lua_newuserdata(L, n);
      n = (*s)->read(buf, n);
      lua_pushlstring(L, (const char*)buf, n);
   }
   catch (std::exception& e)
   {
      luaL_error(L, e.what());
   }
   catch (...)
   {
      luaL_error(L, "exception");
   }

   return 1;
}

static int write_(lua_State* L)
{
   try
   {
      Serial** s = (Serial**)luaL_checkmudata(L, 1, "serial", serialtype);
      size_t size;
      const char* data = luaL_checklstring(L, 2, &size);
      (*s)->write((uint8_t*)data, size);
   }
   catch (std::exception& e)
   {
      luaL_error(L, e.what());
   }
   catch (...)
   {
      luaL_error(L, "exception");
   }

   return 0;
}

static int flush_(lua_State* L)
{
   try
   {
      Serial** s = (Serial**)luaL_checkmudata(L, 1, "serial", serialtype);
      (*s)->flush();
   }
   catch (std::exception& e)
   {
      luaL_error(L, e.what());
   }
   catch (...)
   {
      luaL_error(L, "exception");
   }

   return 0;
}

static int setBaudrate_(lua_State* L)
{
   try
   {
      Serial** s = (Serial**)luaL_checkmudata(L, 1, "serial", serialtype);
      uint32_t baud = luaL_checkint(L, 2);
      (*s)->setBaudrate(baud);
   }
   catch (std::exception& e)
   {
      luaL_error(L, e.what());
   }
   catch (...)
   {
      luaL_error(L, "exception");
   }

   return 0;
}

static int setTimeout_(lua_State* L)
{
   try
   {
      Serial** s = (Serial**)luaL_checkmudata(L, 1, "serial", serialtype);
      uint32_t inter_byte_timeout = luaL_checkint(L, 2);
      uint32_t read_timeout_constant = luaL_optint(L, 3, 0);
      uint32_t read_timeout_multiplier = luaL_optint(L, 4, 0);
      uint32_t write_timeout_constant = luaL_optint(L, 5, 0);
      uint32_t write_timeout_multiplier = luaL_optint(L, 6, 0);
      (*s)->setTimeout(inter_byte_timeout, read_timeout_constant, read_timeout_multiplier, write_timeout_constant, write_timeout_multiplier);
   }
   catch (std::exception& e)
   {
      luaL_error(L, e.what());
   }
   catch (...)
   {
      luaL_error(L, "exception");
   }

   return 0;
}

static int sleep_(lua_State* L)
{
   long t = luaL_checklong(L, 1);
#ifdef _WIN32
   Sleep(t);
#else
   usleep(t * 1000);
#endif
   return 0;
}

static const luaL_Reg lualib_[] =
{
   {"new", new_},
   {"open", open_},
   {"close", close_},
   {"read", read_},
   {"write", write_},
   {"flush", flush_},
   {"setBaudrate", setBaudrate_},
   {"setTimeout", setTimeout_},
   {"sleep", sleep_},
   {0, 0}
};

extern "C" {

LUALIB_API int luaopen_luaserial(lua_State* L)
{
   luaL_register(L, "luaserial", lualib_);

   if (luaL_newmetatable(L, "serial"))
   {
      serialtype = lua_topointer(L, -1);
      lua_pushcfunction(L, gc_);
      lua_setfield(L, -2, "__gc");
      lua_pushvalue(L, -2);
      lua_setfield(L, -2, "__index");
   }

   lua_pop(L, 1);

   return 1;
}

} // extern "C"
