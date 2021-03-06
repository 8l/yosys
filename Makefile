
CONFIG := clang
# CONFIG := gcc
# CONFIG := gcc-4.6
# CONFIG := emcc
# CONFIG := mxe

# features (the more the better)
ENABLE_TCL := 1
ENABLE_ABC := 1
ENABLE_PLUGINS := 1
ENABLE_READLINE := 1
ENABLE_VERIFIC := 0
ENABLE_COVER := 1

# other configuration flags
ENABLE_GPROF := 0
ENABLE_NDEBUG := 0

DESTDIR := /usr/local
INSTALL_SUDO :=

TARGET_BINDIR := $(DESTDIR)/bin
TARGET_DATDIR := $(DESTDIR)/share/yosys

EXE =
OBJS =
GENFILES =
EXTRA_OBJS =
EXTRA_TARGETS =
TARGETS = yosys$(EXE) yosys-config

PRETTY = 1
SMALL = 0

all: top-all

YOSYS_SRC := $(shell pwd)
CXXFLAGS = -Wall -Wextra -ggdb -I"$(YOSYS_SRC)" -MD -D_YOSYS_ -fPIC -I$(DESTDIR)/include
LDFLAGS = -L$(DESTDIR)/lib
LDLIBS = -lstdc++ -lm
SED = sed
BISON = bison

ifeq (Darwin,$(findstring Darwin,$(shell uname)))
	# add macports/homebrew include and library path to search directories, don't use '-rdynamic' and '-lrt':
	CXXFLAGS += -I/opt/local/include -I/usr/local/opt/readline/include
	LDFLAGS += -L/opt/local/lib -L/usr/local/opt/readline/lib
	# add homebrew's libffi include and library path
	CXXFLAGS += $(shell PKG_CONFIG_PATH=$$(brew list libffi | grep pkgconfig | xargs dirname) pkg-config --silence-errors --cflags libffi)
	LDFLAGS += $(shell PKG_CONFIG_PATH=$$(brew list libffi | grep pkgconfig | xargs dirname) pkg-config --silence-errors --libs libffi)
	# use bison installed by homebrew if available
	BISON = $(shell (brew list bison | grep -m1 "bin/bison") || echo bison)
	SED = gsed
else
	LDFLAGS += -rdynamic
	LDLIBS += -lrt
endif

YOSYS_VER := 0.5+$(shell test -d .git && { git log --author=clifford@clifford.at --oneline c3c9fbfb8c678.. | wc -l; })
GIT_REV := $(shell git rev-parse --short HEAD 2> /dev/null || echo UNKNOWN)
OBJS = kernel/version_$(GIT_REV).o

# set 'ABCREV = default' to use abc/ as it is
#
# Note: If you do ABC development, make sure that 'abc' in this directory
# is just a symlink to your actual ABC working directory, as 'make mrproper'
# will remove the 'abc' directory and you do not want to accidentally
# delete your work on ABC..
ABCREV = 61ad5f908c03
ABCPULL = 1
ABCMKARGS = # CC="$(CXX)" CXX="$(CXX)"

define newline


endef

ifneq ($(wildcard Makefile.conf),)
$(info $(subst $$--$$,$(newline),$(shell sed 's,^,[Makefile.conf] ,; s,$$,$$--$$,;' < Makefile.conf | tr -d '\n' | sed 's,\$$--\$$$$,,')))
include Makefile.conf
endif

ifeq ($(CONFIG),clang)
CXX = clang
CXXFLAGS += -std=c++11 -Os

else ifeq ($(CONFIG),gcc)
CXX = gcc
CXXFLAGS += -std=gnu++0x -Os

else ifeq ($(CONFIG),gcc-4.6)
CXX = gcc-4.6
CXXFLAGS += -std=gnu++0x -Os

else ifeq ($(CONFIG),emcc)
CXX = emcc
CXXFLAGS := -std=c++11 $(filter-out -fPIC -ggdb,$(CXXFLAGS))
EMCCFLAGS := -Os -Wno-warn-absolute-paths
EMCCFLAGS += --memory-init-file 0 --embed-file share -s NO_EXIT_RUNTIME=1
EMCCFLAGS += -s EXPORTED_FUNCTIONS="['_main','_run','_prompt','_errmsg']"
EMCCFLAGS += -s DISABLE_EXCEPTION_CATCHING=0 -s ALLOW_MEMORY_GROWTH=1
# https://github.com/kripken/emscripten/blob/master/src/settings.js
CXXFLAGS += $(EMCCFLAGS)
LDFLAGS += $(EMCCFLAGS)
LDLIBS =
EXE = .js

TARGETS := $(filter-out yosys-config,$(TARGETS))
EXTRA_TARGETS += yosysjs-$(YOSYS_VER).zip

viz.js:
	wget -O viz.js.part https://github.com/mdaines/viz.js/releases/download/0.0.3/viz.js
	mv viz.js.part viz.js

yosysjs-$(YOSYS_VER).zip: yosys.js viz.js misc/yosysjs/*
	rm -rf yosysjs-$(YOSYS_VER) yosysjs-$(YOSYS_VER).zip
	mkdir -p yosysjs-$(YOSYS_VER)
	cp viz.js misc/yosysjs/* yosys.js yosysjs-$(YOSYS_VER)/
	zip -r yosysjs-$(YOSYS_VER).zip yosysjs-$(YOSYS_VER)

yosys.html: misc/yosys.html
	$(P) cp misc/yosys.html yosys.html

else ifeq ($(CONFIG),mxe)
CXX = /usr/local/src/mxe/usr/bin/i686-pc-mingw32-gcc
CXXFLAGS += -std=gnu++0x -Os -D_POSIX_SOURCE
CXXFLAGS := $(filter-out -fPIC,$(CXXFLAGS))
LDFLAGS := $(filter-out -rdynamic,$(LDFLAGS)) -s
LDLIBS := $(filter-out -lrt,$(LDLIBS))
ABCMKARGS += ARCHFLAGS="-DSIZEOF_VOID_P=4 -DSIZEOF_LONG=4 -DSIZEOF_INT=4 -DWIN32_NO_DLL -x c++ -fpermissive -w"
ABCMKARGS += LIBS="lib/x86/pthreadVC2.lib -s" READLINE=0 CC="$(CXX)" CXX="$(CXX)"
EXE = .exe

else ifneq ($(CONFIG),none)
$(error Invalid CONFIG setting '$(CONFIG)'. Valid values: clang, gcc, gcc-4.6, emcc, none)
endif

ifeq ($(ENABLE_READLINE),1)
CXXFLAGS += -DYOSYS_ENABLE_READLINE
LDLIBS += -lreadline
ifeq ($(CONFIG),mxe)
LDLIBS += -lpdcurses
endif
endif

ifeq ($(ENABLE_PLUGINS),1)
CXXFLAGS += -DYOSYS_ENABLE_PLUGINS $(shell pkg-config --silence-errors --cflags libffi)
LDLIBS += $(shell pkg-config --silence-errors --libs libffi || echo -lffi) -ldl
endif

ifeq ($(ENABLE_TCL),1)
TCL_VERSION ?= tcl$(shell echo 'puts [info tclversion]' | tclsh)
TCL_INCLUDE ?= /usr/include/$(TCL_VERSION)
CXXFLAGS += -I$(TCL_INCLUDE) -DYOSYS_ENABLE_TCL
LDLIBS += -l$(TCL_VERSION)
endif

ifeq ($(ENABLE_GPROF),1)
CXXFLAGS += -pg
LDFLAGS += -pg
endif

ifeq ($(ENABLE_NDEBUG),1)
CXXFLAGS := -O3 -DNDEBUG $(filter-out -Os,$(CXXFLAGS))
endif

ifeq ($(ENABLE_ABC),1)
CXXFLAGS += -DYOSYS_ENABLE_ABC
TARGETS += yosys-abc$(EXE)
endif

ifeq ($(ENABLE_VERIFIC),1)
VERIFIC_DIR ?= /usr/local/src/verific_lib_eval
VERIFIC_COMPONENTS ?= verilog vhdl database util containers
CXXFLAGS += $(patsubst %,-I$(VERIFIC_DIR)/%,$(VERIFIC_COMPONENTS)) -DYOSYS_ENABLE_VERIFIC
LDLIBS += $(patsubst %,$(VERIFIC_DIR)/%/*-linux.a,$(VERIFIC_COMPONENTS))
endif

ifeq ($(ENABLE_COVER),1)
CXXFLAGS += -DYOSYS_ENABLE_COVER
endif

define add_share_file
EXTRA_TARGETS += $(subst //,/,$(1)/$(notdir $(2)))
$(subst //,/,$(1)/$(notdir $(2))): $(2)
	$$(P) mkdir -p $(1)
	$$(Q) cp $(2) $(subst //,/,$(1)/$(notdir $(2)))
endef

define add_include_file
$(eval $(call add_share_file,$(dir share/include/$(1)),$(1)))
endef

ifeq ($(PRETTY), 1)
P_STATUS = 0
P_OFFSET = 0
P_UPDATE = $(eval P_STATUS=$(shell echo $(OBJS) yosys$(EXE) | gawk 'BEGIN { RS = " "; I = $(P_STATUS)+0; } $$1 == "$@" && NR > I { I = NR; } END { print I; }'))
P_SHOW = [$(shell gawk "BEGIN { N=$(words $(OBJS) yosys$(EXE)); printf \"%3d\", $(P_OFFSET)+90*$(P_STATUS)/N; exit; }")%]
P = @echo "$(if $(findstring $@,$(TARGETS) $(EXTRA_TARGETS)),$(eval P_OFFSET = 10))$(call P_UPDATE)$(call P_SHOW) Building $@";
Q = @
S = -s
else
P_SHOW = ->
P =
Q =
S =
endif

$(eval $(call add_include_file,kernel/yosys.h))
$(eval $(call add_include_file,kernel/hashlib.h))
$(eval $(call add_include_file,kernel/log.h))
$(eval $(call add_include_file,kernel/rtlil.h))
$(eval $(call add_include_file,kernel/register.h))
$(eval $(call add_include_file,kernel/celltypes.h))
$(eval $(call add_include_file,kernel/consteval.h))
$(eval $(call add_include_file,kernel/sigtools.h))
$(eval $(call add_include_file,kernel/modtools.h))
$(eval $(call add_include_file,kernel/macc.h))
$(eval $(call add_include_file,kernel/utils.h))
$(eval $(call add_include_file,kernel/satgen.h))
$(eval $(call add_include_file,libs/ezsat/ezsat.h))
$(eval $(call add_include_file,libs/ezsat/ezminisat.h))
$(eval $(call add_include_file,libs/sha1/sha1.h))
$(eval $(call add_include_file,passes/fsm/fsmdata.h))
$(eval $(call add_include_file,backends/ilang/ilang_backend.h))

OBJS += kernel/driver.o kernel/register.o kernel/rtlil.o kernel/log.o kernel/calc.o kernel/yosys.o
kernel/log.o: CXXFLAGS += -DYOSYS_SRC='"$(YOSYS_SRC)"'

OBJS += libs/bigint/BigIntegerAlgorithms.o libs/bigint/BigInteger.o libs/bigint/BigIntegerUtils.o
OBJS += libs/bigint/BigUnsigned.o libs/bigint/BigUnsignedInABase.o

OBJS += libs/sha1/sha1.o

ifneq ($(SMALL),1)

OBJS += libs/subcircuit/subcircuit.o

OBJS += libs/ezsat/ezsat.o
OBJS += libs/ezsat/ezminisat.o

OBJS += libs/minisat/Options.o
OBJS += libs/minisat/SimpSolver.o
OBJS += libs/minisat/Solver.o
OBJS += libs/minisat/System.o

include frontends/*/Makefile.inc
include passes/*/Makefile.inc
include backends/*/Makefile.inc
include techlibs/*/Makefile.inc

else

include frontends/verilog/Makefile.inc
include frontends/ilang/Makefile.inc
include frontends/ast/Makefile.inc

OBJS += passes/hierarchy/hierarchy.o
OBJS += passes/cmds/select.o
OBJS += passes/cmds/show.o
OBJS += passes/cmds/stat.o
OBJS += passes/cmds/cover.o
OBJS += passes/cmds/design.o
OBJS += passes/cmds/plugin.o

include passes/proc/Makefile.inc
include passes/opt/Makefile.inc
include passes/techmap/Makefile.inc
include passes/abc/Makefile.inc

include backends/verilog/Makefile.inc
include backends/ilang/Makefile.inc

include techlibs/common/Makefile.inc

endif

top-all: $(TARGETS) $(EXTRA_TARGETS)
	@echo ""
	@echo "  Build successful."
	@echo ""

yosys$(EXE): $(OBJS)
	$(P) $(CXX) -o yosys$(EXE) $(LDFLAGS) $(OBJS) $(LDLIBS)

%.o: %.cc
	$(P) $(CXX) -o $@ -c $(CXXFLAGS) $<

%.o: %.cpp
	$(P) $(CXX) -o $@ -c $(CXXFLAGS) $<

kernel/version_$(GIT_REV).cc: Makefile
	$(P) rm -f kernel/version_*.o kernel/version_*.d kernel/version_*.cc
	$(Q) echo "namespace Yosys { extern const char *yosys_version_str; const char *yosys_version_str=\"Yosys $(YOSYS_VER) (git sha1 $(GIT_REV), $(notdir $(CXX)) ` \
			$(CXX) --version | tr ' ()' '\n' | grep '^[0-9]' | head -n1` $(filter -f% -m% -O% -DNDEBUG,$(CXXFLAGS)))\"; }" > kernel/version_$(GIT_REV).cc

yosys-config: misc/yosys-config.in
	$(P) $(SED) -e 's,@CXXFLAGS@,$(subst -I"$(YOSYS_SRC)",-I"$(TARGET_DATDIR)/include",$(CXXFLAGS)),;' \
			-e 's,@CXX@,$(CXX),;' -e 's,@LDFLAGS@,$(LDFLAGS),;' -e 's,@LDLIBS@,$(LDLIBS),;' \
			-e 's,@BINDIR@,$(TARGET_BINDIR),;' -e 's,@DATDIR@,$(TARGET_DATDIR),;' < misc/yosys-config.in > yosys-config
	$(Q) chmod +x yosys-config

abc/abc-$(ABCREV)$(EXE):
	$(P)
ifneq ($(ABCREV),default)
	$(Q) if ( cd abc 2> /dev/null && hg identify; ) | grep -q +; then \
		echo 'REEBE: NOP pbagnvaf ybpny zbqvsvpngvbaf! Frg NOPERI=qrsnhyg va Lbflf Znxrsvyr!' | tr 'A-Za-z' 'N-ZA-Mn-za-m'; false; \
	fi
	$(Q) if test "`cd abc 2> /dev/null && hg identify | cut -f1 -d' '`" != "$(ABCREV)"; then \
		test $(ABCPULL) -ne 0 || { echo 'REEBE: NOP abg hc gb qngr naq NOPCHYY frg gb 0 va Znxrsvyr!' | tr 'A-Za-z' 'N-ZA-Mn-za-m'; exit 1; }; \
		echo "Pulling ABC from bitbucket.org:"; set -x; \
		test -d abc || hg clone https://bitbucket.org/alanmi/abc abc; \
		cd abc && $(MAKE) DEP= clean && hg pull && hg update -r $(ABCREV); \
	fi
endif
	$(Q) rm -f abc/abc-[0-9a-f]*
	$(Q) cd abc && $(MAKE) $(S) $(ABCMKARGS) PROG="abc-$(ABCREV)$(EXE)" MSG_PREFIX="$(eval P_OFFSET = 5)$(call P_SHOW)$(eval P_OFFSET = 10) ABC: "

ifeq ($(ABCREV),default)
.PHONY: abc/abc-$(ABCREV)$(EXE)
endif

yosys-abc$(EXE): abc/abc-$(ABCREV)$(EXE)
	$(P) cp abc/abc-$(ABCREV)$(EXE) yosys-abc$(EXE)

test: $(TARGETS) $(EXTRA_TARGETS)
	+cd tests/simple && bash run-test.sh
	+cd tests/hana && bash run-test.sh
	+cd tests/asicworld && bash run-test.sh
	+cd tests/realmath && bash run-test.sh
	+cd tests/share && bash run-test.sh
	+cd tests/fsm && bash run-test.sh
	+cd tests/techmap && bash run-test.sh
	+cd tests/memories && bash run-test.sh
	+cd tests/bram && bash run-test.sh
	+cd tests/various && bash run-test.sh
	+cd tests/sat && bash run-test.sh
	@echo ""
	@echo "  Passed \"make test\"."
	@echo ""

VALGRIND ?= valgrind --error-exitcode=1 --leak-check=full --show-reachable=yes --errors-for-leak-kinds=all

vgtest: $(TARGETS) $(EXTRA_TARGETS)
	$(VALGRIND) ./yosys -p 'setattr -mod -unset top; synth' $$( ls tests/simple/*.v | grep -v repwhile.v )
	@echo ""
	@echo "  Passed \"make vgtest\"."
	@echo ""

vloghtb: $(TARGETS) $(EXTRA_TARGETS)
	+cd tests/vloghtb && bash run-test.sh
	@echo ""
	@echo "  Passed \"make vloghtb\"."
	@echo ""

install: $(TARGETS) $(EXTRA_TARGETS)
	$(INSTALL_SUDO) mkdir -p $(DESTDIR)/bin
	$(INSTALL_SUDO) install $(TARGETS) $(DESTDIR)/bin/
	$(INSTALL_SUDO) mkdir -p $(DESTDIR)/share/yosys
	$(INSTALL_SUDO) cp -r share/. $(DESTDIR)/share/yosys/.

uninstall:
	$(INSTALL_SUDO) rm -vf $(addprefix $(DESTDIR)/bin/,$(notdir $(TARGETS)))
	$(INSTALL_SUDO) rm -rvf $(DESTDIR)/share/yosys/

update-manual: $(TARGETS) $(EXTRA_TARGETS)
	cd manual && ../yosys -p 'help -write-tex-command-reference-manual'

manual: $(TARGETS) $(EXTRA_TARGETS)
	cd manual && bash appnotes.sh
	cd manual && bash presentation.sh
	cd manual && bash manual.sh

clean:
	rm -rf share
	cd manual && bash clean.sh
	rm -f $(OBJS) $(GENFILES) $(TARGETS) $(EXTRA_TARGETS) $(EXTRA_OBJS)
	rm -f kernel/version_*.o kernel/version_*.cc abc/abc-[0-9a-f]*
	rm -f libs/*/*.d frontends/*/*.d passes/*/*.d backends/*/*.d kernel/*.d techlibs/*/*.d

clean-abc:
	$(MAKE) -C abc DEP= clean
	rm -f yosys-abc$(EXE) abc/abc-[0-9a-f]*

mrproper: clean
	git clean -xdf

qtcreator:
	{ for file in $(basename $(OBJS)); do \
		for prefix in cc y l; do if [ -f $${file}.$${prefix} ]; then echo $$file.$${prefix}; fi; done \
	done; find backends frontends kernel libs passes -type f \( -name '*.h' -o -name '*.hh' \); } > qtcreator.files
	{ echo .; find backends frontends kernel libs passes -type f \( -name '*.h' -o -name '*.hh' \) -printf '%h\n' | sort -u; } > qtcreator.includes
	touch qtcreator.config qtcreator.creator

vcxsrc: $(GENFILES) $(EXTRA_TARGETS)
	rm -rf yosys-win32-vcxsrc-$(YOSYS_VER){,.zip}
	set -e; for f in `ls $(filter %.cc %.cpp,$(GENFILES)) $(addsuffix .cc,$(basename $(OBJS))) $(addsuffix .cpp,$(basename $(OBJS))) 2> /dev/null`; do \
		echo "Analyse: $$f" >&2; cpp -std=gnu++0x -MM -I. -D_YOSYS_ $$f; done | sed 's,.*:,,; s,//*,/,g; s,/[^/]*/\.\./,/,g; y, \\,\n\n,;' | grep '^[^/]' | sort -u | grep -v kernel/version_ > srcfiles.txt
	bash misc/create_vcxsrc.sh yosys-win32-vcxsrc $(YOSYS_VER) $(GIT_REV)
	echo "namespace Yosys { extern const char *yosys_version_str; const char *yosys_version_str=\"Yosys (Version Information Unavailable)\"; }" > kernel/version.cc
	zip yosys-win32-vcxsrc-$(YOSYS_VER)/genfiles.zip $(GENFILES) kernel/version.cc
	zip -r yosys-win32-vcxsrc-$(YOSYS_VER).zip yosys-win32-vcxsrc-$(YOSYS_VER)/
	rm -f srcfiles.txt kernel/version.cc

ifeq ($(CONFIG),mxe)
mxebin: $(TARGETS) $(EXTRA_TARGETS)
	rm -rf yosys-win32-mxebin-$(YOSYS_VER){,.zip}
	mkdir -p yosys-win32-mxebin-$(YOSYS_VER)
	cp -r yosys.exe share/ yosys-win32-mxebin-$(YOSYS_VER)/
ifeq ($(ENABLE_ABC),1)
	cp -r yosys-abc.exe abc/lib/x86/pthreadVC2.dll yosys-win32-mxebin-$(YOSYS_VER)/
endif
	echo -en 'This is Yosys $(YOSYS_VER) for Win32.\r\n' > yosys-win32-mxebin-$(YOSYS_VER)/readme.txt
	echo -en 'Documentation at http://www.clifford.at/yosys/.\r\n' >> yosys-win32-mxebin-$(YOSYS_VER)/readme.txt
	zip -r yosys-win32-mxebin-$(YOSYS_VER).zip yosys-win32-mxebin-$(YOSYS_VER)/
endif

config-clean: clean
	rm -f Makefile.conf

config-clang: clean
	echo 'CONFIG := clang' > Makefile.conf

config-gcc: clean
	echo 'CONFIG := gcc' > Makefile.conf

config-gcc-4.6: clean
	echo 'CONFIG := gcc-4.6' > Makefile.conf

config-emcc: clean
	echo 'CONFIG := emcc' > Makefile.conf
	echo 'ENABLE_TCL := 0' >> Makefile.conf
	echo 'ENABLE_ABC := 0' >> Makefile.conf
	echo 'ENABLE_PLUGINS := 0' >> Makefile.conf
	echo 'ENABLE_READLINE := 0' >> Makefile.conf

config-mxe: clean
	echo 'CONFIG := mxe' > Makefile.conf
	echo 'ENABLE_TCL := 0' >> Makefile.conf
	echo 'ENABLE_PLUGINS := 0' >> Makefile.conf
	echo 'ENABLE_READLINE := 0' >> Makefile.conf

config-gprof: clean
	echo 'CONFIG := gcc' > Makefile.conf
	echo 'ENABLE_GPROF := 1' >> Makefile.conf

config-sudo:
	echo "INSTALL_SUDO := sudo" >> Makefile.conf

echo-yosys-ver:
	@echo "$(YOSYS_VER)"

echo-git-rev:
	@echo "$(GIT_REV)"

-include libs/*/*.d
-include frontends/*/*.d
-include passes/*/*.d
-include backends/*/*.d
-include kernel/*.d
-include techlibs/*/*.d

.PHONY: all top-all abc test install install-abc manual clean mrproper qtcreator
.PHONY: config-clean config-clang config-gcc config-gcc-4.6 config-gprof config-sudo

