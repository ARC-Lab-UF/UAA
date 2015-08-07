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
-- The dsa_pkg entity provides the constants for the select signals of the DSA's
-- muxes for adder inputs.

library ieee;
use ieee.std_logic_1164.all;

package dsa_pkg is

    -- select values for DSA muxes
    constant SEL_IBUF_L : std_logic := '0';
    constant SEL_OBUF   : std_logic := '1';
    constant SEL_IBUF_R  : std_logic_vector(1 downto 0) := "00";
    constant SEL_ADD_OUT : std_logic_vector(1 downto 0) := "01";
    constant SEL_ZERO    : std_logic_vector(1 downto 0) := "10";
end dsa_pkg;

package body dsa_pkg is
end package body;

