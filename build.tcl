# generic parameters
	set arch 			UAA_SGA
	set width 			32
	set parallel_inputs 4
	set add_core_name 	virtex7_latency
	set use_bram		true
	set FCBT_max_inputs 128
	set FCBT_obuf_size	16

# set the project name
set project_name uaa

# set the top-level of our HDL source:
set top_level_filename uaa
set top_level_entityname DEFAULT

# create and open the project and set project-level properties
   project new "build/${project_name}.ise"
   project set family "Virtex7"
   project set device "xc7vx485t"
   project set package "ffg1157"
   project set speed "-2"
   project set top_level_module_type "HDL"
   project set synthesis_tool "XST (VHDL/Verilog)"
   project set simulator "ISim (VHDL/Verilog)"
   
   # set the generic values
   project set "Generics, Parameters" "arch=$arch width=$width parallel_inputs=$parallel_inputs add_core_name=\"${add_core_name}\" use_bram=$use_bram FCBT_max_inputs=$FCBT_max_inputs FCBT_obuf_size=$FCBT_obuf_size" -process "Synthesize - XST" 

# set top_level entity
   project set top "${top_level_entityname}" "{top_level_filename}"
   
# add all the source HDLs
foreach filename [glob -directory ../src *] {
  xfile add $filename
}

# run the entire xst-to-trce flow
process run "Implement Design"

project close
