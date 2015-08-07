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

-- flt_pkg.vhd
-- This package contains functions that specify various characteristics about
-- floating-point entities.

-- This example has been configured based on latencies of Stratix 3 cores used
-- in the *_flt entities.

library ieee;
use ieee.std_logic_1164.all;

package flt_pkg is
    function add_flt_latency(core_name  : string) return natural;
    function mult_flt_latency(core_name : string) return natural;
end flt_pkg;

package body flt_pkg is

    function add_flt_latency(core_name : string) return natural is
    begin
        if (core_name = "stratix3_latency") then
            return 7;
        elsif (core_name = "stratix3_area" or core_name = "stratix3_speed") then
            return 14;
        elsif (core_name = "stratix5_latency") then
            return 7;
        elsif (core_name = "stratix5_area" or core_name = "stratix5_speed") then
            return 14;
        elsif (core_name = "virtex7_latency") then
            return 8;
        elsif (core_name = "virtex7_speed") then
            return 11;
        end if;

        assert(false) report "Error: No add_flt latency specified for architecture " & '"' & core_name & '"' & " in flt_pkg.vhd" severity error;
        return 0;
    end function;

    function mult_flt_latency(core_name : string) return natural is
    begin
        if (core_name = "area") then
            return 5;
        elsif (core_name = "speed") then
            return 11;
        end if;

        assert(false) report "Error: No latency specified for mult_flt architecture " & '"' & core_name & '"' & " in flt_pkg.vhd" severity error;
        return 0;
    end function;

end package body;

