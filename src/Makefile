##
 #  Copyright (C) 2013 Chris Osgood
 #
 #  This program is free software: you can redistribute it and/or modify
 #  it under the terms of the GNU General Public License as published by
 #  the Free Software Foundation, version 3 of the License.
 #
 #  This program is distributed in the hope that it will be useful,
 #  but WITHOUT ANY WARRANTY; without even the implied warranty of
 #  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 #  GNU General Public License for more details.
 #
 #  You should have received a copy of the GNU General Public License
 #  along with this program.  If not, see <http://www.gnu.org/licenses/>.
##

VERSION=$(shell grep -o '[0-9.]\+' VERSION)
SYSTEM=$(shell uname)

ifneq (,$(findstring MINGW,$(SYSTEM)))
   SYSTEM=mingw
endif

CC=gcc
CXX=g++

CFLAGS=-O2 -Wall -m32
LDFLAGS=-static -s
LIBS=../ext/luajit/src/libluajit.a
OBJS=luajit.o serial.o lpeg.o luaserial.o linenoise.o linenoiselib.o
OUTDIR=.lib/

ifeq "$(SYSTEM)" "Darwin"
   LIBS+=-ldl -lpthread -lm
   CFLAGS=-O2 -Wall -mmacosx-version-min=10.6 -fPIC -fomit-frame-pointer \
          -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -U_FORTIFY_SOURCE \
          -fno-stack-protector
   LDFLAGS=-pagezero_size 10000 -image_base 100000000
   OBJS+=serialimpl.o
   OUTEXE=$(OUTDIR)MultiWiiCL
   LUAEXE=../ext/luajit/src/luajit
else
   ifeq "$(SYSTEM)" "mingw"
      OBJS+=winserialimpl.o
      OUTEXE=$(OUTDIR)MultiWiiCL.exe
      LUAEXE=../ext/luajit/src/luajit.exe
   else
      ifdef CROSS_MINGW
         CC=i486-mingw32-gcc
         CXX=i486-mingw32-g++
         OBJS+=winserialimpl.o
         OUTEXE=$(OUTDIR)MultiWiiCL.exe
         LUAEXE=luajit
      else
         OBJS+=serialimpl.o
         LIBS+=-ldl -lpthread -lm
         OUTEXE=$(OUTDIR)MultiWiiCL
         LUAEXE=../ext/luajit/src/luajit
      endif
   endif
endif

LUAHDRS=MultiWii.h Prompt.h Config.h

INCLUDES=-I$(OUTDIR) -I../ext/linenoise -I../ext/luajit/src -I../ext/serial/include

all: $(OUTEXE)

$(OUTDIR):
	mkdir -p $(OUTDIR)

###############################################################################

../ext/luajit/src/libluajit.a:
ifeq "$(SYSTEM)" "Darwin"
	make -C ../ext/luajit CFLAGS=-mmacosx-version-min=10.6 LDFLAGS=-mmacosx-version-min=10.6 BUILDMODE=static
else
ifdef CROSS_MINGW
	make -C ../ext/luajit HOST_CC="gcc -m32" CROSS=i486-mingw32- TARGET_SYS=Windows BUILDMODE=static
else
	make -C ../ext/luajit CC="gcc -m32" BUILDMODE=static
endif
endif

###############################################################################

$(OUTDIR)%.h: %.lua
	$(LUAEXE) bintosrc.lua $^ $(basename $^) > $@

###############################################################################

$(OUTEXE): $(OUTDIR) ../ext/luajit/src/libluajit.a $(addprefix $(OUTDIR),$(OBJS))
	$(CXX) $(CFLAGS) $(INCLUDES) $(LDFLAGS) $(addprefix $(OUTDIR),$(OBJS)) -o $@ $(LIBS)
	cp -a $@ .

###############################################################################

$(OUTDIR)luajit.o: $(addprefix $(OUTDIR),$(LUAHDRS)) luajit.c
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ luajit.c

$(OUTDIR)serial.o: ../ext/serial/src/serial.cc
	$(CXX) $(CFLAGS) $(INCLUDES) -c -o $@ $^

$(OUTDIR)serialimpl.o: ../ext/serial/src/impl/unix.cc
	$(CXX) $(CFLAGS) $(INCLUDES) -c -o $@ $^

$(OUTDIR)winserialimpl.o: ../ext/serial/src/impl/win.cc
	$(CXX) $(CFLAGS) $(INCLUDES) -c -o $@ $^

$(OUTDIR)luaserial.o: luaserial.cpp
	$(CXX) $(CFLAGS) $(INCLUDES) -c -o $@ $^
	
$(OUTDIR)lpeg.o: ../ext/lpeg/lpeg.c
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $^

$(OUTDIR)linenoise.o: ../ext/lua-linenoise/linenoise.c
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $^

$(OUTDIR)linenoiselib.o: ../ext/linenoise/linenoise.c
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $^

###############################################################################

clean:
	rm -rf MultiWiiCL MultiWiiCL.exe .lib

allclean: clean
	cd ../ext/luajit && make clean

###############################################################################

package: $(OUTEXE)
ifeq "$(SYSTEM)" "Darwin"
	rm -f MultiWiiCL-osx-x86-$(VERSION).zip
	zip MultiWiiCL-osx-x86-$(VERSION).zip MultiWiiCL
	mv MultiWiiCL-osx-x86-$(VERSION).zip ../bin/
else
ifeq "$(SYSTEM)" "mingw"
	rm -f MultiWiiCL-win-x86-$(VERSION).zip
	zip MultiWiiCL-win-x86-$(VERSION).zip MultiWiiCL.exe
	mv MultiWiiCL-win-x86-$(VERSION).zip ../bin/
else
ifdef CROSS_MINGW
	rm -f MultiWiiCL-win-x86-$(VERSION).zip
	zip MultiWiiCL-win-x86-$(VERSION).zip MultiWiiCL.exe
	mv MultiWiiCL-win-x86-$(VERSION).zip ../bin/
else
	tar cvfz MultiWiiCL-linux-x86-$(VERSION).tar.gz MultiWiiCL
	mv MultiWiiCL-linux-x86-$(VERSION).tar.gz ../bin/
endif  
endif  
endif

###############################################################################

patchext:
	-cd ../ext/serial && patch -N -p1 < ../serial.patch
	-cd ../ext/linenoise && patch -N -p1 < ../linenoise.patch
	-cd ../ext/lua-linenoise && patch -N -p1 < ../lua-linenoise.patch
