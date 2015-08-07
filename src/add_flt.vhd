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
-- The add_flt entity is a wrapper that provides a common interface to
-- different floating-point adder cores.
-- 
-- IMPORTANT INSTRUCTIONS:
-- 1) Instantiate a floating-point adder core and connect it to the I/O of
-- add_flt. The adder core must have the capability to stall the add pipeline.
-- 2) If you have multiple options for cores, use the add_core string to select a
-- corresponding implementation. For example, add_core="speed" could select a core
-- optimized for speed, whereas add_core="area" could select a core optimized for
-- area. add_core is completely option, so this step can be skipped if you only have
-- a single core
-- 3) Open flt_pkg.vhd and modify the function add_flt_latency.
-- In the simplest case of a single core option, simply return the latency of
-- the adder core in terms of clock cycles. When using the add_core string to choose
-- from different cores, modify the function to return the corresponding
-- latency of each option.

-- Used entities:
-- user dependent (whatever add cores they decide to use)
-- This file contains an example of how to map add_flt to Stratix 5 and Virtex 7
-- floating-point adder cores for different optimizations.

library ieee;
use ieee.std_logic_1164.all;

-------------------------------------------------------------------------------
-- Generics Description
-- width             : The width of the adder input/output. This should match
--                     the precision of the adder (e.g. single precision=32,
--                     double precision=64) (required)
-- name               : A string specifying the optimization strategy, or just
--                     a name for the adder core. This string is optional,
--                     but is useful when trying to instantiate
--                     implementations with different optimizations
--                     (e.g. area vs. speed).
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Port Description:
-- clk    : clock input
-- en     : enable input (active high), stalls the pipeline when '0'
-- input1 : the first  input to the add
-- input2 : the second input to the add
-- output : the sum
-------------------------------------------------------------------------------

entity add_flt is
    generic (
        width     : positive := 32;
        core_name : string   := "");
    port (
        clk    : in  std_logic;
        en     : in  std_logic;
        input1 : in  std_logic_vector(width-1 downto 0);
        input2 : in  std_logic_vector(width-1 downto 0);
        output : out std_logic_vector(width-1 downto 0));    
end add_flt;

architecture default of add_flt is
begin

    U_S5_LATENCY : if core_name = "stratix5_latency" generate
        U_STRATIX5_LATENCY : entity work.add_flt_stratix5_latency
            port map (
                clk_en => en,
                clock  => clk,
                dataa  => input1,
                datab  => input2,
                result => output);
    end generate U_S5_LATENCY;

    U_S5_AREA : if core_name = "stratix5_area" generate
        U_STRATIX5_AREA : entity work.add_flt_stratix5_area
            port map (
                clk_en => en,
                clock  => clk,
                dataa  => input1,
                datab  => input2,
                result => output);
    end generate U_S5_AREA;

    U_S5_SPEED : if core_name = "stratix5_speed" generate
        U_STRATIX5_SPEED : entity work.add_flt_stratix5_speed
            port map (
                clk_en => en,
                clock  => clk,
                dataa  => input1,
                datab  => input2,
                result => output);
    end generate U_S5_SPEED;

    U_V7_SPEED : if core_name = "virtex7_speed" generate
        U_VIRTEX7_SPEED : entity work.add_flt_virtex7_speed
            port map (
                clk    => clk,
                ce     => en,
                a      => input1,
                b      => input2,
                result => output);
    end generate U_V7_SPEED;

    U_V7_LATENCY : if core_name = "virtex7_latency" generate
        U_VIRTEX7_LATENCY : entity work.add_flt_virtex7_latency
            port map (
                clk    => clk,
                ce     => en,
                a      => input1,
                b      => input2,
                result => output);
    end generate U_V7_LATENCY;


    -- print error if invalid add core specified
    U_UNDEFINED : if (core_name /= "stratix5_latency" and
                      core_name /= "stratix5_area" and
                      core_name /= "stratix5_speed" and
                      core_name /= "virtex7_speed" and
                      core_name /= "virtex7_latency" 
                      ) generate
        assert(false) report "Error: Undefined add core " & core_name & " in add_flt.vhd" severity error;
    end generate U_UNDEFINED;
    
end default;

