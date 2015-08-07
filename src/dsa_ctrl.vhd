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
-- The dsa_ctrl entity implements a controller for its associated adder in the 
-- dsa entity and is responsible for handling the control signals from/to the ibuf,
-- and obuf.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.dsa_pkg.all;
use work.math_custom.all;

entity dsa_ctrl is
    generic(add_latency : positive);
    port(clk : in std_logic;
         rst : in std_logic;

         -- ibuf control signals
         ibuf_empty        : in  std_logic_vector(1 downto 0);
         ibuf_rd           : out std_logic;
         ibuf_end_of_group : in  std_logic;
         ibuf_give_up      : out std_logic;

         -- obuf control signals
         obuf_empty : in  std_logic;
         obuf_rd    : out std_logic;
         obuf_wr    : out std_logic;

         -- adder control signals
         add_en        : out std_logic;
         add_in1_sel   : out std_logic;
         add_in2_sel   : out std_logic_vector(1 downto 0);
         add_valid_in  : out std_logic;
         add_valid_out : in  std_logic;
         add_count     : in  std_logic_vector(bitsNeeded(add_latency)-1 downto 0);

         -- status signals
         hold_output     : in  std_logic;
         is_earliest     : in  std_logic;
         has_ibuf_access : in  std_logic;
         is_steady       : out std_logic;
         is_coalescing   : out std_logic;
         done            : out std_logic);  
end dsa_ctrl;


architecture FSM of dsa_ctrl is
    type state_type is (S_WAIT_FOR_IBUF_ACCESS, S_WAIT_FOR_DATA, S_FILL,
                        S_STEADY, S_COALESCE, S_DONE);
    signal state, next_state : state_type;

begin
    
    process(clk, rst)
    begin
        if (rst = '1') then
            state <= S_WAIT_FOR_IBUF_ACCESS;
        elsif (rising_edge(clk)) then
            
            state <= next_state;

            -- unsynthesizeble assertions for testing
            -- synthesis should ignore, but comment out if a problem
            case state is

                when S_WAIT_FOR_DATA =>
                    assert(not(ibuf_empty = "01" and ibuf_end_of_group = '1')) report "DSA_CTRL ERROR: ibuf(1) should be empty when reaching the end of the group.";
                    
                when S_STEADY =>
                    -- This assertion is no longer relevant because DSA now
                    -- forces a write into ibuf1 when a group ends in ibuf0.
                    -- This isn't always needed, but prevents groups from
                    -- getting misaligned when both controllers are coalescing.
                    -- There is probably a better way to implement the buffers
                    -- that makes this assertion valid.
--                    assert(ibuf_empty(1) = '0') report "DSA_CTRL ERROR: ibuf(1) should not have valid element in state S_STEADY.";

                    if (ibuf_empty(0) = '0') then
                        assert(add_valid_out = '1') report "DSA_CTRL ERROR: adder output isn't valid.";
                    end if;

                when others => null;
            end case;

            assert(ibuf_empty /= "01") report "DSA_CTRL ERROR: ibuf(1) should be empty when ibuf(0) is empty.";
        end if;
    end process;

    process(state, ibuf_empty, ibuf_end_of_group, obuf_empty, add_valid_out, add_count, hold_output, is_earliest, has_ibuf_access)
        procedure startAdd(in1 : std_logic;
                           in2 : std_logic_vector(1 downto 0)) is
        begin
            add_en       <= '1';
            add_valid_in <= '1';
            add_in1_sel  <= in1;
            add_in2_sel  <= in2;

            if (in1 = SEL_IBUF_L or in2 = SEL_IBUF_R) then
                ibuf_rd <= '1';
            end if;

            if (in1 = SEL_OBUF) then
                obuf_rd <= '1';
            end if;
        end startAdd;

    begin

        -- default control values
        ibuf_rd       <= '0';
        obuf_rd       <= '0';
        obuf_wr       <= '0';
        add_en        <= '0';
        add_in1_sel   <= SEL_IBUF_L;
        add_in2_sel   <= SEL_IBUF_R;
        add_valid_in  <= '0';
        is_steady     <= '0';
        is_coalescing <= '0';
        done          <= '0';
        next_state    <= state;

        case state is
            when S_WAIT_FOR_IBUF_ACCESS =>

                -- clear out the obuf from previous executions
                obuf_rd <= '1';

                -- wait until given access to the ibuf. This prevents
                -- multiple adders from reading from the buffer simultaneously
                if (has_ibuf_access = '1') then
                    next_state <= S_WAIT_FOR_DATA;
                end if;
                
            when S_WAIT_FOR_DATA =>

                -- waits until first pair of data from ibuf, pushes that data into
                -- the adder, and then moves to the fill state (or the coalesce
                -- state if the end of the group is reached.
                
                if (ibuf_empty = "00") then

                    startAdd(SEL_IBUF_L, SEL_IBUF_R);

                    if (ibuf_end_of_group = '1') then
                        next_state <= S_COALESCE;
                    else
                        next_state <= S_FILL;
                    end if;
                elsif (ibuf_empty = "10" and ibuf_end_of_group = '1') then

                    -- the input group only has one element.
                    -- This code forces a zero into the adder.
                    -- NOTE: This can be optimized by directly moving the input
                    -- to the output.

                    startAdd(SEL_IBUF_L, SEL_ZERO);
                    next_state <= S_COALESCE;
                end if;

            when S_FILL =>

                if (ibuf_end_of_group = '1') then

                    -- push the final values into the adder, forcing a zero
                    -- if necessary
                    if (ibuf_empty = "00") then
                        startAdd(SEL_IBUF_L, SEL_IBUF_R);
                    else
                        startAdd(SEL_IBUF_L, SEL_ZERO);
                    end if;

                    next_state <= S_COALESCE;
                    
                elsif (ibuf_empty = "00") then

                    startAdd(SEL_IBUF_L, SEL_IBUF_R);

                    -- if adder pipeline is full, move to steady state
                    if (unsigned(add_count) = (add_latency-1)) then
                        -- TODO: verify is steady should bea asserted here
                        is_steady  <= '1';
                        next_state <= S_STEADY;
                    end if;
                end if;

            when S_STEADY =>
                
                is_steady <= '1';

                -- whenever there is a single input in ibuf, add it with the
                -- output of the adder
                if (ibuf_empty(0) = '0') then

                    startAdd(SEL_IBUF_L, SEL_ADD_OUT);

                    if (ibuf_end_of_group = '1') then
                        -- stop is_steady one cycle early to prevent writing
                        -- into ibuf0 twice in a row at the beginning of the
                        -- next group, which can happen if there is no delay
                        -- between groups
                        is_steady  <= '0';
                        next_state <= S_COALESCE;
                    end if;
                end if;

            when S_COALESCE =>
                
                is_coalescing <= '1';

                -- force a junk value into adder when obuf or adder output is invalid
                if (obuf_empty = '1' or add_valid_out = '0') then
                    add_en       <= '1';
                    add_valid_in <= '0';
                end if;

                if (add_valid_out = '1') then
                    if (obuf_empty = '1') then
                        -- write the adder output to the obuf when empty
                        obuf_wr <= '1';
                    else
                        -- start an add if both adder output and obuf are valid
                        startAdd(SEL_OBUF, SEL_ADD_OUT);
                    end if;
                end if;

                -- the controller is done when the adder has no pending adds
                -- (count = 0) and when the controller is not starting another
                -- add                
                if (unsigned(add_count) = 0 and
                    not (add_valid_out = '1' and obuf_empty = '0')) then
                    next_state <= S_DONE;
                end if;
                
            when S_DONE =>
                -- if this adder isn't handling the earliest group, delay until
                -- the earliest group finishes to prevent out-of-order outputs.
                -- This also stalls if hold_output isn't asserted, which
                -- prevents the output from being lost. 
                if (is_earliest = '1' and hold_output = '0') then
                    done       <= '1';
                    next_state <= S_WAIT_FOR_IBUF_ACCESS;
                end if;

            when others => null;
        end case;
    end process;

    -- this process guarantees that any transition to the coalesce state
    -- gives up access to the ibuf. This separate process is safer than having
    -- to remember to manually specify every transition in the earlier process.
    process(state, next_state)
    begin

        ibuf_give_up <= '0';

        if (next_state = S_COALESCE and state /= S_COALESCE) then
            ibuf_give_up <= '1';
        end if;
    end process;
    
end FSM;

