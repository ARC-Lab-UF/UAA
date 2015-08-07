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

-- Yang Zheng
-- Greg Stitt
-- David Wilson
-- University of Florida

-- Description:
-- This file implements a testbench for the uaa entity.
-- The testbench provides numerous generics for controlling
-- the behavior of the simulation. See the description below. To test multiple
-- architectures, or different configurations of the same architecture,
-- instantiate this testbench multiple times within another testbench. For output,
-- the testbench will report the number of groups that had outputs that exceeded
-- both the acceptable percent difference of an estimated accurate result calculated
-- through double precision and the sequentially accumulated result. Each individual 
-- input group will report these differences in a double precision hex string.
--
-- Notes:
-- If uaa changes to support a different precision, this testbench will
-- require a few minor changes other than changing the width parameter. For example,
-- the replacement of single precision will change require using changing the 
-- instantiation done with float32 in the testbench and in the package file.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

use work.uaa_pkg.all;
use work.uaa_tb_pkg.all;
use work.flt_pkg.all;

library ieee_proposed;
use ieee_proposed.fixed_float_types.all;
use ieee_proposed.float_pkg.all;

------------------------------------------------------------------------------------------------
-- Port Description
-- test_name                : Specifies the name of the current test, which the
--                            testbench prints during the simulation.
-- test_for_arch            : Specifies whether the testbench is testing for architectural
--                            correctness by feeding the architectures '1's for inputs.
--                            Using '1's ensures the output is not affected by rounding and 
--                            keeps the order of additions equivalent to the sequential order.
--                            This test should not be asserted with test_for_error.
-- test_for_error           : Specifies whether the testbench is testing for error in the
--                            final result by feeding the architectures input values with 
--                            randomized exponent values. Use min_input_exp and max_input_exp 
--                            to limit the range of the input's exponents. This test should  
--                            not be asserted with test_for_arch.
-- arch                     : Specifies the type of architecture to use. All possible
--                            options are included in uaa_pkg.vhd
-- parallel_inputs          : The number of inputs provided in parallel as input. For
--                            example, if a design can provide 4 inputs every cycle,
--                            this should be 4 to maximize throughput.
-- add_core_name            : A string representing different optimizations for the
--                            actual adder core. See add_flt.vhd and flt_pkg.vhd for
--                            more information.
-- use_bram                 : Attempts to use bram when true, uses LUTs when false
-- FCBT_max_inputs          : Specifies the maximum number of inputs for the
--                            FCBT architecture. This generic is ignored for other
--                            architectures, which support any number of inputs.
-- total_groups             : Specifies the total number of groups to test.
-- min_group_size           : Specifies the minimum size of any group. If this value is
--                            not a multiple of parallel_inputs, the testbench will
--                            increase it to the nearest multiple.
-- max_group_size           : Specifies the maximum size of any group. If this value is
--                            not a multiple of parallel_inputs, the testbench will
--                            increase it to the nearest multiple.
-- min_input_exp            : The minimum random value used for an input's exponent.
--                            This parameter is only relevant when test_for_error is asserted
-- max_input_exp            : The maximum random values used for an input's exponent.
--                            This parameter is only relevant when test_for_error is asserted
-- input_delay_prob         : The probability that and input will be delayed (i.e. will
--                            not appear one cycle after the previous input.
-- min_input_delay          : If an input is delayed, this specifies the minimum random
--                            cycle delay.
-- max_input_delay          : If an input is delayed, this specifies the maximum random
--                            cycle delay.
-- group_delay_prob         : The probability that there will be a delay in between
--                            consecutive input groups.
-- min_group_delay          : If a group is delayed, this specifies the minimum random
--                            cycle delay.
-- max_group_delay          : If a group is delayed, this specifies the maximum random
--                            cycle delay.
-- hold_output_prob         : The probability during any cycle that hold_ouput will be
--                            asserted.
-- min_hold_output_delay    : If hold_output is asserted, this specifies the
--                            minimum random cycle delay before deassertion.
-- max_hold_output_delay    : If hold_output is asserted, this specifies the
--                            maximum random cycle delay before deassertion.
-- junk_input_prob          : The probability that a junk value will be used as input
--                            while accumulator is not ready (i.e. ready = '0').
-- acceptable_error_percent : Specifies acceptable percentage difference between the actual 
--                            output and an estimated correct output due to floating rounding. 
--                            Also, specifies acceptable percentage difference between the actual 
--                            output and a sequentially accumulated output due to assumption of 
--                            associativity.
-- print_status             : When asserted, simulation prints information that specifies
--                            the current status. Useful for long simulations.
-- start_group              : Use its falling_edge to indicate the beginning
--                            of a new group, and apply changes to parameter port signals
------------------------------------------------------------------------------------------------

entity uaa_tb is
    generic(
        test_name       : string    := "DEFAULT_TEST";
        test_for_arch   : boolean   := true;
        test_for_error  : boolean   := false;
        arch            : arch_type := UAA_DSA;
        parallel_inputs : positive  := 1;
        add_core_name   : string    := "stratix5_speed";
        use_bram        : boolean   := true;
        FCBT_max_inputs : positive  := 1;
        FCBT_obuf_size  : positive  := 1;
        total_groups    : positive  := 1);
    port(
        min_group_size : in positive := 1;
        max_group_size : in positive := 300;

        min_input_exp : in integer := 0;
        max_input_exp : in integer := 0;

        input_delay_prob : in real range 0.0 to 1.0 := 0.25;
        min_input_delay  : in natural               := 1;
        max_input_delay  : in natural               := 10;

        group_delay_prob : in real range 0.0 to 1.0 := 0.2;
        min_group_delay  : in natural               := 1;
        max_group_delay  : in natural               := 30;

        hold_output_prob      : in real range 0.0 to 1.0 := 0.3;
        min_hold_output_delay : in natural               := 1;
        max_hold_output_delay : in natural               := 200;

        junk_input_prob : in real range 0.0 to 1.0 := 0.05;

        acceptable_error_percent : in real := 0.000;  -- e.g., .002 = .2%

        print_status : in  boolean := false;
        done         : out std_logic;
        start_group  : out std_logic
        );
end uaa_tb;

architecture RANDOM_TB of uaa_tb is
    -------------------------------------------------------------
    -- Constants
    constant HALF_PERIOD  : time     := 5 ns;
    constant WIDTH        : positive := 32;
    constant C_JUNK_INPUT : std_logic_vector(width-1 downto 0) := x"55555555";

    -------------------------------------------------------------
    -- Input signals
    signal clk          : std_logic                                          := '0';
    signal rst          : std_logic                                          := '1';
    signal end_of_group : std_logic                                          := '0';
    signal valid_in     : std_logic                                          := '0';
    signal input        : std_logic_vector(parallel_inputs*width-1 downto 0) := (others => '0');
    signal hold_output  : std_logic                                          := '0';

    ------------------------------------------------------------
    -- Output signals
    signal valid_out : std_logic;
    signal output    : std_logic_vector(width-1 downto 0);
    signal ready     : std_logic;

    -------------------------------------------------------------
    -- Testbench signals
    type ARRAY_INT     is array(natural range<>) of integer;
    type ARRAY_FLOAT32 is array(natural range<>) of float32;
    type ARRAY_FLOAT64 is array(natural range<>) of float64;
    
    signal sim_done       : std_logic                           := '0';
    signal correct_output : ARRAY_FLOAT64(0 to total_groups-1)  := (others => to_float64(to_float(0)));
    signal seq_output     : ARRAY_FLOAT32(0 to total_groups-1)  := (others => to_float32(to_float(0)));

    -- used for displaying current group number
    signal in_group_num   : integer                             := 0;
    signal out_group_num  : integer                             := 0;
begin

    -- FCBT_max_input check
    process
    begin
        if (arch = UAA_FCBT) then
            while(sim_done = '0') loop
                assert(FCBT_max_inputs >= max_group_size) 
                report "ERROR: max_group_size cannot exceed FCBT_max_inputs for the FCBT architecture." severity error;
                wait until max_group_size'active for 1 ms;
            end loop;
        end if;
        wait;
    end process;
    
    -- Active test check
    process
    begin
        assert(test_for_arch xor test_for_error) 
        report "ERROR: Only one test can be active. Assert only test_for_arch or test_for_error" severity error;
      wait;
    end process;

    -- UUT
    U_UUT : entity work.uaa
        generic map (
            arch            => arch,
            width           => width,
            parallel_inputs => parallel_inputs,
            add_core_name   => add_core_name,
            use_bram        => use_bram,
            FCBT_max_inputs => FCBT_max_inputs,
            FCBT_obuf_size  => FCBT_obuf_size)
        port map (
            clk          => clk,
            rst          => rst,
            hold_output  => hold_output,
            ready        => ready,
            end_of_group => end_of_group,
            input        => input,
            output       => output,
            valid_in     => valid_in,
            valid_out    => valid_out
            );

    -- Stops the clock when the simulation has compared the UUT's outputs to the expected ones
    clk <= clk when sim_done = '1' else
           not clk after HALF_PERIOD;
    done <= sim_done;

    process
        variable s1, s2     : positive;  -- seed values
        variable group_size : ARRAY_INT(0 to total_groups-1);
        variable group_rem  : integer;

        variable use_junk_input                       : boolean;
        variable rand_input                           : std_logic_vector(width-1 downto 0);
        variable in_sum_float64, rand_input_float64   : float64;

        variable in_sum_float32, rand_input_float32   : float32;
        variable parallel_input                       : std_logic_vector(parallel_inputs*width-1 downto 0);
    begin
        -- Reset sequence
        rst         <= '1';
        start_group <= '1';
        for i in 0 to 3 loop
            wait until rising_edge(clk);
        end loop;
        start_group <= '0';
        rst         <= '0';
        
        -- Idle time
        for i in 0 to add_flt_latency(add_core_name) loop
            wait until rising_edge(clk);
        end loop;

        -- create random group sizes for all groups
        for i in 0 to total_groups-1 loop
            randomInt(s1, s2, min_group_size, max_group_size, group_size(i));

            -- round group size up to next multiple of parallel_inputs
            group_rem := group_size(i) mod parallel_inputs;
            if (group_rem > 0) then
                group_size(i) := group_size(i) + parallel_inputs -group_rem;
            end if;

            assert(group_size(i) mod parallel_inputs = 0)
            report "ERROR: The group size must be a multiple of parallel_inputs for the testbench to work correctly." severity error;

            -- Assign input values
            for j in 1 to group_size(i)/parallel_inputs loop

                valid_in     <= '0';
                end_of_group <= '0';

                -- randomly delay consecutive inputs
                randDelay(s1, s2, clk, input_delay_prob,
                          min_input_delay, max_input_delay);

                -- give ready time to change
                wait for HALF_PERIOD;

                -- test junk inputs while accumulator is not ready
                while (ready = '0') loop

                    -- randomly decide to inject junk values while the
                    -- accumulator is not ready
                    randDecision(s1, s2, junk_input_prob, use_junk_input);

                    if (use_junk_input) then

                        for k in 0 to parallel_inputs-1 loop
                            parallel_input(width*(k+1)-1 downto width*k) := C_JUNK_INPUT;
                        end loop;

                        input        <= parallel_input;
                        valid_in     <= '1';
                        end_of_group <= '1';
                    else
                        valid_in     <= '0';
                        end_of_group <= '0';
                    end if;

                    wait until rising_edge(clk);
                    wait for HALF_PERIOD;
                end loop;

                -- create random input or uses '1's depending on test
                in_sum_float64  := to_float64(to_float(0));
                in_sum_float32  := to_float32(to_float(0));
                for k in 0 to parallel_inputs-1 loop
                    randomFloat(s1, s2, min_input_exp, max_input_exp, rand_input, rand_input_float32, rand_input_float64);
                    if (test_for_error) then
                      parallel_input(width*(k+1)-1 downto width*k) := rand_input;
                      in_sum_float64  := in_sum_float64 + rand_input_float64;
                      in_sum_float32  := in_sum_float32 + rand_input_float32;
                    else
                      parallel_input(width*(k+1)-1 downto width*k) := to_slv(to_float32(to_float(1)));
                      in_sum_float64  := in_sum_float64 + to_float64(to_float(1));
                      in_sum_float32  := in_sum_float32 + to_float32(to_float(1));
                    end if;
                end loop;
                
                -- record running sum of the sequential floating point accumulation and of the estimated accurate result
                -- in double precision
                correct_output(i) <= correct_output(i) + in_sum_float64;
                seq_output(i)     <= seq_output(i)     + in_sum_float32;
                
                input             <= parallel_input;
                valid_in          <= '1';

                -- check for end of group
                if (j = group_size(i)/parallel_inputs) then
                    end_of_group <= '1';
                    start_group  <= '1';
                else
                    end_of_group <= '0';
                end if;

                wait until rising_edge(clk);
            end loop;

            valid_in     <= '0';
            end_of_group <= '0';

            -- random delay between groups
            randDelay(s1, s2, clk, group_delay_prob,
                      min_group_delay, max_group_delay);
            in_group_num <= i;
            start_group  <= '0';
            if (print_status) then
                report "Done with group " & integer'image(i) & ".";
            end if;
        end loop;

        wait;
    end process;

    -- randomly varies the hold_output input over time
    process
        variable s1, s2      : positive;  -- seed values
        variable should_hold : boolean;

    begin
        while (sim_done = '0') loop
            hold_output <= '0';
            wait until rising_edge(clk);

            randDecision(s1, s2, hold_output_prob, should_hold);
            if (should_hold) then
                hold_output <= '1';
                randDelay(s1, s2, clk, 1.0, min_hold_output_delay, max_hold_output_delay);
            end if;
        end loop;
    end process;

    -- Check and report the wrong results
    process
      variable group_count  : integer := 0;
      variable accuracy_cnt : integer := 0;
      variable seq_cnt      : integer := 0;

      variable line_buffer  : line;
      variable start_time   : time;
      variable end_time     : time;
      file output_file      : text open WRITE_MODE is "output.csv";
    begin
    
      -- Start checking after reset sequence
      for i in 0 to 3 loop
          wait until rising_edge(clk);
      end loop;
      --start_time := now;

      while sim_done = '0' loop

        -- check for valid output at falling clk edge to ensure stabilized output
        wait for HALF_PERIOD;
        while (valid_out = '0') loop
          wait until valid_out = '1';
          wait for HALF_PERIOD;
        end loop;
        
        --report "Testing group " & integer'image(group_count) & " HERE!" severity note;
        
        -- Check actual output to estimated accurate result
        if (isAcceptableError(to_float64(to_float(output)),
                              correct_output(group_count),
                              to_float64(to_float(acceptable_error_percent))) = false) then
            report("NOTE: " & integer'image(group_count) & " group's output is greater than the acceptable error parameter. " & 
                    "Output Difference = "  & to_hstring(to_float64(to_float(output))-correct_output(group_count))
            )
            severity note;
            accuracy_cnt := accuracy_cnt + 1;
        end if;

        -- Check actual output to sequential accumulation result
        if (isAcceptableError(to_float64(to_float(output)),
                              to_float64(seq_output(group_count)),
                              to_float64(to_float(acceptable_error_percent))) = false) then
            report("NOTE: " & integer'image(group_count) & " group's output is not equal to the sequential output. " & 
                    "Output Difference = "  & to_hstring(to_float64(to_float(output))-to_float64(seq_output(group_count)))
            )
            severity note;
            seq_cnt := seq_cnt + 1;

        end if;

        group_count   := group_count + 1;
        out_group_num <= group_count;
        
        
        -- Check for end condition
        if (group_count = total_groups) then
          
          report "TEST " & test_name & " FINISHED. " &
                  "Groups with unacceptable accuracy: " & integer'image(accuracy_cnt) & ", " &
                  "Groups with unacceptable IEEE754 difference: " & integer'image(seq_cnt);
                  
          end_time := now;
          
          -- write parameters to csv
          write(line_buffer,
            integer'image(total_groups)     & "," &
            integer'image(parallel_inputs)  & "," &
            arch_type'image(arch)           & "," &
            add_core_name                   & "," &
            integer'image(max_group_size)   & "," &
            time'image(end_time-start_time) & "," &
            integer'image(accuracy_cnt)     & "," &
            integer'image(seq_cnt)
          );
          writeline(output_file, line_buffer);
    
          sim_done <= '1';
          wait;
        end if;
    
        -- If hold_output is asserted, then the next "valid" valid_out will be in the clock
        -- cycle after hold_output is deasserted.
        -- Otherwise, wait a clk cycle in the event that valid_out remains asserted for
        -- two separate valid outputs.
        if (hold_output = '1') then
            wait until hold_output = '0';
            wait until rising_edge(clk);
        else
            wait until rising_edge(clk);
        end if;

      end loop;
    end process;
end RANDOM_TB;

