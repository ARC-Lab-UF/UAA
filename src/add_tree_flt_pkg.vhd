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

-- add_tree_flt_pkg.vhd
-- This package defines functions for using add_tree_flt instances.

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;
use work.flt_pkg.all;

package add_tree_flt_pkg is
    -- specifies the latency of an add_tree_flt based on the number of inputs
    -- and the name of the adder core
    function add_tree_flt_latency (
        constant num_inputs    : positive;
        constant add_core_name : string)
        return natural;
end add_tree_flt_pkg;

package body add_tree_flt_pkg is

    function add_tree_flt_latency (
        constant num_inputs    : positive;
        constant add_core_name : string)
        return natural is
    begin
        return natural(ceil(log2(real(num_inputs))))*add_flt_latency(add_core_name);
    end function;
    
end add_tree_flt_pkg;

