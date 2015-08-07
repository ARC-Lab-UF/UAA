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

-- David Wilson
-- University of Florida

-- Description:
-- This file implements a fifo2 entity. Due to the nature of the FCBT, two elements
-- need to be read out during the same cycle. This is achieved with the fifo2 entity
-- by instantiating two fifo entities that take turns being written to and read from
-- as the first element of the fifo.

-- Notes:
-- The fifo protects against invalid writes (i.e. when full) and invalid reads
-- (i.e. when empty)
--
-- (use_bram = true and same_cycle_output = true) is not supported by
-- all FPGAs.
--
-- To simplify control logic, the depth is rounded up to an even number so that
-- both fifos have the same depth.

-- Used entities:
-- fifo

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.math_custom.all;
use work.flt_pkg.all;

-------------------------------------------------------------------------------
-- Generics Description
-- width             : the width of the FIFO in bits (required)
-- depth             : the depth of the FIFO in words (required)
-- use_bram          : uses bram when true, uses LUTs/FFs when false
-- same_cycle_output : output appears in same cycle as read when true, one
--                     cycle later when false
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Port Description:
-- clk    		: clock input
-- rst    		: reset input 					(asynchronous)
-- rd     		: read input 					(active high)
-- wr     		: write input 					(active high)
-- single 		: read only one input 			(active high)
-- empty  		: empty output 					(active high)
-- full   		: full output 					(active high)
-- overflow 	: fifo2 has overflowed 			(active high)
-- underflow 	: fifo2 has underflowed 		(active high)
-- input  		: fifo2 input
-- output0 		: fifo2 output, first element
-- output1		: fifo2 output, second element
-- count		: fifo2 count
-------------------------------------------------------------------------------

entity fifo2 is
    generic(
	    width               : positive;
        depth               : positive;
        use_bram            : boolean  := true;
        same_cycle_output   : boolean  := false);
    port(
	     clk     : in  std_logic;
         rst     : in  std_logic;
         rd      : in  std_logic;
         wr      : in  std_logic;
		 single  : in  std_logic;
         empty   : out std_logic;
         full    : out std_logic;
		 overflow : out std_logic;
		 underflow : out std_logic;
         input   : in  std_logic_vector(width-1 downto 0);
		 output0 : out std_logic_vector(width-1 downto 0);
         output1 : out std_logic_vector(width-1 downto 0);
		 count   : out std_logic_vector(clog2(depth+1)-1 downto 0)
	);
end fifo2;

architecture RTL of fifo2 is
	-- round buffer depth to a number divisible by two so that both fifos gets the 
	-- same depth
    constant BUFFER_DEPTH : positive := (depth+1)/2;
	
	-- fifo signals
	type data_array is array (natural range<>) of std_logic_vector(width-1 downto 0);
	signal buf_rd         : std_logic_vector(1 downto 0);
	signal buf_wr         : std_logic_vector(1 downto 0);
	signal buf_empty      : std_logic_vector(1 downto 0);
	signal buf_full       : std_logic_vector(1 downto 0);
	signal buf_out        : data_array(1 downto 0);
	
	-- control signals
	signal count_s			: std_logic_vector(clog2(depth+1)-1 downto 0);
	signal wr_sel          : std_logic;
	signal front_input_sel : std_logic;
begin

	-- determine which fifo has first element of fifo2
	output0 <= buf_out(0) when front_input_sel = '0' else buf_out(1);
	output1 <= buf_out(1) when front_input_sel = '0' else buf_out(0);

	-- update empty and full flags
	empty 	<= '1' 	when buf_empty = "11" else '0';
	full 	<= '1' 	when buf_full = "11" else '0';
	
	-- fifo2 counter
	process(clk, rst)
		variable buf_count : integer;
	begin
		if (rst = '1') then
			count_s 	<= (others => '0');
			overflow 	<= '0';
			underflow 	<= '0';
		elsif (rising_edge(clk)) then
			buf_count := to_integer(unsigned(count_s));
			
			if (wr = '1') then
			
				-- add to the buffer count if its not full
				-- otherwise, the buffer has overflowed
				if (to_integer(unsigned(count_s)) < depth) then
					buf_count := buf_count + 1;
				else
					overflow <= '1';
				end if;
			end if;
			
			if (rd = '1') then
			
				-- read only one element from the fifo2
				if (single = '1') then
				
					-- subtract from buffer count if its not empty
					-- otherwise, the buffer has underflowed
					if (to_integer(unsigned(count_s)) > 0) then
						buf_count := buf_count - 1;
					else
						underflow <= '1';
					end if;
					
				-- read two elements from the fifo2
				else
				
					-- subtract from buffer count if it doesn't have at least two elements
					-- otherwise, the buffer has underflowed
					if (to_integer(unsigned(count_s)) > 1) then
						buf_count := buf_count - 2;
					else
						underflow <= '1';
					end if;
				end if;
			end if;
			count_s <= std_logic_vector(to_unsigned(buf_count,count_s'length));
		end if;
	end process;
	count <= count_s;
	
	-- alternate writes between the two buffers
	process(clk, rst)
	begin
		if (rst = '1') then
			wr_sel <= '0';
		elsif (rising_edge(clk)) then
			if (wr = '1') then
				wr_sel <= not wr_sel;
			end if;
		end if;
	end process;
	
	-- only write to the fifo pointed to by wr_sel
	buf_wr(0) <= '1' when wr = '1' and wr_sel = '0' else '0';
	buf_wr(1) <= '1' when wr = '1' and wr_sel = '1' else '0';
	
	-- both buffers are read from when there is a non-singleton read.
	-- only front buffer is read from when there is a singleton read.
	buf_rd(0) <= '1' when rd = '1' and single = '0' else
	             '1' when rd = '1' and single = '1' and front_input_sel = '0' else '0';
				 
	buf_rd(1) <= '1' when rd = '1' and single = '0' else
	             '1' when rd = '1' and single = '1' and front_input_sel = '1' else '0';
	
	-- determine which fifo has the first element of fifo2
	process(clk, rst)
	begin
		if (rst = '1') then
			front_input_sel <= '0';
		elsif (rising_edge(clk)) then
			
			-- the front fifo only changes when a singleton read occurs
			if (rd = '1' and single = '1') then
				front_input_sel <= not front_input_sel;
			end if;
		end if;
	end process;
	
	U_BUF : for i in 0 to 1 generate
		U_IBUF0 : entity work.fifo
		generic map (
			width                 => width,
			depth                 => BUFFER_DEPTH,
			use_bram              => use_bram,
			use_distributed_ram   => false,
			same_cycle_output     => same_cycle_output)
		port map (
			clk    => clk,
			rst    => rst,
			rd     => buf_rd(i),
			wr     => buf_wr(i),
			empty  => buf_empty(i),
			full   => buf_full(i),
			input  => input,
			output => buf_out(i)
		);
	end generate;
end RTL;

