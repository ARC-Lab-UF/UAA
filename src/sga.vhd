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
-- The sga entity implements a simple group adder similar to the architecture
-- described in the paper "Design and implementation of an FPGA-based high-
-- performance improved vector-reduction method" by Song et al. (2011)

-- Used entities:
-- add_wrapper

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.math_custom.all;
use work.flt_pkg.all;

-------------------------------------------------------------------------------
-- Generics Description
-- width             : The width of the input and output in bits
-- add_core_name     : A string representing different optimizations for the
--                     actual adder core. See add_flt.vhd and flt_pkg.vhd for
--                     more information.
-- use_bram          : uses bram when true, uses LUTs or FFs when false
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Port Description:
-- clk          : clock input
-- rst          : reset input (asynchronous, active high)
-- hold_output  : When asserted, this signal prevents the entity from
--                continuing past a valid output. When not asserted, the
--                output is valid for only a single cycle. This signal
--                makes it possible to stall the sga if downstream
--                components cannot receive another input  (active high)
-- ready        : when asserted, the sga is ready to accept new inputs. If not
--                asserted, external components must hold the current input or
--                it will be lost (active high)
-- end_of_group : should be asserted on the same cycle as the last input in a
--                group (active high)
-- input        : sga input
-- output       : sga output
-- valid_in     : assert when the input to the sga is valid and ready is
--                asserted (active high)
-- valid_out    : asserted when the output from the sga is valid. Unless
--                hold_output is asserted, valid_out is only asserted for
--                one cycle. (active high)
-------------------------------------------------------------------------------

entity sga is
    generic (
        width         : positive := 32;
        add_core_name : string   := "speed";
        use_bram      : boolean  := true);
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        hold_output  : in  std_logic;   -- '1' keeps outputs from disappearing
        ready        : out std_logic;   -- '1' when sga can accept input
        end_of_group : in  std_logic;   -- specifies last input in group

        input     : in  std_logic_vector(width-1 downto 0);
        output    : out std_logic_vector(width-1 downto 0);
        valid_in  : in  std_logic;
        valid_out : out std_logic
        );
end sga;

architecture RTL of sga is
    type buf_array is array (natural range <>) of std_logic_vector(width downto 0);

    --control signals
    signal is_coalescing     : std_logic;
    signal stall             : std_logic;
    signal all_buffers_empty : std_logic;
    signal ready_int         : std_logic;

    --ibuf signals
    signal ibuf_sel             : std_logic;
    signal ibuf_rd              : std_logic;
    signal ibuf_out             : buf_array(1 downto 0);
    signal ibuf_ready           : std_logic;
    signal ibuf_ready_singleton : std_logic;

    --buf signals
    signal buf_sel      : std_logic;
    signal buf_rd       : std_logic;
    signal buf_out      : buf_array(1 downto 0);
    signal buf0_out     : buf_array(1 downto 0);
    signal buf0_rd_addr : std_logic;
    signal buf0_wr_addr : std_logic;
    signal buf_ready    : std_logic;

    --obuf signals
    signal obuf_wr       : std_logic;
    signal valid_out_int : std_logic;

    --adder signals
    signal add_in1       : std_logic_vector(width-1 downto 0);
    signal add_in2       : std_logic_vector(width-1 downto 0);
    signal add_out       : std_logic_vector(width-1 downto 0);
    signal add_en        : std_logic;
    signal add_valid_in  : std_logic;
    signal add_valid_out : std_logic;
    signal add_count     : std_logic_vector(bitsNeeded(add_flt_latency(add_core_name))-1 downto 0);
    
begin

------------------------------------------------
-- IBUF

    -- ibuf is ready to add when both ready bits of its output registers are asserted
    ibuf_ready <= ibuf_out(0)(width) and ibuf_out(1)(width);

    -- ibuf is ready to add single element when one ready bit is asserted and no more
    -- elements are arriving
    ibuf_ready_singleton <= '1' when (ibuf_out(0)(width) = '1' or ibuf_out(1)(width) = '1') and
                            is_coalescing = '1' else
                            '0';

    -- create ibuf
    process(clk, rst)
    begin
        if (rst = '1') then
            ibuf_sel <= '0';
            ibuf_out <= (others => (others => '0'));
        elsif (rising_edge(clk)) then
            if (stall = '0') then

                -- zero out previous elements when reading
                if (ibuf_rd = '1') then
                    ibuf_out <= (others => (others => '0'));
                end if;

                -- write to an ibuf register any time there is 
                -- valid data
                if (valid_in = '1' and ready_int = '1') then
                    if (ibuf_sel = '0') then
                        ibuf_out(0) <= '1' & input;
                    else
                        ibuf_out(1) <= '1' & input;
                    end if;

                                        -- switch between writing to ibuf0 and ibuf1
                    ibuf_sel <= not ibuf_sel;
                end if;
            end if;
        end if;
    end process;

------------------------------------------------
-- BUF

    -- buf is ready to add when buf0 and buf1 ready bits are asserted
    buf_ready <= buf_out(0)(width) and buf_out(1)(width);

    -- create buf. Buf0 is implemented as two-register fifo to handle 
    -- when both ibuf and buf have two elements and two writes in the 
    -- same cycle.
    process(clk, rst)
    begin
        if (rst = '1') then
            buf0_rd_addr <= '0';
            buf0_wr_addr <= '0';
            buf0_out     <= (others => (others => '0'));
            buf_sel      <= '0';
            buf_out(1)   <= (others => '0');
        elsif (rising_edge(clk)) then
            if (stall = '0') then

                -- zero out previous elements when reading
                if (buf_rd = '1') then

                                        -- zero out only registers used in read
                    if (buf0_rd_addr = '0') then
                        buf0_out(0) <= (others => '0');
                    else
                        buf0_out(1) <= (others => '0');
                    end if;
                    buf_out(1) <= (others => '0');

                                        -- pop the buf0 fifo by changing rd_addr
                    buf0_rd_addr <= not buf0_rd_addr;
                end if;

                -- write to buf any time there is valid adder output
                -- that isn't the last element in the group
                if (add_valid_out = '1' and obuf_wr = '0') then

                                        -- switch between writing to buf0 and buf1
                    buf_sel <= not buf_sel;
                    if (buf_sel = '1') then
                        buf_out(1) <= '1' & add_out;
                    else

                                        -- push element into buf0 fifo
                        if (buf0_wr_addr = '0') then
                            buf0_out(0) <= '1' & add_out;
                        else
                            buf0_out(1) <= '1' & add_out;
                        end if;
                        buf0_wr_addr <= not buf0_wr_addr;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- multiplexer for buf0 output as a fifo
    buf_out(0) <= buf0_out(0) when buf0_rd_addr <= '0' else buf0_out(1);

-------------------------------------------------
-- Control logic

    -- determines adder scheduling
    process(ibuf_ready, buf_ready, ibuf_ready_singleton)
    begin
        add_valid_in <= '0';
        ibuf_rd      <= '0';
        buf_rd       <= '0';

        -- add using inputs from ibuf when ibuf is ready
        if(ibuf_ready = '1') then
            add_valid_in <= '1';
            ibuf_rd      <= '1';

        -- add using inputs from buf when buf is ready
        elsif(buf_ready = '1') then
            add_valid_in <= '1';
            buf_rd       <= '1';

        -- add using inputs from ibuf when ibuf has only one element and no more elements are arriving
        elsif (ibuf_ready_singleton = '1') then
            add_valid_in <= '1';
            ibuf_rd      <= '1';
        end if;
    end process;

    -- buffers are empty if none of the registers have their ready bits asserted
    all_buffers_empty <= '1' when buf0_out(0)(width) = '0' and buf0_out(1)(width) = '0' and buf_out(1)(width) = '0' and
                         ibuf_out(0)(width) = '0' and ibuf_out(1)(width) = '0' else
                         '0';

    -- inputs are accepted when the architecture is not stalling or is coalescing the final sum of a group
    ready_int <= '1' when stall = '0' and is_coalescing = '0' else '0';
    ready     <= ready_int;

    -- stall the architecture when an output is being held and another final sum has been computed
    stall <= '1' when (obuf_wr = '1' and valid_out_int = '1' and hold_output = '1') else '0';

    -- indicates if the group's elements are being coalesced into one value
    process(clk, rst)
    begin
        if (rst = '1') then
            is_coalescing <= '0';
            
        elsif (rising_edge(clk)) then
            if (stall = '0') then

                -- coalescing begins when the last element has arrived
                if (valid_in = '1' and ready_int = '1' and end_of_group = '1') then
                    is_coalescing <= '1';

                -- coalescing ends when the final sum has been computed
                elsif (is_coalescing = '1' and obuf_wr = '1') then
                    is_coalescing <= '0';
                end if;
            end if;
        end if;
    end process;

------------------------------------------------
-- OBUF
    -- the obuf is written to when the buffers are empty
    -- and the adder output has the final sum
    obuf_wr <= '1' when (unsigned(add_count) = 1 and
                         all_buffers_empty = '1' and
                         add_valid_out = '1' and
                         is_coalescing = '1') else 
               '0';

    -- create obuf
    process(clk, rst)
    begin
        if (rst = '1') then
            output        <= (others => '0');
            valid_out_int <= '0';
        elsif (rising_edge(clk)) then
            if (stall = '0') then

                -- only deassert valid_out when hold_output is deasserted
                if (hold_output = '0') then
                    valid_out_int <= '0';
                end if;

                -- the final sum from adder is output when no elements remain in adders
                -- and buffers, and no output is being held with hold_output asserted
                if (obuf_wr = '1' and (hold_output = '0' or valid_out_int = '0')) then
                    output        <= add_out;
                    valid_out_int <= '1';
                end if;
            end if;
        end if;
    end process;
    valid_out <= valid_out_int;

------------------------------------------------
-- OBUF

    -- enable adder when the architecture is not stalling
    add_en <= not stall;

    -- multiplexer for 1st adder input
    add_in1 <= ibuf_out(0)(width-1 downto 0) when ibuf_rd = '1' else
               buf_out(0)(width-1 downto 0);

    -- multiplexer for 2nd adder input
    add_in2 <= ibuf_out(1)(width-1 downto 0) when ibuf_rd = '1' else
               buf_out(1)(width-1 downto 0);

    
    U_ADD : entity work.add_wrapper
        generic map (core_name => add_core_name,
                     width         => width)
        port map (clk       => clk,
                  rst       => rst,
                  en        => add_en,
                  input1    => add_in1,
                  input2    => add_in2,
                  output    => add_out,
                  valid_in  => add_valid_in,
                  valid_out => add_valid_out,
                  count     => add_count);
end RTL;

