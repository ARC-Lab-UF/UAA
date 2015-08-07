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
-- David Wilson
-- Greg Stitt
-- University of Florida

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library ieee_proposed;
use ieee_proposed.fixed_float_types.all;  -- ieee in the release 
use ieee_proposed.float_pkg.all;          -- ieee.float_pkg.all; in the release

package uaa_tb_pkg is

	type DATA_ARRAY is array(integer range<>) of std_logic_vector(31 downto 0); 
    -----------------------------------------------------------------------
    -- Procedure randomFloat
    -- Description: create random floating-point number within a specified
    --              range.
    --
    -- Parameters:
    -- seed1/2        : seed values for random number generation
    -- min_exp        : lower bound on randomly generated exponent
    -- max_exp        : upper bound on randomly generated exponent
    -- result         : randomly generated float stored in std_logic_vector
    -- result_float32 : randomly generated float stored in float32 used for
    --                  sequential accumulation result
    -- result_float64 : randomly generated float stored in float64 used for
    --                  estimated accurate result
    -- Preconditions  : min <= max
    --                : min_exp and max_exp within single precision exponent range
    -----------------------------------------------------------------------
    procedure randomFloat
        (variable seed1, seed2    : inout positive; min_exp, max_exp : in integer;
         variable result          : out   std_logic_vector(31 downto 0);
         variable result_float32  : out   float32;
         variable result_float64  : out   float64);

    -----------------------------------------------------------------------
    -- Procedure randomInt
    -- Description: create random integer within a specified range
    --
    -- Parameters:
    -- seed1/2  : seed values for random number generation
    -- min : lower bound on randomly generated number
    -- max : upper bound on randomly generated number
    -- result : randomly generated integer 
	--
    -- Preconditions: min <= max
    -----------------------------------------------------------------------
    procedure randomInt
        (variable seed1, seed2 : inout positive; min, max : in integer;
         variable result       : out   integer);

    ----------------------------------------------------------
    -- Procedure randDecision
    -- Description: randomly decide true/false based on a specified probability
    --
    -- Parameters:
    -- seed1/2  : seed values for random number generation
    -- prob     : probability that decision will be yes/true
    -- decision : the resulting decision
    ----------------------------------------------------------
    procedure randDecision(seed1, seed2 : inout positive;
                           prob         :       real;
                           decision     : out   boolean);

    ----------------------------------------------------------
    -- Procedure randDelay
    -- Description: Create a delay with random cycle length, with specified
    --              probability.
    --
    -- Parameters:
    -- seed1/2  : seed values for random number generation
    -- clk      : The clock signal used for the delay
    -- prob     : probability that the delay will occur
    -- min      : the minimum cycle delay
    -- max      : the maximum cycle delay
    ----------------------------------------------------------
    procedure randDelay(seed1, seed2 : inout positive;
                        signal clk   :       std_logic;
                        prob         :       real;
                        min, max     :       natural);

    ----------------------------------------------------------
    -- Function isAcceptableError
    -- Description: Determines if difference between two real values is
    --              smaller than a specified threshold. 
    --
    -- Parameters:
    -- actual     : The value to compare to a correct value
    -- correct    : The correct value
    -- threshold  : The acceptable percentage difference
    --
    -- Returns : True if error is acceptable, false otherwise.
    ----------------------------------------------------------
    function isAcceptableError(actual, correct, acceptPercent : float64)
        return boolean;
    
end uaa_tb_pkg;

package body uaa_tb_pkg is

    procedure randomFloat(variable seed1, seed2 : inout positive; min_exp, max_exp : in integer; 
						  variable result         : out std_logic_vector(31 downto 0);
              variable result_float32 : out float32;
						  variable result_float64 : out float64) is
        variable rand         : real;    -- Random real value in range 0 to 1.0

        variable temp_result  : real;
    begin

        assert (min_exp >= -128 and min_exp <= 127) 
        report "ERROR: min exponent must be within IEEE754 exponent range: -128 to 127" severity error;
        
        assert (max_exp >= -128 and max_exp <= 127) 
        report "ERROR: max exponent must be within IEEE754 exponent range: -128 to 127" severity error;
        
        assert (min_exp <= max_exp) 
        report "ERROR: In randomFloat(), min must be <= max" severity error;
        
        UNIFORM(seed1, seed2, rand);    -- generate random number  
        temp_result     := 2**ceil(real(max_exp-min_exp)*rand+real(min_exp));
        result_float32  := to_float32(to_float(temp_result));
        result          := to_slv(to_float32(to_float(temp_result)));

        result_float64  := to_float64(to_float(temp_result));
    end randomFloat;


    procedure randomInt(variable seed1, seed2 : inout positive; min, max : in integer; variable result : out integer) is
        variable rand : real;           -- Random real value in range 0 to 1.0
    begin
        assert (min <= max) report "ERROR: In randomInt(), min must be <= max" severity error;

        UNIFORM(seed1, seed2, rand);    -- generate random number  
        result := integer(TRUNC(real(max-min)*rand+real(min)));
    end randomInt;

    
    procedure randDecision(seed1, seed2 : inout positive;
                           prob         :       real;
                           decision     : out   boolean) is
        variable rand : real;
    begin
        
        UNIFORM(seed1, seed2, rand);
        if rand < prob then
            decision := true;
        else
            decision := false;
        end if;
    end procedure;

    procedure randDelay(seed1, seed2 : inout positive;
                        signal clk   :       std_logic;
                        prob         :       real;
                        min, max     :       natural) is

        variable should_delay : boolean;
        variable cycle_delay  : natural;
    begin

        -- decide whether or not to delay
        randDecision(seed1, seed2, prob, should_delay);

        if should_delay then
            -- delay by a random amount between min and max
            randomInt(seed1, seed2, min, max, cycle_delay);
            if cycle_delay > 0 then
                for i in 0 to cycle_delay-1 loop
                    wait until rising_edge(clk);
                end loop;
            end if;
        end if;
    end procedure;

    function isAcceptableError(actual, correct, acceptPercent : float64)
        return boolean is
    begin
        if(to_real(abs(actual-correct)) <= to_real(abs(correct*acceptPercent))) then
            return true;
        else
            return false;
        end if;
    end isAcceptableError;
end package body;

