--  Copyright (c) 2015 University of Florida
--
--  This file is part of uaa.
--
--  uaa is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  uaa is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with uaa.  If not, see <http://www.gnu.org/licenses/>.

-- Greg Stitt
-- University of Florida

-- Description:
-- This file implements a fifo entity. The fifo has a configurable depth
-- and width, and can use bram, distributed ram, or LUTs/FFs to implement
-- the buffer. The fifo also has a configurable output delay of either 0 or 1
-- cycles.
--
-- This entity does not implement the behavior of the fifo and instead
-- instantiates fifo_core architectures depending on the configuration of
-- generics. The fifo and fifo_core could potentially be combined, but having
-- recursive instantiations causes problems with some simulators, which this
-- implementation tries to avoid.

-- Notes:
-- The fifo protects against invalid writes (i.e. when full) and invalid reads
-- (i.e. when empty)
--
-- (use_bram = true and same_cycle_output = true) is not supported by
-- all FPGAs.
--
-- When using BRAM, the FIFO depth is rounded up to the nearest power of two.
--
-- The actual choice of RAM depends on the specific synthesis tool and FPGA.
-- This entity does not guarantee the correct type.

-- Used entities:
-- fifo_core

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------
-- Generics Description
-- width             : the width of the FIFO in bits (required)
-- depth             : the depth of the FIFO in words (required)
-- use_bram          : uses bram when true, uses LUTs/FFs when false
--                     (default = true)
-- use_distribted_ram : uses distributed ram when true. If use_bram is also
--                      true, use_distributed_ram is ignore. If both are false,
--                      use LUTS/FFs. (default = false)
-- same_cycle_output : when true, output appears in same cycle as read. when
--                     false, output appears one cycle after read.
--                     (default = false)
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Port Description: (all control inputs are active high)
-- clk    : clock
-- rst    : reset (asynchronous)
-- rd     : read enable
-- wr     : write enable 
-- empty  : asserted when the FIFO is empty
-- full   : asserted when the FIFO is full
-- input  : Input to write into the FIFO
-- output : Output read from the FIFO
-------------------------------------------------------------------------------

entity fifo is
    generic(width               : positive;
            depth               : positive;
            use_bram            : boolean  := true;
            use_distributed_ram : boolean  := false;
            same_cycle_output   : boolean  := false);
    port(clk    : in  std_logic;
         rst    : in  std_logic;
         rd     : in  std_logic;
         wr     : in  std_logic;
         empty  : out std_logic;
         full   : out std_logic;
         input  : in  std_logic_vector(width-1 downto 0);
         output : out std_logic_vector(width-1 downto 0));
end fifo;


architecture DEFAULT of fifo is
begin

    -- if the user doesn't want any type of ram, use the flip-flop architecture
    FF : if use_bram = false and use_distributed_ram = false generate

        U_FIFO_FF : entity work.fifo_core(FF)
            generic map (width             => width,
                         depth             => depth,
                         use_bram          => false,
                         same_cycle_output => same_cycle_output)
            port map (clk    => clk,
                      rst    => rst,
                      rd     => rd,
                      wr     => wr,
                      empty  => empty,
                      full   => full,
                      input  => input,
                      output => output);
    end generate FF;

    -- for any type of memory, use the MEMORY architecture where the use_bram
    -- option will specify the type of memory
    MEMORY : if use_bram = true or use_distributed_ram = true generate
        
        U_FIFO_RAM : entity work.fifo_core(MEMORY)
            generic map (width             => width,
                         depth             => depth,
                         use_bram          => use_bram,
                         same_cycle_output => same_cycle_output)
            port map (clk    => clk,
                      rst    => rst,
                      rd     => rd,
                      wr     => wr,
                      empty  => empty,
                      full   => full,
                      input  => input,
                      output => output);
    end generate MEMORY;
end DEFAULT;

