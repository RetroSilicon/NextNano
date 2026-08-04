-- PS2 Keyboard
-- Copyright 2020 Fabio Belavenuto
-- Copyright 2021 Alvin Albrecht
--
-- This file is part of the ZX Spectrum Next Project
-- <https://gitlab.com/SpectrumNext/ZX_Spectrum_Next_FPGA/tree/master/cores>
--
-- The ZX Spectrum Next FPGA source code is free software: you can 
-- redistribute it and/or modify it under the terms of the GNU General 
-- Public License as published by the Free Software Foundation, either 
-- version 3 of the License, or (at your option) any later version.
--
-- The ZX Spectrum Next FPGA source code is distributed in the hope 
-- that it will be useful, but WITHOUT ANY WARRANTY; without even the 
-- implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
-- PURPOSE.  See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with the ZX Spectrum Next FPGA source code.  If not, see 
-- <https://www.gnu.org/licenses/>.

-- ps2 button state is represented in an 8x7 matrix
-- when the physical membrane is scanned, the ps2 inserts column data
-- caps + sym shift presses are counted; shifts are not lost in multiple keys
-- typematic filtered so that shift counts remain accurate
-- F11 = multiface nmi button, F12 = divmmc nmi button
-- function keys work as on membrane: F11 + number
-- pause/break resets the ps2 matrix state

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity ps2_keyb is
   port
   (
      i_CLK             : in std_logic;
      i_reset           : in std_logic;

      -- ps2 interface
      ps2_key           : in std_logic_vector(10 downto 0);

      -- membrane interaction
      i_membrane_row    : in std_logic_vector(2 downto 0);
      o_membrane_col    : out std_logic_vector(6 downto 0);

      -- programmable keymap
      i_keymap_addr     : in std_logic_vector(8 downto 0);
      i_keymap_data     : in std_logic_vector(7 downto 0);
      i_keymap_we       : in std_logic;

      fn                : out std_logic_vector(11 downto 1) := (others => '0')
   );
end entity;

architecture rtl of ps2_keyb is

   signal capshift_count_zero    : std_logic;
   signal capshift_count         : std_logic_vector(2 downto 0);
   
   signal symshift_count_zero    : std_logic;
   signal symshift_count         : std_logic_vector(2 downto 0);

   type key_matrix_t is array (7 downto 0) of std_logic_vector(6 downto 0);
   signal matrix_state           : key_matrix_t := ((others => (others => '1')));
   
   signal row_0_n                : std_logic;
   signal row_7_n                : std_logic;
   
   signal ps2_keymap_data        : std_logic_vector(8 downto 0);
   
   signal ps2_valid              : std_logic;
   signal ps2_key_valid          : std_logic;
   signal ps2_matrix_reset       : std_logic;
   
   signal ps2_stb1, ps2_stb2     : std_logic;
   signal ps2_receive_data       : std_logic_vector(7 downto 0);

   signal ps2_key_extend         : std_logic;
   signal ps2_key_release        : std_logic;
begin

   process (i_CLK)
   begin
      if rising_edge(i_CLK) then
         ps2_stb1  <= ps2_key(10);
         ps2_stb2  <= ps2_stb1;
         ps2_valid <= ps2_stb2 xor ps2_stb1;
      end if;
   end process;
   
	ps2_key_release  <= not ps2_key(9);
	ps2_key_extend   <= ps2_key(8);
	ps2_receive_data <= ps2_key(7 downto 0);

	ps2_key_valid    <= '1' when ps2_valid = '1' and ps2_keymap_data(7 downto 6) /= "11" else '0';
   ps2_matrix_reset <= '1' when ps2_key_valid = '1' and ps2_key_extend = '1' and ps2_receive_data = X"77" else '0';


   -- F1..F11

   process (i_CLK)
   begin
      if rising_edge(i_CLK) then
         if ps2_matrix_reset = '1' then
				fn <= (others => '0');
         elsif ps2_valid = '1' and ps2_key_extend = '0' then
				if ps2_receive_data = X"05" then    -- F1
					fn(1) <= not ps2_key_release;
				elsif ps2_receive_data = X"06" then -- F2
					fn(2) <= not ps2_key_release;
				elsif ps2_receive_data = X"04" then -- F3
					fn(3) <= not ps2_key_release;
				elsif ps2_receive_data = X"0C" then -- F4
					fn(4) <= not ps2_key_release;
				elsif ps2_receive_data = X"03" then -- F5
					fn(5) <= not ps2_key_release;
				elsif ps2_receive_data = X"0B" then -- F6
					fn(6) <= not ps2_key_release;
				elsif ps2_receive_data = X"83" then -- F7
					fn(7) <= not ps2_key_release;
				elsif ps2_receive_data = X"0A" then -- F8
					fn(8) <= not ps2_key_release;
				elsif ps2_receive_data = X"01" then -- F9
					fn(9) <= not ps2_key_release;
				elsif ps2_receive_data = X"09" then -- F10
					fn(10) <= not ps2_key_release;
				elsif ps2_receive_data = X"78" then -- F11
					fn(11) <= not ps2_key_release;
				end if;
         end if;
      end if;
   end process;
	
   
   -- matrix representation
   
   capshift_count_zero <= '1' when capshift_count = std_logic_vector(to_unsigned(0,capshift_count'length)) else '0';
   
   process (i_CLK)
   begin
      if rising_edge(i_CLK) then
         if i_reset = '1' or ps2_matrix_reset = '1' then
            capshift_count <= (others => '0');
         elsif ps2_key_valid = '1' and ps2_keymap_data(6) = '1' then
            if ps2_key_release = '0' then
               capshift_count <= capshift_count + 1;
            elsif capshift_count_zero = '0' then
               capshift_count <= capshift_count - 1;
            end if;
         end if;
      end if;
   end process;
   
   symshift_count_zero <= '1' when symshift_count = std_logic_vector(to_unsigned(0,symshift_count'length)) else '0';
   
   process (i_CLK)
   begin
      if rising_edge(i_CLK) then
         if i_reset = '1' or ps2_matrix_reset = '1' then
            symshift_count <= (others => '0');
         elsif ps2_key_valid = '1' and ps2_keymap_data(7) = '1' then
            if ps2_key_release = '0' then
               symshift_count <= symshift_count + 1;
            elsif symshift_count_zero = '0' then
               symshift_count <= symshift_count - 1;
            end if;
         end if;
      end if;
   end process;

   process (i_CLK)
   begin
      if rising_edge(i_CLK) then
         if i_reset = '1' or ps2_matrix_reset = '1' then
            matrix_state <= ((others => (others => '1')));
         elsif ps2_key_valid = '1' and ps2_keymap_data(2 downto 0) /= "111" then
            matrix_state(to_integer(unsigned(ps2_keymap_data(5 downto 3))))(to_integer(unsigned(ps2_keymap_data(2 downto 0)))) <= ps2_key_release;
         end if;
      end if;
   end process;
   
   -- membrane scan
   
   row_0_n <= '0' when i_membrane_row = "000" else '1';
   row_7_n <= '0' when i_membrane_row = "111" else '1';
   
   o_membrane_col <= (matrix_state(to_integer(unsigned(i_membrane_row)))(6 downto 2)) & 
                     (matrix_state(to_integer(unsigned(i_membrane_row)))(1) and (row_7_n or symshift_count_zero)) & 
                     (matrix_state(to_integer(unsigned(i_membrane_row)))(0) and (row_0_n or capshift_count_zero));
                     

   -- ps2 keymap

   keymap: entity work.keymaps
   port map
   (
      clock_i     => i_CLK,
      addr_wr_i   => i_keymap_addr,
      data_i      => '0' & i_keymap_data,
      we_i        => i_keymap_we,
      --
      addr_rd_i   => ps2_key_extend & ps2_receive_data,
      data_o      => ps2_keymap_data
   );

end architecture;
