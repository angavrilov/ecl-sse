# Makefile for Windows NT.  Assumes Microsoft compiler.
# DLLs are included in the root set under NT, but not under win32S.
# Use "nmake nodebug=1 all" for optimized versions of library, gctest and editor.
# MY_CPU=X86 for 32 bits or AMD64 for 64 bits
CPU=$(MY_CPU)
!include <ntwin32.mak>

srcdir=..\..\src\gc

!if "$(ECL_THREADS)" != ""
THREADS_OBJ= win32_threads.obj thread_local_alloc.obj
THREADS_FLAGS= -D_CRT_SECURE_NO_WARNINGS -DGC_DLL -DGC_BUILD -DGC_WIN32_THREADS -DTHREAD_LOCAL_ALLOC -DLARGE_CONFIG
!else
THREADS_OBJ=
THREADS_FLAGS= -D_CRT_SECURE_NO_WARNINGS -DGC_DLL -DGC_BUILD -DLARGE_CONFIG
!endif

# Make sure that .cc is not viewed as a suffix.  It is for VC++2005, but
# not earlier versions.  We can deal with either, but not inconsistency.
.SUFFIXES:
.SUFFIXES: .obj .cpp .c

# Atomic_ops installation directory.  For win32, the source directory
# should do, since we only need the headers.
# We assume this was manually unpacked, since I'm not sure there is
# a Windows standard command line tool to do this.
AO_VERSION=1.2
AO_SRC_DIR=$(srcdir)/libatomic_ops-$(AO_VERSION)/src
AO_INCLUDE_DIR=$(AO_SRC_DIR)

OBJS= alloc.obj reclaim.obj allchblk.obj misc.obj mach_dep.obj os_dep.obj mark_rts.obj headers.obj mark.obj obj_map.obj blacklst.obj finalize.obj new_hblk.obj dbg_mlc.obj malloc.obj stubborn.obj dyn_load.obj typd_mlc.obj ptr_chck.obj gc_cpp.obj mallocx.obj win32_threads.obj msvc_dbg.obj thread_local_alloc.obj

all: gc.lib

{$(srcdir)}.c{}.obj:
	$(cc) $(cdebug) $(cflags) $(cvarsmt) $(CFLAGS_CONFIG) -Iinclude -I$(AO_INCLUDE_DIR) $(THREADS_FLAGS) -I$(srcdir)\include $< /Fo$*.obj

{$(srcdir)\tests}.c{tests}.obj:
	$(cc) $(cdebug) $(cflags) $(cvarsmt) $(CFLAGS_CONFIG) -Iinclude -I$(AO_INCLUDE_DIR) $(THREADS_FLAGS) -I$(srcdir)\include $< /Fo$*.obj

{$(srcdir)}.cpp{}.obj:
	$(cc) $(cdebug) $(cflags) $(cvarsmt) $(CFLAGS_CONFIG) -Iinclude -I$(AO_INCLUDE_DIR) $(THREADS_FLAGS) -I$(srcdir)\include $< /Fo$*.obj

$(OBJS) tests\test.obj: $(srcdir)\include\private\gc_priv.h $(srcdir)\include\private\gc_hdrs.h $(srcdir)\include\gc.h $(srcdir)\include\private\gcconfig.h $(srcdir)\include\private\gc_locks.h $(srcdir)\include\private\gc_pmark.h $(srcdir)\include\gc_mark.h $(srcdir)\include\private\msvc_dbg.h

gc.lib: $(OBJS)
!if "$(CPU)" == "X386"
	lib /MACHINE:i386 /out:gc.lib $(OBJS)
!else
	lib /MACHINE:X64 /out:gc.lib $(OBJS)
!endif
# The original NT SDK used lib32 instead of lib

gctest.exe: tests\test.obj gc.lib
#	The following works for win32 debugging.  For win32s debugging use debugtype:coff
#	and add mapsympe line.
#  This produces a "GUI" applications that opens no windows and writes to the log file
#  "gc.log".  This is done to make the result runnable under win32s.
	$(link) -debug:full -debugtype:cv $(guiflags) -stack:131072 -out:$*.exe tests\test.obj $(guilibs) gc.lib
#	mapsympe -n -o gctest.sym gctest.exe

cord\de_win.rbj: cord\de_win.res
	cvtres /MACHINE:$(MY_CPU) /OUT:cord\de_win.rbj cord\de_win.res

cord\de.obj cord\de_win.obj: $(srcdir)\include\cord.h $(srcdir)\include\private\cord_pos.h cord\de_win.h cord\de_cmds.h

cord\de_win.res: cord\de_win.rc cord\de_win.h cord\de_cmds.h
	$(rc) $(rcvars) -r -fo cord\de_win.res cord\de_win.rc

# Cord/de is a real win32 gui application.
cord\de.exe: cord\cordbscs.obj cord\cordxtra.obj cord\de.obj cord\de_win.obj cord\de_win.rbj gc.lib
	$(link) -debug:full -debugtype:cv $(guiflags) -stack:16384 -out:cord\de.exe  cord\cordbscs.obj cord\cordxtra.obj cord\de.obj cord\de_win.obj cord\de_win.rbj gc.lib $(guilibs)

gc_cpp.obj: $(srcdir)\include\gc_cpp.h $(srcdir)\include\gc.h

gc_cpp.cpp: $(srcdir)\gc_cpp.cc
	copy $? $@

test_cpp.cpp: $(srcdir)\tests\test_cpp.cc
	copy $? $@

# This generates the C++ test executable.  The executable expects
# a single numeric argument, which is the number of iterations.
# The output appears in the file "gc.log".
test_cpp.exe: test_cpp.obj $(srcdir)\include\gc_cpp.h $(srcdir)\include\gc.h gc.lib
	$(link) -debug:full -debugtype:cv $(guiflags) -stack:16384 -out:test_cpp.exe test_cpp.obj gc.lib $(guilibs)

AO_SCR_DIR:
	        tar xvfz $(AO_SRC_DIR).tar.gz;

