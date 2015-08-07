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
-- This entity implements a pipelined, floating-point accumulator with generics
-- that select between different accumulator architectures, different adder
-- architectures, any number of inputs per cycle, and whether or not to
-- use block. Valid architectures are listed in uaa_pkg.vhd and are
-- described in the corresponding paper.

-- Notes:
-- See README before instantiating this entity. uaa requires
-- an existing adder core, a mapping onto an adder wrapper (add_flt), and
-- adder latencies (add_flt_pkg.vhd).

-- Used entities:
-- add_tree_flt
-- delay
-- dsa, fcbt, sga

library ieee;
use ieee.std_logic_1164.all;

use work.uaa_pkg.all;
use work.add_tree_flt_pkg.all;

-------------------------------------------------------------------------------
-- Generics Description
-- arch             : Specifies the type of architecture to use. All possible
--                    options are included in uaa_pkg.vhd
-- width            : The width of the input and output in bits (e.g., 32 bits
--                    for single precision, 64 for double)
-- parallel_inputs  : The number of inputs provided in parallel as input. For
--                    example, if a design can provide 4 inputs every cycle,
--                    this should be 4 to maximize throughput. 
-- add_core_name    : A string representing different optimizations for the
--                    actual adder core. See add_flt.vhd and flt_pkg.vhd for
--                    more information.
-- use_bram         : attempts to use bram when true, uses LUTs or FFs when
--                    false
-- FCBT_max_inputs  : Specifies the maximum number of inputs for the
--                    FCBT architecture. This generic is ignored for other
--                    architectures, which support any number of inputs.
-- FCBT_obuf_size   : Specifies the size of the output buffer for the
--                    FCBT architecture. This generic is ignored for other
--                    architectures, which support any number of inputs.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Port Description:
-- clk          : clock input
-- rst          : reset input (asynchronous, active high)
-- hold_output  : The user can assert this signal to prevent the entity from
--                continuing past a valid output. When hold_output is not
--                asserted, the output is valid for only a single cycle.
--                This signal makes it possible to stall the entity if
--                downstream components can't receive data (active high)
-- ready        : The entity asserts this signal when it is ready to accept
--                new inputs. If not, asserted, external components must hold
--                the current input or it will be lost (active high)
-- end_of_group : User should be assert on the same cycle as the last input in a
--                group (active high)
-- input        : Provides parallel_inputs number of width-bit inputs 
-- output       : Accumulated output
-- valid_in     : User should assert when input is valid and ready is
--                asserted (active high)
-- valid_out    : Entity asserts when the output from the dsa is valid. Unless
--                the user asserts hold_output, the entity only asserts
--                valid_out is only asserted for one cycle. (active high)
-------------------------------------------------------------------------------

entity uaa is
    generic (
        arch            : arch_type := UAA_SGA;
        width           : positive  := 32;
        parallel_inputs : positive  := 1;
        add_core_name   : string    := "stratix5_speed";
        use_bram        : boolean   := true;
        FCBT_max_inputs : positive  := 1;
        FCBT_obuf_size  : positive  := 1
        );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        hold_output  : in  std_logic;
        ready        : out std_logic;
        end_of_group : in  std_logic;
        input        : in  std_logic_vector(width*parallel_inputs-1 downto 0);
        output       : out std_logic_vector(width-1 downto 0);
        valid_in     : in  std_logic;
        valid_out    : out std_logic
        );
end uaa;

architecture DEFAULT of uaa is

    signal accum_input        : std_logic_vector(width-1 downto 0);
    signal accum_valid_in     : std_logic;
    signal accum_end_of_group : std_logic;
    signal ready_s            : std_logic;
begin

    -- use an adder tree to reduce parallel_inputs per cycle to 1 value
    ADD_TREE : if (parallel_inputs > 1) generate

        -- the add tree only stalls when ready isn't asserted. This differs
        -- from the accumulator. As a result, invalid outputs from the add tree
        -- will likely be interleaved with valid outputs. The accumulator
        -- simply ignores the invalid inputs, so there is no reason to stall
        -- the add tree (unless ready is not asserted).

        U_ADD_TREE : entity work.add_tree_flt
            generic map (
                num_inputs    => parallel_inputs,
                add_core_name => add_core_name,
                width         => width)
            port map (
                clk    => clk,
                rst    => rst,
                en     => ready_s,
                input  => input,
                output => accum_input);

        -- delay valid_in until output leaves add tree
        U_DELAY_VALID_IN : entity work.delay
            generic map (
                width  => 1,
                cycles => add_tree_flt_latency(parallel_inputs, add_core_name),
                init   => "0")
            port map (
                clk       => clk,
                rst       => rst,
                en        => ready_s,
                input(0)  => valid_in,
                output(0) => accum_valid_in);

        -- delay end_of_group until output leaves add tree
        U_DELAY_END_OF_GROUP : entity work.delay
            generic map (
                width  => 1,
                cycles => add_tree_flt_latency(parallel_inputs, add_core_name),
                init   => "0")
            port map (
                clk       => clk,
                rst       => rst,
                en        => ready_s,
                input(0)  => end_of_group,
                output(0) => accum_end_of_group);

    end generate ADD_TREE;

    -- if there is only one input per cycle, forward it to the accumulator
    NO_ADD_TREE : if (parallel_inputs = 1) generate
        accum_input        <= input;
        accum_valid_in     <= valid_in;
        accum_end_of_group <= end_of_group;
    end generate NO_ADD_TREE;

    ready <= ready_s;

    -- instantiate a DSA architecture when requested
    DSA : if (arch = UAA_DSA) generate
        U_DSA : entity work.dsa
            generic map (
                width         => width,
                add_core_name => add_core_name,
                use_bram      => use_bram)
            port map (
                clk          => clk,
                rst          => rst,
                hold_output  => hold_output,
                ready        => ready_s,
                end_of_group => accum_end_of_group,
                input        => accum_input,
                output       => output,
                valid_in     => accum_valid_in,
                valid_out    => valid_out
                );
    end generate DSA;

    -- instantiate a FCBT architecture when requested
    FCBT : if (arch = UAA_FCBT) generate
        U_FCBT : entity work.fcbt
            generic map (
                width           => width,
                add_core_name   => add_core_name,
                use_bram        => use_bram,
                FCBT_max_inputs => FCBT_max_inputs,
                FCBT_obuf_size  => FCBT_obuf_size)
            port map(
                clk          => clk,
                rst          => rst,
                hold_output  => hold_output,
                ready        => ready_s,
                end_of_group => accum_end_of_group,
                input        => accum_input,
                output       => output,
                valid_in     => accum_valid_in,
                valid_out    => valid_out
                );
    end generate FCBT;

    -- instantiate a SGA architecture when requested
    SGA : if (arch = UAA_SGA) generate
        U_SGA : entity work.sga
            generic map (
                width         => width,
                add_core_name => add_core_name,
                use_bram      => use_bram)
            port map(
                clk          => clk,
                rst          => rst,
                hold_output  => hold_output,
                ready        => ready_s,
                end_of_group => accum_end_of_group,
                input        => accum_input,
                output       => output,
                valid_in     => accum_valid_in,
                valid_out    => valid_out
                );
    end generate SGA;


    OTHER : if (arch /= UAA_DSA and arch /= UAA_FCBT and arch /= UAA_SGA) generate
        assert(false) report "Error: invalid architecture specified in uaa." severity error;
    end generate OTHER;

end DEFAULT;

