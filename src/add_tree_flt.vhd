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

-- Entity: add_tree_flt
-- Description : A pipelined single-precision floating-point adder tree with
-- a generic number of inputs. To use the add tree, the inputs must be
-- converted from an array into a std_logic_vector to avoid limitations of
-- arrays of unconstrained types.

-- INSTRUCTIONS: use add_tree_flt_latency in add_tree_flt_pkg to calculate
-- cycle latency, which determines when output is valid.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.flt_pkg.all;

-------------------------------------------------------------------------------
-- Generic Descriptions
-- num_inputs : The number of inputs in the adder tree
-- opt : A string defining the optimization type to use for the floating-point
--       cores.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Port Descriptions
-- clk : clock
-- rst : reset
-- en : enable (active high), '0' stalls the pipeline
-- inputs : The inputs to the adder tree
-- output : The sum of all inputs
-------------------------------------------------------------------------------

entity add_tree_flt is
    generic (
        num_inputs    : positive;
        add_core_name : string := "";
		width         : positive);
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        en     : in  std_logic;
        input  : in  std_logic_vector(num_inputs*width-1 downto 0);
        output : out std_logic_vector(width-1 downto 0));
end add_tree_flt;

architecture default of add_tree_flt is

    type input_array is array(integer range<>) of std_logic_vector(width-1 downto 0);

    -- calculates depth of the right subtree
    function getRightDepth(numInputs : natural)
        return natural is
        variable return_val : natural;
    begin
        if (numInputs = 0) then
            return_val := 0;
        else
            return_val := integer(ceil(log2(real(numInputs))));
        end if;

        return return_val;
    end getRightDepth;

    -- converts from input_array to std_logic_vector
    function vectorize(input        : input_array;
                       arraySize    : natural;
                       elementWidth : positive) return std_logic_vector is
        variable temp : std_logic_vector(arraySize*elementWidth-1 downto 0);
    begin
        for i in 0 to arraySize-1 loop
            temp((i+1)*elementWidth-1 downto i*elementWidth) := input(input'left+i);
        end loop;

        return temp;
    end function;

    -- converts from std_logic_vector to input_array
    function devectorize(input        : std_logic_vector;
                         arraySize    : natural;
                         elementWidth : positive) return input_array is
        variable temp : input_array(0 to arraySize-1);
    begin
        for i in 0 to arraySize-1 loop
            temp(i) := input((i+1)*elementWidth-1 downto i*elementWidth);
        end loop;

        return temp;
    end function;

    constant LEFT_TREE_INPUTS      : natural := num_inputs - num_inputs/2;
    constant RIGHT_TREE_INPUTS     : natural := num_inputs/2;
    constant LEFT_TREE_DEPTH       : natural := integer(ceil(log2(real(LEFT_TREE_INPUTS))));
    constant RIGHT_TREE_DEPTH      : natural := getRightDepth(RIGHT_TREE_INPUTS);
    constant TREE_DEPTH_DIFFERENCE : natural := LEFT_TREE_DEPTH-RIGHT_TREE_DEPTH;

    signal left_tree_out            : std_logic_vector(width-1 downto 0);
    signal right_tree_out           : std_logic_vector(width-1 downto 0);
    signal right_tree_out_unaligned : std_logic_vector(width-1 downto 0);

    signal inputs     : input_array(0 to num_inputs-1);
    signal left_temp  : std_logic_vector(LEFT_TREE_INPUTS*width-1 downto 0);
    signal right_temp : std_logic_vector(RIGHT_TREE_INPUTS*width-1 downto 0);
begin

    -- convert big input vector into array of data
    inputs <= devectorize(input, num_inputs, width);

    -- recursion base cases  
    U_END1 : if (num_inputs = 1) generate
        output <= inputs(0);
    end generate U_END1;

    U_END2 : if (num_inputs = 2) generate
        U_ADD : entity work.add_flt
            generic map (
                core_name => add_core_name)
            port map (
                clk    => clk,
                en     => en,
                input1 => inputs(0),
                input2 => inputs(1),
                output => output);
    end generate U_END2;

    -- recursion to create tree  
    U_RECURSE : if (num_inputs > 2) generate

        -- put left array inputs into a big vector
        left_temp <= vectorize(inputs(num_inputs/2 to num_inputs-1), LEFT_TREE_INPUTS, width);

        -- left adder sub tree. In the case of odd inputs, this tree gets one more
        -- than the right tree
        U_LEFT_TREE : entity work.add_tree_flt
            generic map (
                num_inputs    => LEFT_TREE_INPUTS,
                add_core_name => add_core_name,
				width         => width)
            port map (
                clk    => clk,
                rst    => rst,
                en     => en,
                input  => left_temp,
                output => left_tree_out);

        -- put right array inputs into a big vector
        right_temp <= vectorize(inputs(0 to num_inputs/2-1), RIGHT_TREE_INPUTS, width);

        -- right adder tree
        U_RIGHT_TREE : entity work.add_tree_flt
            generic map (
                num_inputs    => RIGHT_TREE_INPUTS,
                add_core_name => add_core_name,
				width         => width)
            port map (
                clk    => clk,
                rst    => rst,
                en     => en,
                input  => right_temp,
                output => right_tree_out_unaligned);

        -- if there are an odd number of inputs, we need to delay the right
        -- subtree by the difference in the depth of the left and right
        U_ALIGN_ODD : if num_inputs mod 2 /= 0 generate
            U_DELAY : entity work.delay
                generic map (
                    cycles => add_flt_latency(add_core_name)*TREE_DEPTH_DIFFERENCE,
                    width  => right_tree_out_unaligned'length,
                    init   => std_logic_vector(to_unsigned(0, right_tree_out_unaligned'length)))
                port map (
                    clk    => clk,
                    rst    => rst,
                    en     => en,
                    input  => right_tree_out_unaligned,
                    output => right_tree_out);
        end generate U_ALIGN_ODD;

        -- no alignment needed for even inputs
        U_ALIGN_EVEN : if num_inputs mod 2 = 0 generate
            right_tree_out <= right_tree_out_unaligned;
        end generate U_ALIGN_EVEN;

        -- add the two sub tree results
        U_ADD_TREES : entity work.add_flt
            generic map (
                core_name => add_core_name)
            port map (
                clk    => clk,
                en     => en,
                input1 => left_tree_out,
                input2 => right_tree_out,
                output => output);

    end generate U_RECURSE;
end default;

