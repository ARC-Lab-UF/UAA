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
-- David Wilson
-- University of Florida

-- Description:
-- The dsa entity implements a dual-strided adder similar to the architecture
-- described in the paper "High-Performance Reduction Circuits Using Deeply 
-- Pipelined Operators on FPGAs" by Ling Zhuo, G.R. Morris and V.K. Prasanna (2007)

-- Used entities:
-- fifo, dsa_ctrl, add_wrapper


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.math_custom.all;
use work.flt_pkg.all;
use work.dsa_pkg.all;

-------------------------------------------------------------------------------
-- Generics Description
-- width             : The width of the input and output in bits
-- add_core_name           : A string representing different optimizations for the
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
--                makes it possible to stall the dsa if downstream
--                components cannot receive another input  (active high)
-- ready        : when asserted, the dsa is ready to accept new inputs. If not
--                asserted, external components must hold the current input or
--                it will be lost (active high)
-- end_of_group : should be asserted on the same cycle as the last input in a
--                group (active high)
-- input        : dsa input
-- output       : dsa output
-- valid_in     : assert when the input to the dsa is valid and ready is
--                asserted (active high)
-- valid_out    : asserted when the output from the dsa is valid. Unless
--                hold_output is asserted, valid_out is only asserted for
--                one cycle. (active high)
-------------------------------------------------------------------------------

entity dsa is
    generic (
        width         : positive := 32;
        add_core_name : string   := "speed";
        use_bram      : boolean  := true);
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        hold_output  : in  std_logic;   -- '1' keeps outputs from disappearing
        ready        : out std_logic;   -- '1' when dsa can accept input
        end_of_group : in  std_logic;   -- specifies last input in group

        input     : in  std_logic_vector(width-1 downto 0);
        output    : out std_logic_vector(width-1 downto 0);
        valid_in  : in  std_logic;
        valid_out : out std_logic
        );
end dsa;

architecture RTL of dsa is

    constant ADD_LATENCY  : natural := add_flt_latency(add_core_name);
    constant BUFFER_DEPTH : natural := ADD_LATENCY;

    type data_array is array(natural range <>) of std_logic_vector(width-1 downto 0);
    type ibuf_array is array(natural range <>) of std_logic_vector(width downto 0);
    type add_count_array is array(natural range <>) of std_logic_vector(bitsNeeded(ADD_LATENCY)-1 downto 0);
    type sel_array is array(natural range <>) of std_logic_vector(1 downto 0);

    -- adder signals
    signal add_in1       : data_array(1 downto 0);
    signal add_in2       : data_array(1 downto 0);
    signal add_in1_sel   : std_logic_vector(1 downto 0);
    signal add_in2_sel   : sel_array(1 downto 0);
    signal add_out       : data_array(1 downto 0);
    signal add_en        : std_logic_vector(1 downto 0);
    signal add_valid_in  : std_logic_vector(1 downto 0);
    signal add_valid_out : std_logic_vector(1 downto 0);
    signal add_count     : add_count_array(1 downto 0);

    -- ibuf signals
    signal ibuf_in           : ibuf_array(1 downto 0);
    signal ibuf_out          : data_array(1 downto 0);
    signal ibuf_out_temp     : ibuf_array(1 downto 0);
    signal ibuf_rd           : std_logic;
    signal ibuf_wr           : std_logic_vector(1 downto 0);
    signal ibuf_empty        : std_logic_vector(1 downto 0);
    signal ibuf_full         : std_logic_vector(1 downto 0);
    signal ibuf_end_of_group : std_logic;
    signal ibuf_next         : std_logic;
    signal ibuf_wr_count     : integer range 0 to ADD_LATENCY*2;

    -- obuf signals
    signal obuf_out   : data_array(1 downto 0);
    signal obuf_empty : std_logic_vector(1 downto 0);
    signal obuf_rd    : std_logic_vector(1 downto 0);
    signal obuf_wr    : std_logic_vector(1 downto 0);

    -- specifies index of adder that is procesing the earliest group
    signal early_ctrl_id : unsigned(0 downto 0);

    -- specifies which controller currently has access to the ibuf
    signal ibuf_ctrl_id : unsigned(0 downto 0);

    signal ctrl_done         : std_logic_vector(1 downto 0);
    signal ctrl_ibuf_access  : std_logic_vector(1 downto 0);
    signal ctrl_earliest     : std_logic_vector(1 downto 0);
    signal ctrl_ibuf_rd      : std_logic_vector(1 downto 0);
--    signal ctrl_coalescing   : std_logic_vector(1 downto 0);
    signal ctrl_steady       : std_logic_vector(1 downto 0);
    signal ctrl_ibuf_give_up : std_logic_vector(1 downto 0);

    constant C_ZERO : std_logic_vector(width-1 downto 0) := (others => '0');

begin

    -- assign the output from the adder handling the earliest group
    output    <= obuf_out(to_integer(early_ctrl_id));
    valid_out <= ctrl_done(to_integer(early_ctrl_id));

    -- the DSA is ready for new inputs anytime the ibufs aren't empty
    ready <= not (ibuf_full(0) and ibuf_full(1));

    -- determine which controller has access to ibuf
    process(clk, rst)
    begin
        if (rst = '1') then
            -- initially give acces to controller 0
            ibuf_ctrl_id <= to_unsigned(0, 1);

        elsif (rising_edge(clk)) then

            -- if the current ibuf controller gives up access, switch access
            -- to the other controller
            if (ctrl_ibuf_give_up(to_integer(ibuf_ctrl_id)) = '1') then
                ibuf_ctrl_id <= ibuf_ctrl_id + 1;
            end if;
        end if;
    end process;

    -- give/take access to ibuf for each controller
    ctrl_ibuf_access(0) <= not ibuf_ctrl_id(0);
    ctrl_ibuf_access(1) <= ibuf_ctrl_id(0);

    -- tell each controller if it is handling the earliest group. This will
    -- prevent a controller from finishing until all earlier groups are done.
    ctrl_earliest(0) <= not early_ctrl_id(0);
    ctrl_earliest(1) <= early_ctrl_id(0);

    -- specify which controller is processing the earliest group
    process(clk, rst)
    begin
        if (rst = '1') then
            -- controller 0 always handles the first group
            early_ctrl_id <= to_unsigned(0, 1);
        elsif (rising_edge(clk)) then
            -- update the earliest controller each time the current earliest finishes
            if (ctrl_done(to_integer(early_ctrl_id)) = '1') then
                early_ctrl_id <= early_ctrl_id + 1;
            end if;
        end if;
    end process;

    ------------------------------------------------
    -- IBUF

    -- combine end_of_group and the input so controller knows if data leaving
    -- ibuf is the end of a group
    ibuf_in(0) <= end_of_group & input;
    -- force a zero into ibuf1 when a group ends in ibuf0
--    ibuf_in(1) <= end_of_group & input;
    ibuf_in(1) <= end_of_group & input when not(end_of_group = '1' and ibuf_next = '0') else
                  end_of_group & C_ZERO;
    ibuf_rd <= ctrl_ibuf_rd(0) when ctrl_ibuf_access(0) = '1' else ctrl_ibuf_rd(1);

    -- write to each buffer any time the buffer isn't full and it is that
    -- buffers turn
    ibuf_wr(0) <= '1' when valid_in = '1' and ibuf_full(0) = '0' and ibuf_next = '0' else '0';

    -- ibuf1 has to write everytime there is the end of a group otherwise
    -- multiple groups can become misaligned if the size is odd. For example, there
    -- could be an element from group3 on the ibuf0 output and group2 on the
    -- ibuf1 output
    ibuf_wr(1) <= '1' when valid_in = '1' and ibuf_full(1) = '0' and ibuf_next = '1' else
                  '1' when end_of_group = '1' and ibuf_wr(0) = '1' else
                  '1' when valid_in = '1' and ibuf_wr_count = 2*ADD_LATENCY else
                  '0';

    -- determine which ibuf to write to next
    process(clk, rst)
    begin
        if (rst = '1') then
            ibuf_next <= '0';
            ibuf_wr_count  <= 0;
        elsif (rising_edge(clk)) then

            -- if valid write
            if (ibuf_full(to_integer(unsigned'(""&ibuf_next))) = '0' and valid_in = '1') then

                if (ibuf_wr_count = 2*ADD_LATENCY) then
                    -- if all the inputs for the fill state have already
                    -- arrived, force all future writes into ibuf(0)
                    ibuf_next <= '0';
                else
                    -- switch ibufs for next write
                    ibuf_next <= not ibuf_next;
                    ibuf_wr_count  <= ibuf_wr_count + 1;
                end if;

                if (end_of_group = '1') then
                    -- if this is the end of the group, the next ibuf should also
                    -- be 0 to ensure every group starts in ibuf(0)   
                    ibuf_next <= '0';
                    ibuf_wr_count  <= 0;
                end if;
            end if;
        end if;
    end process;

    U_IBUF0 : entity work.fifo
        generic map (width             => width+1,
                     depth             => BUFFER_DEPTH,
                     use_bram          => use_bram,
                     same_cycle_output => true)
        port map (clk    => clk,
                  rst    => rst,
                  rd     => ibuf_rd,
                  wr     => ibuf_wr(0),
                  empty  => ibuf_empty(0),
                  full   => ibuf_full(0),
                  input  => ibuf_in(0),
                  output => ibuf_out_temp(0));

    U_IBUF1 : entity work.fifo
        generic map (width             => width+1,
                     depth             => BUFFER_DEPTH,
                     use_bram          => use_bram,
                     same_cycle_output => true)
        port map (clk    => clk,
                  rst    => rst,
                  rd     => ibuf_rd,
                  wr     => ibuf_wr(1),
                  empty  => ibuf_empty(1),
                  full   => ibuf_full(1),
                  input  => ibuf_in(1),
                  output => ibuf_out_temp(1));

    -- break up ibuf outputs into end_of_group flag and data to add
    -- Note: these may be uninitialized until the first rising clock edge when
    -- using block RAM
    -- This has to verify that that ibuf isn't empty, otherwise an old value
    -- can erroneously trigger and end of group
    ibuf_end_of_group <= (ibuf_out_temp(0)(width) and not ibuf_empty(0)) or
                         (ibuf_out_temp(1)(width) and not ibuf_empty(1));
    ibuf_out(0) <= ibuf_out_temp(0)(width-1 downto 0);
    ibuf_out(1) <= ibuf_out_temp(1)(width-1 downto 0);

    -- create obufs
    process(clk, rst)
    begin
        if (rst = '1') then
            obuf_out   <= (others => (others => '0'));
            obuf_empty <= (others => '1');
        elsif (rising_edge(clk)) then
            for i in 0 to 1 loop
                -- if obuf is read, it no longer has valid data
                if (obuf_rd(i) = '1') then
                    obuf_empty(i) <= '1';
                end if;

                -- if obuf is written to, store data and mark valid
                if (obuf_wr(i) = '1') then
                    obuf_out(i)   <= add_out(i);
                    obuf_empty(i) <= '0';
                end if;
            end loop;
        end if;
    end process;

-------------------------------------------------
-- Adder 0

    U_CTRL0 : entity work.dsa_ctrl
        generic map (add_latency => ADD_LATENCY)
        port map (clk => clk,
                  rst => rst,

                  ibuf_empty        => ibuf_empty,
                  ibuf_rd           => ctrl_ibuf_rd(0),
                  ibuf_end_of_group => ibuf_end_of_group,
                  ibuf_give_up      => ctrl_ibuf_give_up(0),
                  obuf_empty        => obuf_empty(0),
                  obuf_rd           => obuf_rd(0),
                  obuf_wr           => obuf_wr(0),

                  add_en        => add_en(0),
                  add_in1_sel   => add_in1_sel(0),
                  add_in2_sel   => add_in2_sel(0),
                  add_valid_in  => add_valid_in(0),
                  add_valid_out => add_valid_out(0),
                  add_count     => add_count(0),

                  hold_output     => hold_output,
                  is_earliest     => ctrl_earliest(0),
                  has_ibuf_access => ctrl_ibuf_access(0),
                  is_steady       => ctrl_steady(0),
--                  is_coalescing   => ctrl_coalescing(0),
                  is_coalescing   => open,
                  done            => ctrl_done(0));

    -- multiplexer for 1st adder input
    add_in1(0) <= ibuf_out(0) when add_in1_sel(0) = SEL_IBUF_L else
                  obuf_out(0) when add_in1_sel(0) = SEL_OBUF;

    -- multiplexer for 2nd adder input
    add_in2(0) <= ibuf_out(1) when add_in2_sel(0) = SEL_IBUF_R else
                  add_out(0) when add_in2_sel(0) = SEL_ADD_OUT else
                  (others => '0');

    U_ADD0 : entity work.add_wrapper
        generic map (core_name => add_core_name,
                     width     => width)
        port map (clk       => clk,
                  rst       => rst,
                  en        => add_en(0),
                  input1    => add_in1(0),
                  input2    => add_in2(0),
                  output    => add_out(0),
                  valid_in  => add_valid_in(0),
                  valid_out => add_valid_out(0),
                  count     => add_count(0));

-------------------------------------------------
-- Adder 1

    U_CTRL1 : entity work.dsa_ctrl
        generic map (add_latency => ADD_LATENCY)
        port map (clk => clk,
                  rst => rst,

                  ibuf_empty        => ibuf_empty,
                  ibuf_rd           => ctrl_ibuf_rd(1),
                  ibuf_end_of_group => ibuf_end_of_group,
                  ibuf_give_up      => ctrl_ibuf_give_up(1),
                  obuf_empty        => obuf_empty(1),
                  obuf_rd           => obuf_rd(1),
                  obuf_wr           => obuf_wr(1),

                  add_en        => add_en(1),
                  add_in1_sel   => add_in1_sel(1),
                  add_in2_sel   => add_in2_sel(1),
                  add_valid_in  => add_valid_in(1),
                  add_valid_out => add_valid_out(1),
                  add_count     => add_count(1),

                  hold_output     => hold_output,
                  is_earliest     => ctrl_earliest(1),
                  has_ibuf_access => ctrl_ibuf_access(1),
                  is_steady       => ctrl_steady(1),
--                  is_coalescing   => ctrl_coalescing(1),
                  is_coalescing   => open,
                  done            => ctrl_done(1));

    -- multiplexer for 1st adder input
    add_in1(1) <= ibuf_out(0) when add_in1_sel(1) = SEL_IBUF_L else
                  obuf_out(1) when add_in1_sel(1) = SEL_OBUF;

    -- multiplexer for 2nd adder input
    add_in2(1) <= ibuf_out(1) when add_in2_sel(1) = SEL_IBUF_R else
                  add_out(1) when add_in2_sel(1) = SEL_ADD_OUT else
                  (others => '0');

    U_ADD1 : entity work.add_wrapper
        generic map (core_name => add_core_name,
                     width     => width)
        port map (clk       => clk,
                  rst       => rst,
                  en        => add_en(1),
                  input1    => add_in1(1),
                  input2    => add_in2(1),
                  output    => add_out(1),
                  valid_in  => add_valid_in(1),
                  valid_out => add_valid_out(1),
                  count     => add_count(1));

end RTL;

