.PHONY: build verify clean

all: build verify

build: 
	if [ ! -d "./build" ]; then mkdir build; fi
	xtclsh build.tcl;

verify:
	if [ ! -d "./sim" ]; then mkdir sim; fi
	cd sim; fuse -intstyle ise -prj ../sim.prj -top uaa_tb_all -top glbl -lib xilinxcorelib_ver -lib unisims_ver -lib unimacro_ver -lib secureip; \
	./x.exe -tclbatch ../isim.tcl
  
clean:
	-rm -rf build
	-rm -rf sim
	-rm -f *~
	-rm -f *.log
	-rm -f *.cmd
	-rm -f *.xmsgs
