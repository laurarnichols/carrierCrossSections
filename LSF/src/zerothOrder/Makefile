
-include ../../../make.sys

# location of needed modules
MODFLAGS = -I$(CommonModules_srcPath) -I.

LSF0_OBJS = LSF_zeroth_Module_v35.o LSF_zeroth_Main.o

CommonMods = $(CommonModules_srcPath)/commonmodules.a

all : LSF0.x
	
LSF0.x : mods $(CommonMods) $(LSF0_OBJS)
	$(mpif90) $(LDFLAGS) $(MODFLAGS) -o $@ $(LSF0_OBJS) $(CommonMods)
	- ( cd $(Home_Path)/bin ; ln -fs $(LSF0_srcPath)/$@ . )

	@echo "" ; \
	echo "" ; \
	echo "Module 'LSF0' compiled successfully !" ; \
	echo "" ; \
	echo "" ;

mods :
	cd $(CommonModules_srcPath) ; \
	make

%.o : %.f90
	$(mpif90) $(MODFLAGS) -c -g $<

clean :

	@echo "" ; \
	echo "Cleaning module 'LSF0' ... " ; \
	/bin/rm -f *.x *.o *.mod .DS_Store ; \
	echo "Cleaning module 'LSF0' done !" ; \
	echo "" ; \

include make.depend
