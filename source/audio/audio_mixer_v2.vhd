library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity audio_mixer is
   port
   (
      clock_i        : in  std_logic;
      reset_i        : in  std_logic;
      -- beeper and tape
      exc_i          : in  std_logic;
      ear_i          : in  std_logic;
      mic_i          : in  std_logic;
      -- ay
      ay_L_i         : in  std_logic_vector(11 downto 0);
      ay_R_i         : in  std_logic_vector(11 downto 0);
      -- dac
      dac_L_i        : in  std_logic_vector(8 downto 0);
      dac_R_i        : in  std_logic_vector(8 downto 0);
      -- pi i2s audio (kept in entity for compatibility, unused)
      pi_i2s_L_i     : in  std_logic_vector(9 downto 0);
      pi_i2s_R_i     : in  std_logic_vector(9 downto 0);
      -- mixed pcm audio
      pcm_L_o        : out std_logic_vector(12 downto 0);
      pcm_R_o        : out std_logic_vector(12 downto 0)
   );
end entity;

architecture rtl of audio_mixer is

constant ear_volume : std_logic_vector(14 downto 0) := "000010000000000";  -- 1024
constant mic_volume : std_logic_vector(14 downto 0) := "000000100000000";  -- 256

   signal ear   : std_logic_vector(14 downto 0);
   signal mic   : std_logic_vector(14 downto 0);
   signal ay_L  : std_logic_vector(14 downto 0);
   signal ay_R  : std_logic_vector(14 downto 0);
   signal dac_L : std_logic_vector(14 downto 0);
   signal dac_R : std_logic_vector(14 downto 0);
   signal sum_L : std_logic_vector(14 downto 0);
   signal sum_R : std_logic_vector(14 downto 0);

begin

   ear <= ear_volume when (ear_i = '1' and exc_i = '0') else (others => '0');
   mic <= mic_volume when (mic_i = '1' and exc_i = '0') else (others => '0');

   -- AY x3 = (ay << 1) + ay, padded to 15-bit
   ay_L <= ("00" & ay_L_i & '0') + ("000" & ay_L_i);  -- max 12285
   ay_R <= ("00" & ay_R_i & '0') + ("000" & ay_R_i);

   -- DAC x8 = ay << 3, padded to 15-bit
   dac_L <= "000" & dac_L_i & "000";  -- max 4088
   dac_R <= "000" & dac_R_i & "000";

   process (clock_i)
   begin
      if rising_edge(clock_i) then
         if reset_i = '1' then
            sum_L <= (others => '0');
            sum_R <= (others => '0');
         else
            sum_L <= ear + mic + ay_L + dac_L;  -- max 17653, fits in 15-bit (32767)
            sum_R <= ear + mic + ay_R + dac_R;
         end if;
      end if;
   end process;

   -- Saturate to 13-bit: clamp to 8191 if either top bit set, i.e. sum > 8191
   pcm_L_o <= "1111111111111" when (sum_L(14) = '1' or sum_L(13) = '1')
              else sum_L(12 downto 0);
   pcm_R_o <= "1111111111111" when (sum_R(14) = '1' or sum_R(13) = '1')
              else sum_R(12 downto 0);

end architecture;