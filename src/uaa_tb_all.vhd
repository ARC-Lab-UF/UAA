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
-- Greg Stitt
-- University of Florida

-- Description:
-- This file instantiates the uaa's testbench for each of the 
-- architectures and verifies their correctness in a simple case

library ieee;
use ieee.std_logic_1164.all;

use work.uaa_pkg.all;

entity uaa_tb_all is
end uaa_tb_all;

architecture DEFAULT of uaa_tb_all is
begin
  UUT_FCBT : entity work.uaa_tb
  generic map(
    test_name           => "FCBT",
    arch                => UAA_FCBT,
    parallel_inputs     => 4,
    add_core_name       => "virtex7_latency",
    use_bram            => true,
    FCBT_max_inputs     => 300,
    FCBT_obuf_size      => 14,
    total_groups        => 20
  ) 
  port map(
    min_group_size            => 300,
    max_group_size            => 300,
    input_delay_prob          => 0.0,
    group_delay_prob          => 0.0,
    hold_output_prob          => 0.0,
    acceptable_error_percent  => 0.000,
    print_status              => false
  );
  
  UUT_DSA : entity work.uaa_tb
  generic map(
    test_name           => "DSA",
    arch                => UAA_DSA,
    parallel_inputs     => 4,
    add_core_name       => "virtex7_speed",
    use_bram            => true,
    FCBT_max_inputs     => 300,
    FCBT_obuf_size      => 14,
    total_groups        => 20
  ) 
  port map(
    min_group_size            => 300,
    max_group_size            => 300,
    input_delay_prob          => 0.0,
    group_delay_prob          => 0.0,
    hold_output_prob          => 0.0,
    acceptable_error_percent  => 0.000,
    print_status              => false
  );

  UUT_SGA : entity work.uaa_tb
  generic map(
    test_name           => "SGA",
    arch                => UAA_SGA,
    parallel_inputs     => 4,
    add_core_name       => "virtex7_speed",
    use_bram            => true,
    FCBT_max_inputs     => 300,
    FCBT_obuf_size      => 14,
    total_groups        => 20
  ) 
  port map(
    min_group_size            => 300,
    max_group_size            => 300,
    input_delay_prob          => 0.0,
    group_delay_prob          => 0.0,
    hold_output_prob          => 0.0,
    acceptable_error_percent  => 0.000,
    print_status              => false
  );  
end DEFAULT;
