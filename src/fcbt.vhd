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
-- The fcbt entity implements the fully compacted binary tree design similar to the 
-- architecture described in the paper "High-Performance Reduction Circuits Using Deeply 
-- Pipelined Operators on FPGAs" by Ling Zhuo, G.R. Morris and V.K. Prasanna (2007)

-- Used entities:
-- fifo2, delay, add_wrapper

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
-- FCBT_max_inputs   : This positive indicates the maximum amount of inputs
--                     per input group. Buffer size scales with the log of
--                     of this generic.
-- FCBT_obuf_size    : Specifies the size of the output buffer for the
--                     FCBT architecture. 
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Port Description:
-- clk          : clock input
-- rst          : reset input (asynchronous, active high)
-- hold_output  : When asserted, this signal prevents the entity from
--                continuing past a valid output. When not asserted, the
--                output is valid for only a single cycle. This signal
--                makes it possible to stall the fcbt if downstream
--                components cannot receive another input  (active high)
-- ready        : when asserted, the fcbt is ready to accept new inputs. If not
--                asserted, external components must hold the current input or
--                it will be lost (active high)
-- end_of_group : should be asserted on the same cycle as the last input in a
--                group (active high)
-- input        : fcbt input
-- output       : fcbt output
-- valid_in     : assert when the input to the fcbt is valid and ready is
--                asserted (active high)
-- valid_out    : asserted when the output from the fcbt is valid. Unless
--                hold_output is asserted, valid_out is only asserted for
--                one cycle. (active high)
-------------------------------------------------------------------------------

entity fcbt is
    generic (
        width           : positive := 32;
        add_core_name   : string   := "speed";
        use_bram        : boolean  := true;
        FCBT_max_inputs : positive := 128;
        FCBT_obuf_size  : positive := 14
        );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        hold_output  : in  std_logic;   -- '1' keeps outputs from disappearing
        ready        : out std_logic;   -- '1' when fcbt can accept input
        end_of_group : in  std_logic;   -- specifies last input in group

        input     : in  std_logic_vector(width-1 downto 0);
        output    : out std_logic_vector(width-1 downto 0);
        valid_in  : in  std_logic;
        valid_out : out std_logic
        );
end fcbt;

architecture STR of fcbt is

    -- fcbt should be used when the max number of inputs per group is more than 4
    function set_max_inputs return positive is
    begin
        if FCBT_max_inputs < 5 then
            return 5;
        else
            return FCBT_max_inputs;
        end if;
    end function set_max_inputs;
	
	function set_obuf_size return positive is
	begin
		if FCBT_obuf_size < 1 then
			return 1;
		else
			return FCBT_obuf_size;
		end if;
	end function set_obuf_size;

    constant ADD_LATENCY  : natural  := add_flt_latency(add_core_name);
    constant BUFFER_DEPTH : integer  := 6;
    constant MAX_INPUTS   : positive := set_max_inputs;

    constant TREE_LEVELS      : integer := clog2(MAX_INPUTS);
    constant TREE_LEVELS_BITS : integer := clog2(TREE_LEVELS);
    constant MAX_GROUP        : integer := set_obuf_size;
    constant MAX_GROUP_BITS   : integer := clog2(MAX_GROUP);
    constant TAGGING_BITS     : integer := MAX_GROUP_BITS+2;

    type data_array             is array (natural range<>) of std_logic_vector(width-1 downto 0);
    type obuf_out_array         is array (natural range<>) of std_logic_vector(width downto 0);
    type buf_count_array        is array (natural range<>) of std_logic_vector(clog2(BUFFER_DEPTH+1)-1 downto 0);
    type buf_group_num_array    is array (natural range<>) of std_logic_vector(MAX_GROUP_BITS-1 downto 0);
    type buf_array              is array (natural range<>) of std_logic_vector(width+TAGGING_BITS-1 downto 0);
    type add_group_labels_array is array (natural range<>) of std_logic_vector(TAGGING_BITS-1 downto 0);

    -- input tagging signals
    signal start_of_group : std_logic;
    signal group_num      : std_logic_vector(MAX_GROUP_BITS-1 downto 0);

    -- adder signals
    signal add_in1                : data_array(1 downto 0);
    signal add_in2                : data_array(1 downto 0);
    signal add_out                : data_array(1 downto 0);
    signal add_valid_in           : std_logic_vector(1 downto 0);
    signal add_valid_out          : std_logic_vector(1 downto 0);
    signal add_zero               : std_logic_vector(1 downto 0);
    signal add_group_tags_in      : add_group_labels_array(1 downto 0);
    signal add_group_tags_out     : add_group_labels_array(1 downto 0);
    signal add_group_num_in       : buf_group_num_array(1 downto 0);
    signal add_group_num_out      : buf_group_num_array(1 downto 0);
    signal add_end_of_group_in    : std_logic_vector(1 downto 0);
    signal add_end_of_group_out   : std_logic_vector(1 downto 0);
    signal add_start_of_group_in  : std_logic_vector(1 downto 0);
    signal add_start_of_group_out : std_logic_vector(1 downto 0);
    signal add_last_element       : std_logic_vector(1 downto 0);

    -- buf signals
    signal buf_in                  : buf_array(TREE_LEVELS-1 downto 0);
    signal buf_out0                : data_array(TREE_LEVELS-1 downto 0);
    signal buf_out1                : data_array(TREE_LEVELS-1 downto 0);
    signal buf_out0_temp           : buf_array(TREE_LEVELS-1 downto 0);
    signal buf_out1_temp           : buf_array(TREE_LEVELS-1 downto 0);
    signal buf_rd                  : std_logic_vector(TREE_LEVELS-1 downto 0);
    signal buf_rd_single           : std_logic_vector(TREE_LEVELS-1 downto 0);
    signal buf_wr                  : std_logic_vector(TREE_LEVELS-1 downto 0);
    signal buf_start_of_group      : std_logic_vector(TREE_LEVELS-1 downto 0);
    signal buf_start_of_group_zero : std_logic_vector(TREE_LEVELS-1 downto 0);
    signal buf_end_of_group        : std_logic_vector(TREE_LEVELS-1 downto 0);
    signal buf_end_of_group_zero   : std_logic_vector(TREE_LEVELS-1 downto 0);
    signal buf_group_num           : buf_group_num_array(TREE_LEVELS-1 downto 0);
    signal buf_count               : buf_count_array(TREE_LEVELS-1 downto 0);
    signal buf_empty               : std_logic_vector(TREE_LEVELS-1 downto 0);

    -- obuf signals
    signal obuf_out      : obuf_out_array(MAX_GROUP-1 downto 0);
    signal output_ptn    : unsigned(MAX_GROUP_BITS-1 downto 0);
    signal valid_out_int : std_logic;

    -- ctrl signals
    signal ctrl_en           : std_logic;
    signal ctrl_count        : unsigned(TREE_LEVELS-2 downto 0);
    signal ctrl_buf_sel      : unsigned(TREE_LEVELS_BITS-1 downto 0);
    signal ctrl_next_buf_in  : std_logic_vector(TREE_LEVELS_BITS-1 downto 0);
    signal ctrl_next_buf_out : std_logic_vector(TREE_LEVELS_BITS-1 downto 0);
    signal ready_max_groups  : std_logic;
    
begin
    -- the FCBT deasserts ready when fcbt holds the max number of groups
    ctrl_en   <= '1';
    ready     <= ready_max_groups;

---------------------------------------------------------------
-- Input Tagging

    -- assign group number for incoming inputs. Group numbers will correspond to index in
    -- output buffer and will ensure in-order outputs from the buffer.
    process(clk, rst)
    begin
        if (rst = '1') then
            -- group numbers start at 0
            group_num <= std_logic_vector(to_unsigned(0, MAX_GROUP_BITS));
            
        elsif (rising_edge(clk)) then
			if (ready_max_groups = '1') then
                -- get next group number after receiving the current group's last element
                if (valid_in = '1' and end_of_group = '1') then
                    if (to_integer(unsigned(group_num)) = MAX_GROUP-1) then
                        group_num <= std_logic_vector(to_unsigned(0, MAX_GROUP_BITS));
                    else
                        group_num <= std_logic_vector(unsigned(group_num)+1);
                    end if;
                end if;
            end if;
        end if;
    end process;

    ready_max_groups <= '0' when output_ptn = to_unsigned(to_integer(unsigned(group_num)+1) mod MAX_GROUP, MAX_GROUP_BITS) else '1';

    -- keep track of which input is the first element of a group. This will be the first
    -- received element or the next valid element following the last element of a
    -- previous group.
    process(clk, rst)
    begin
        if (rst = '1') then
            -- First received element will be the start of the first group
            start_of_group <= '1';
            
        elsif (rising_edge(clk)) then
			if (ready_max_groups = '1') then
                -- the element following the end of one group will be the start of the 
                -- next group
                if (end_of_group = '1' and valid_in = '1') then
                    start_of_group <= '1';

                -- any other element is not the start of the next group
                elsif (valid_in = '1') then
                    start_of_group <= '0';
                end if;
            end if;
        end if;
    end process;

---------------------------------------------------------------
-- BUF

    -- attach tagging information to the input to identify the last element and its place in the
    -- output buffer. The last element will have  both end_of_group and start_of_group asserted.
    -- Group_num will act as an index into the output buffer to handle out of order outputs
    buf_in(0) <= group_num & end_of_group & start_of_group & input;
    -- write to the first buffer any time there is valid input and the architecture isn't stalling
    buf_wr(0) <= '1' when valid_in = '1' and ready_max_groups = '1' else
                 '0';

    -- carry along data with tagging information
    buf_in(1) <= add_group_num_out(0) & add_end_of_group_out(0) & add_start_of_group_out(0) & add_out(0);
    -- write to the second buffer any time there is valid output from the first adder that isn't the final 
    -- sum of the group and when the architecture isn't stalling
    buf_wr(1) <= '1' when add_valid_out(0) = '1' and add_last_element(0) = '0' else
                 '0';
    
    U_BUFF_WR : for i in 2 to TREE_LEVELS-1 generate

        -- carry along data with tagging information
        buf_in(i) <= add_group_num_out(1) & add_end_of_group_out(1) & add_start_of_group_out(1) & add_out(1);
        -- write to the other buffers any time there is valid output from the second adder that isn't the 
        -- final sum of the group and is the sum of elements on the buffer level below it
        buf_wr(i) <= '1' when add_valid_out(1) = '1' and add_last_element(1) = '0' and
                     ctrl_next_buf_out = std_logic_vector(to_unsigned(i, TREE_LEVELS_BITS)) else
                     '0';
    end generate U_BUFF_WR;

    U_BUFFERS : for i in 0 to TREE_LEVELS-1 generate
        U_BUFF : entity work.fifo2
            generic map(
                width             => width+TAGGING_BITS,
                depth             => BUFFER_DEPTH,
                use_bram          => use_bram,
                same_cycle_output => true)
            port map(
                clk       => clk,
                rst       => rst,
                rd        => buf_rd(i),
                wr        => buf_wr(i),
                single    => buf_rd_single(i),
                empty     => buf_empty(i),
                full      => open,
                overflow  => open,
                underflow => open,
                input     => buf_in(i),
                output0   => buf_out0_temp(i),
                output1   => buf_out1_temp(i),
                count     => buf_count(i)
                );

        -- break up buf outputs into group_num data, end_of_group flag, start_of_group flag, and data to add
        -- Note: these may be uninitialized until the first rising clock edge when using block RAM
        buf_group_num(i)           <= buf_out0_temp(i)(width+2+MAX_GROUP_BITS-1 downto width+2);
        buf_end_of_group(i)        <= buf_out0_temp(i)(width+1) or buf_out1_temp(i)(width+1);
        buf_end_of_group_zero(i)   <= buf_out0_temp(i)(width+1);
        buf_start_of_group(i)      <= buf_out0_temp(i)(width) or buf_out1_temp(i)(width);
        buf_start_of_group_zero(i) <= buf_out0_temp(i)(width);
        buf_out0(i)                <= buf_out0_temp(i)(width-1 downto 0);
        buf_out1(i)                <= buf_out1_temp(i)(width-1 downto 0);
    end generate U_BUFFERS;

    process(ctrl_count, buf_count, buf_out0_temp)
    begin
        -- default values
        buf_rd_single <= (others => '0');
        buf_rd        <= (others => '0');
        add_zero      <= (others => '0');
        add_valid_in  <= (others => '0');
        ctrl_buf_sel  <= (others => '0');



        -- perform singleton addition with 1st adder if the next element in buffer 0
        -- is the last element of a group
        if(buf_count(0) > std_logic_vector(to_unsigned(0, buf_count(0)'length)) and
           buf_out0_temp(0)(width+1) = '1') then
            buf_rd(0)        <= '1';
            buf_rd_single(0) <= '1';
            add_zero(0)      <= '1';
            add_valid_in(0)  <= '1';

        -- perform normal addition with 1st adder when there's two or more elements
        -- in buffer 0
        elsif(buf_count(0) > std_logic_vector(to_unsigned(1, buf_count(0)'length))) then
            buf_rd(0)       <= '1';
            add_valid_in(0) <= '1';
        end if;

        for i in 1 to TREE_LEVELS-1 loop

            -- 2nd adder uses inputs from buffer i (i>=1) every 2^i cycles 
            if (ctrl_count(i-1 downto 0) = to_unsigned(2**(i-1)-1, i)) then
                ctrl_buf_sel <= to_unsigned(i, ctrl_buf_sel'length);

                                    -- perform singleton addition if the next element in buffer i is the last 
                                    -- element of a group
                if(buf_count(i) > std_logic_vector(to_unsigned(0, buf_count(i)'length)) and
                   buf_out0_temp(i)(width+1) = '1') then
                    buf_rd(i)        <= '1';
                    buf_rd_single(i) <= '1';
                    add_zero(1)      <= '1';
                    add_valid_in(1)  <= '1';

                                    -- perform normal addition when there's two or more elements in buffer i
                elsif(buf_count(i) > std_logic_vector(to_unsigned(1, buf_count(i)'length))) then
                    buf_rd(i)       <= '1';
                    add_valid_in(1) <= '1';
                end if;
            end if;
        end loop;
    end process;

---------------------------------------------------------------
-- Adders

    -- 1st adder inputs. Second input is zeroed for singleton addition
    add_in1(0) <= buf_out0(0);
    add_in2(0) <= buf_out1(0) when add_zero(0) = '0' else (others => '0');

    -- 2nd adder inputs. Second input is zeroed for singleton addition
    add_in1(1) <= buf_out0(to_integer(ctrl_buf_sel));
    add_in2(1) <= buf_out1(to_integer(ctrl_buf_sel)) when add_zero(1) = '0' else (others => '0');

    -- adder end_of_group bits. Value only considers first element in singleton add.
    add_end_of_group_in(0) <= buf_end_of_group(0) when add_zero(0) = '0' else
                                           buf_end_of_group_zero(0);
    add_end_of_group_in(1) <= buf_end_of_group(to_integer(ctrl_buf_sel)) when add_zero(1) = '0' else
                                           buf_end_of_group_zero(to_integer(ctrl_buf_sel));

    -- adder start_of_group bits. Value only considers first element in singleton add.
    add_start_of_group_in(0) <= buf_start_of_group(0) when add_zero(0) = '0' else
                                   buf_start_of_group_zero(0);
    add_start_of_group_in(1) <= buf_start_of_group(to_integer(ctrl_buf_sel)) when add_zero(1) = '0' else
                                   buf_start_of_group_zero(to_integer(ctrl_buf_sel));

    -- adder group_num bits
    add_group_num_in(0) <= buf_group_num(0);
    add_group_num_in(1) <= buf_group_num(to_integer(ctrl_buf_sel));

    U_ADDERS : for i in 0 to 1 generate
        U_ADDER : entity work.add_wrapper
            generic map(
                core_name => add_core_name,
                width         => width)
            port map(
                clk       => clk,
                rst       => rst,
                en        => ctrl_en,
                input1    => add_in1(i),
                input2    => add_in2(i),
                output    => add_out(i),
                valid_in  => add_valid_in(i),
                valid_out => add_valid_out(i),
                count     => open
                );

        U_GROUP_TAGS : entity work.delay
            generic map(
                cycles => ADD_LATENCY,
                width  => TAGGING_BITS,
                init   => std_logic_vector(to_unsigned(0, TAGGING_BITS)))
            port map(
                clk    => clk,
                rst    => rst,
                en     => ctrl_en,
                input  => add_group_tags_in(i),
                output => add_group_tags_out(i)
                );

        -- carry along tagging information while sum is in adder
        add_group_tags_in(i) <= add_group_num_in(i) &
                                   add_end_of_group_in(i) &
                                   add_start_of_group_in(i);

        -- break up tagging signal into end_of_group flag, start_of_group flag, and group_num data
        add_end_of_group_out(i)   <= add_group_tags_out(i)(1);
        add_start_of_group_out(i) <= add_group_tags_out(i)(0);
        add_group_num_out(i)      <= add_group_tags_out(i)(TAGGING_BITS-1 downto 2);

        -- an adder output with both end_of_group and start_of_group bits asserted is 
        -- the last element in the group
        add_last_element(i) <= '1' when add_end_of_group_out(i) = '1' and
                                           add_start_of_group_out(i) = '1' else
                                           '0';
    end generate;

    U_NEXT_BUF : entity work.delay
        generic map(
            cycles => ADD_LATENCY,
            width  => TREE_LEVELS_BITS,
            init   => std_logic_vector(to_unsigned(0, TREE_LEVELS_BITS)))
        port map(
            clk    => clk,
            rst    => rst,
            en     => ctrl_en,
            input  => ctrl_next_buf_in,
            output => ctrl_next_buf_out
            );

    -- if the adder is using inputs from buffer i, the sum should be written to
    -- buffer i+1 or obuf if final sum.
    ctrl_next_buf_in <= std_logic_vector(ctrl_buf_sel+1);

---------------------------------------------------------------
-- OBUF

    -- create obufs, and handle output and valid_out logic
    process(clk, rst)
        variable obuf_index : integer;
    begin
        if (rst = '1') then
            for i in 0 to MAX_GROUP-1 loop
                obuf_out(i) <= (others => '0');
            end loop;
            output_ptn    <= to_unsigned(0, output_ptn'length);
            valid_out_int <= '0';
            output        <= (others => '0');
        elsif (rising_edge(clk)) then	
            for i in 0 to 1 loop
			
                -- write adder output to obuf at its group number index if valid and last element of group
                -- obuf has additional bit acting as a ready bit
                if (add_valid_out(i) = '1' and add_last_element(i) = '1') then
                    obuf_out(to_integer(unsigned(add_group_num_out(i)))) <= '1' & add_out(i);
                end if;
            end loop;

			if (hold_output = '0') then
				-- clear valid_out flag if it was set before
					valid_out_int <= '0';
			
				-- outputs data at output_ptn if the ready bit is asserted and either hold_output isn't asserted
				-- or valid_out isn't asserted. 
				if (obuf_out(to_integer(output_ptn))(width) = '1' and (hold_output = '0' or valid_out_int = '0')) then
					output        <= obuf_out(to_integer(output_ptn))(width-1 downto 0);
					valid_out_int <= '1';
	
					-- Data at output_ptn index is cleared and output_ptn gets next possible index.
					obuf_out(to_integer(output_ptn)) <= (others => '0');
					if (to_integer(output_ptn) = MAX_GROUP-1) then
						output_ptn <= to_unsigned(0, MAX_GROUP_BITS);
					else
						output_ptn <= output_ptn+1;
					end if;
				end if;
			end if;
        end if;
    end process;
    valid_out <= valid_out_int;

---------------------------------------------------------------
-- Scheduling Counter

    -- Counter bits used for scheduling 2nd adder additions
    process(clk, rst)
    begin
        if (rst = '1') then
            ctrl_count <= (others => '0');
        elsif (rising_edge(clk)) then
            ctrl_count <= unsigned(ctrl_count)+1;
        end if;
    end process;
end STR;

