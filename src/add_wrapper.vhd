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
-- The add_wrapper entity wraps the add_flt entity to implement a pipelined
-- floating-point adder that specifies when the output is valid based on the
-- pipeline latency of the specified adder core, while also outputting the
-- number of adds in the pipeline.

-- Used entities:
-- add_flt, delay

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.flt_pkg.all;
use work.math_custom.all;

-------------------------------------------------------------------------------
-- Generics Description
-- width             : The width of the adder input/output. This should match
--                     the precision of the adder (e.g. single precision=32,
--                     double precision=64) (required)
-- core_name           : A string specifying the optimization strategy, or just
--                     a name for the adder core. This string should be one of
--                     the possible user-defined values defined in flt_pkg
--                     for any corresponding adder cores.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Port Description:
-- clk       : clock input
-- rst       : reset input (active high)
-- en        : enable input (active high), stalls the pipeline when '0'
-- input1    : the first input to the add
-- input2    : the second input to the add
-- output    : the sum
-- valid_in  : user should assert when input is valid (active high)
-- valid_out : asserted by entity when output is valid after the adder core's
--             pipeline latency (active high)
-- count     : the number of pending adds within the adder core's pipeline
-------------------------------------------------------------------------------

entity add_wrapper is
    generic (
        width   : positive;
        core_name : string := "");
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        en        : in  std_logic;
        input1    : in  std_logic_vector(width-1 downto 0);
        input2    : in  std_logic_vector(width-1 downto 0);
        output    : out std_logic_vector(width-1 downto 0);
        valid_in  : in  std_logic;
        valid_out : out std_logic;
        count     : out std_logic_vector(bitsNeeded(add_flt_latency(core_name))-1 downto 0)
        );    
end add_wrapper;

architecture RTL of add_wrapper is
    constant COUNT_WIDTH : positive := bitsNeeded(add_flt_latency(core_name));
    signal count_s     : unsigned(COUNT_WIDTH-1 downto 0);
    signal valid_out_s : std_logic;
begin

    -- track the number of adds in the pipeline
    process(clk, rst)
    begin
        if (rst = '1') then
            count_s <= to_unsigned(0, COUNT_WIDTH);
        elsif (rising_edge(clk)) then
            if (en = '1') then
                if (en = '1' and valid_in = '1' and valid_out_s = '0') then
                    -- the number of pending adds increases when a valid
                    -- input enters and there isn't an output
                    count_s <= count_s + 1;
                elsif (en = '1' and valid_in = '0' and valid_out_s = '1') then
                    -- the number of pending adds decreases when output leaves
                    -- with no valid input
                    count_s <= count_s - 1;
                end if;
            end if;
        end if;
    end process;

    count <= std_logic_vector(count_s);

    -- instantiate the floating-point adder
    U_ADD_FLT : entity work.add_flt
        generic map (core_name => core_name)
        port map (clk    => clk,
                  en     => en,
                  input1 => input1,
                  input2 => input2,
                  output => output);

    -- delay enable signal (valid_in) to determine when adder output is valid
    U_DELAY : entity work.delay
        generic map (cycles => add_flt_latency(core_name),
                     width  => 1,
                     init   => "0")
        port map (clk       => clk,
                  rst       => rst,
                  en        => en,
                  input(0)  => valid_in,
                  output(0) => valid_out_s);

    valid_out <= valid_out_s;

end RTL;

