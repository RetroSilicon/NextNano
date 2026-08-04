--
-- Z80 compatible microprocessor core, asynchronous top level
--
-- Version : 0247
--
-- Copyright 2001-2002 Daniel Wallner (jesus@opencores.org)
--
-- Modifications for the ZX Spectrum Next Project
-- Copyright 2020 Fabio Belavenuto, Victor Trucco, Charlie Ingley, Garry Lancaster, ACX
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Please report bugs to the author, but before you do so, please make sure that 
-- this is not a derivative work and that you have the latest version of this file.
--
-- The latest version of this file can be found at:
-- <http://www.opencores.org/cvsweb.shtml/t80/>
--
-- Limitations :
--
-- File history :
--
-- 0208 : First complete release
--
-- 0211 : Fixed interrupt cycle
--
-- 0235 : Updated for T80 interface change
--
-- 0238 : Updated for T80 interface change
--
-- 0240 : Updated for T80 interface change
--
-- 0242 : Updated for T80 interface change
--
-- 0247 : Fixed bus req/ack cycle
--

-- This file is part of the ZX Spectrum Next Project
-- <https://gitlab.com/SpectrumNext/ZX_Spectrum_Next_FPGA/tree/master/cores>
--
-- Modifications for the ZX Spectrum Next were made by:
--
-- Fabio Belavenuto : partial fix of wait bug
-- Victor Trucco, Fabio Belavenuto, Garry Lancaster : additional instructions
-- Charlie Ingley : complete fix of wait logic
-- ACX : implement undocumented flags for SLI r,(IY+s)

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE work.T80N_Pack.ALL;
USE work.Z80N_pack.ALL;

ENTITY T80Na IS

   GENERIC (
      Mode : INTEGER := 0 -- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
   );
   PORT (
      RESET_n : IN STD_LOGIC;
      CLK_n : IN STD_LOGIC;
      CE_n      : in std_logic;
      CE_p      : in std_logic;
      WAIT_n : IN STD_LOGIC;
      INT_n : IN STD_LOGIC;
      NMI_n : IN STD_LOGIC;
      BUSRQ_n : IN STD_LOGIC;
      M1_n : OUT STD_LOGIC;
      MREQ_n : OUT STD_LOGIC;
      IORQ_n : OUT STD_LOGIC;
      RD_n : OUT STD_LOGIC;
      WR_n : OUT STD_LOGIC;
      RFSH_n : OUT STD_LOGIC;
      HALT_n : OUT STD_LOGIC;
      BUSAK_n : OUT STD_LOGIC;
      A : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
      --    D        : inout std_logic_vector( 7 downto 0);
      D_i : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      D_o : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);

      -- extended functions
      Z80N_dout_o : OUT STD_LOGIC := '0';
      Z80N_data_o : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
      Z80N_command_o : OUT Z80N_seq
   );
END T80Na;
ARCHITECTURE rtl OF T80Na IS

   -- signal CEN           : std_logic;
   -- SIGNAL CE_n : STD_LOGIC := '1';
   -- SIGNAL CE_p : STD_LOGIC := '1';
   SIGNAL Reset_s : STD_LOGIC;
   SIGNAL IntCycle_n : STD_LOGIC;
   SIGNAL IORQ : STD_LOGIC;
   SIGNAL NoRead : STD_LOGIC;
   SIGNAL Write : STD_LOGIC;
   SIGNAL MREQ : STD_LOGIC;
   SIGNAL MReq_Inhibit : STD_LOGIC;
   SIGNAL Req_Inhibit : STD_LOGIC;
   SIGNAL RD : STD_LOGIC;
   SIGNAL MREQ_n_i : STD_LOGIC;
   SIGNAL MREQ_rw : STD_LOGIC; -- 30/10/19 Charlie Ingley-- add MREQ control
   SIGNAL IORQ_n_i : STD_LOGIC;
   SIGNAL IORQ_t1 : STD_LOGIC; -- 30/10/19 Charlie Ingley-- add IORQ control
   SIGNAL IORQ_t2 : STD_LOGIC; -- 30/10/19 Charlie Ingley-- add IORQ control
   SIGNAL IORQ_rw : STD_LOGIC; -- 30/10/19 Charlie Ingley-- add IORQ control
   SIGNAL IORQ_int : STD_LOGIC; -- 30/10/19 Charlie Ingley-- add IORQ interrupt control
   SIGNAL IORQ_int_inhibit : STD_LOGIC_VECTOR(2 DOWNTO 0);
   SIGNAL RD_n_i : STD_LOGIC;
   SIGNAL WR_n_i : STD_LOGIC;
   SIGNAL WR_t2 : STD_LOGIC; -- 30/10/19 Charlie Ingley-- add WR control
   SIGNAL RFSH_n_i : STD_LOGIC;
   SIGNAL BUSAK_n_i : STD_LOGIC;
   SIGNAL A_i : STD_LOGIC_VECTOR(15 DOWNTO 0);
   SIGNAL DO : STD_LOGIC_VECTOR(7 DOWNTO 0);

   ATTRIBUTE syn_keep : BOOLEAN;
   ATTRIBUTE syn_keep OF DO : SIGNAL IS true;
   ATTRIBUTE syn_keep OF A_i : SIGNAL IS true;

   ATTRIBUTE syn_preserve : BOOLEAN;
   ATTRIBUTE syn_preserve OF A_i : SIGNAL IS true;
   ATTRIBUTE syn_preserve OF DO : SIGNAL IS true;

   ATTRIBUTE syn_ramstyle : STRING;
   ATTRIBUTE syn_ramstyle OF DO : SIGNAL IS "registers";

   ATTRIBUTE syn_ramstyle OF A_i : SIGNAL IS "registers";
   SIGNAL DI_Reg : STD_LOGIC_VECTOR (7 DOWNTO 0); -- Input synchroniser
   SIGNAL MCycle : STD_LOGIC_VECTOR(2 DOWNTO 0);
   SIGNAL TState : STD_LOGIC_VECTOR(2 DOWNTO 0);

   ATTRIBUTE syn_preserve OF DI_Reg : SIGNAL IS true;
   ATTRIBUTE syn_ramstyle OF DI_Reg : SIGNAL IS "registers";
   ATTRIBUTE syn_preserve OF MCycle : SIGNAL IS true;
   ATTRIBUTE syn_ramstyle OF MCycle : SIGNAL IS "registers";
   ATTRIBUTE syn_preserve OF TState : SIGNAL IS true;
   ATTRIBUTE syn_ramstyle OF TState : SIGNAL IS "registers";

BEGIN

   -- CEN <= '1';

   -- PROCESS (Reset_s, CLK_n)
   -- BEGIN
   --    CE_n <= '1';
   --    CE_p <= '1';
   -- END PROCESS;

   BUSAK_n <= BUSAK_n_i; -- 30/10/19 Charlie Ingley - IORQ/RD/WR changes
   MREQ_rw <= MREQ AND (Req_Inhibit OR MReq_Inhibit); --          added MREQ timing control
   MREQ_n_i <= NOT MREQ_rw; --          changed MREQ generation 
   IORQ_rw <= IORQ AND NOT (IORQ_t1 OR IORQ_t2); --          added IORQ generation timing control
   IORQ_n_i <= NOT ((IORQ_int AND NOT IORQ_int_inhibit(2)) OR IORQ_rw); --          changed IORQ generation
   RD_n_i <= NOT (RD AND (MREQ_rw OR IORQ_rw)); --          changed RD/IORQ generation
   WR_n_i <= NOT (Write AND ((WR_t2 AND MREQ_rw) OR IORQ_rw)); --          added WR/IORQ timing control

   -- MREQ_n <= MREQ_n_i when BUSAK_n_i = '1' else 'Z';
   -- IORQ_n <= IORQ_n_i when BUSAK_n_i = '1' else 'Z';
   -- RD_n <= RD_n_i when BUSAK_n_i = '1' else 'Z';
   -- WR_n <= WR_n_i when BUSAK_n_i = '1' else 'Z';
   -- RFSH_n <= RFSH_n_i when BUSAK_n_i = '1' else 'Z';
   -- A <= A_i when BUSAK_n_i = '1' else (others => 'Z');
   -- D <= DO when Write = '1' and BUSAK_n_i = '1' else (others => 'Z');

   MREQ_n <= MREQ_n_i;
   IORQ_n <= IORQ_n_i;
   RD_n <= RD_n_i;
   WR_n <= WR_n_i;
   RFSH_n <= RFSH_n_i;
   A <= A_i;
   D_o <= DO;

   PROCESS (RESET_n, CLK_n)
   BEGIN
      IF RESET_n = '0' THEN
         Reset_s <= '0';
      ELSIF CLK_n'event AND CLK_n = '1' THEN
         Reset_s <= '1';
      END IF;
   END PROCESS;

   z80n : T80N
   GENERIC MAP(
      Mode => Mode,
      IOWait => 1)
   PORT MAP(
      CEN => CE_n,
      M1_n => M1_n,
      IORQ => IORQ,
      NoRead => NoRead,
      Write => Write,
      RFSH_n => RFSH_n_i,
      HALT_n => HALT_n,
      WAIT_n => Wait_n,
      INT_n => INT_n,
      NMI_n => NMI_n,
      RESET_n => Reset_s,
      BUSRQ_n => BUSRQ_n,
      BUSAK_n => BUSAK_n_i,
      CLK_n => CLK_n,
      A => A_i,
      --       DInst => D,
      DInst => D_i,
      DI => DI_Reg,
      DO => DO,
      MC => MCycle,
      TS => TState,
      IntCycle_n => IntCycle_n,

      Z80N_dout_o => Z80N_dout_o,
      Z80N_data_o => Z80N_data_o,
      Z80N_command_o => Z80N_command_o
   );

   PROCESS (CLK_n)
   BEGIN
      IF CLK_n'event AND CLK_n = '0' THEN
         IF CE_p = '1' THEN
            IF TState = "011" AND BUSAK_n_i = '1' THEN
               --          DI_Reg <= to_x01(D);
               DI_Reg <= D_i;
            END IF;
         END IF;
      END IF;
   END PROCESS;

   -- 30/10/19 Charlie Ingley - Generate WR_t2 to correct MREQ/WR timing
   PROCESS (Reset_s, CLK_n)
   BEGIN
      IF Reset_s = '0' THEN
         WR_t2 <= '0';
      ELSIF CLK_n'event AND CLK_n = '0' THEN
         IF CE_p = '1' THEN
            IF MCycle /= "001" THEN
               IF TState = "010" THEN -- WR starts on falling edge of T2 for MREQ
                  WR_t2 <= Write;
               END IF;
            END IF;
            IF TState = "011" THEN -- end WR
               WR_t2 <= '0';
            END IF;
         END IF;
      END IF;
   END PROCESS;

   -- Generate Req_Inhibit 
   PROCESS (Reset_s, CLK_n)
   BEGIN
      IF Reset_s = '0' THEN
         Req_Inhibit <= '1'; -- Charlie Ingley 30/10/19 - changed Req_Inhibit polarity
      ELSIF CLK_n'event AND CLK_n = '1' THEN
         IF CE_n = '1' THEN
            IF MCycle = "001" AND TState = "010" AND WAIT_n = '1' THEN -- by Fabio Belavenuto - fix behavior of Wait_n
               Req_Inhibit <= '0';
            ELSE
               Req_Inhibit <= '1';
            END IF;
         END IF;
      END IF;
   END PROCESS;

   -- Generate MReq_Inhibit
   PROCESS (Reset_s, CLK_n)
   BEGIN
      IF Reset_s = '0' THEN
         MReq_Inhibit <= '1'; -- Charlie Ingley 30/10/19 - changed Req_Inhibit polarity
      ELSIF CLK_n'event AND CLK_n = '0' THEN
         IF CE_p = '1' THEN
            IF MCycle = "001" AND TState = "010" AND WAIT_n = '1' THEN -- by Fabio Belavenuto - fix behavior of Wait_n
               MReq_Inhibit <= '0';
            ELSE
               MReq_Inhibit <= '1';
            END IF;
         END IF;
      END IF;
   END PROCESS;

   -- Generate RD for MREQ
   PROCESS (Reset_s, CLK_n)
   BEGIN
      IF Reset_s = '0' THEN
         RD <= '0';
         MREQ <= '0';
      ELSIF CLK_n'event AND CLK_n = '0' THEN
         IF CE_p = '1' THEN
            IF MCycle = "001" THEN
               IF TState = "001" THEN
                  RD <= IntCycle_n;
                  MREQ <= IntCycle_n;
               END IF;
               IF TState = "011" THEN
                  RD <= '0';
                  MREQ <= '1';
               END IF;
               IF TState = "100" THEN
                  MREQ <= '0';
               END IF;
            ELSE
               IF TState = "001" AND NoRead = '0' THEN
                  RD <= NOT Write;
                  MREQ <= NOT IORQ;
               END IF;
               IF TState = "011" THEN
                  RD <= '0';
                  MREQ <= '0';
               END IF;
            END IF;
         END IF;
      END IF;
   END PROCESS;

   -- 30/10/19 Charlie Ingley - Generate IORQ_int for IORQ interrupt timing control
   PROCESS (Reset_s, CLK_n)
   BEGIN
      IF Reset_s = '0' THEN
         IORQ_int <= '0';
      ELSIF CLK_n'event AND CLK_n = '1' THEN
         IF CE_n = '1' THEN
            IF MCycle = "001" THEN
               IF TState = "001" THEN
                  IORQ_int <= NOT IntCycle_n;
               END IF;
               IF TState = "010" THEN
                  IORQ_int <= '0';
               END IF;
            END IF;
         END IF;
      END IF;
   END PROCESS;

   PROCESS (Reset_s, CLK_n)
   BEGIN
      IF Reset_s = '0' THEN
         IORQ_int_inhibit <= "111";
      ELSIF CLK_n'event AND CLK_n = '0' THEN
         IF CE_p = '1' THEN
            IF IntCycle_n = '0' THEN
               IF MCycle = "001" THEN
                  IORQ_int_inhibit <= IORQ_int_inhibit(1 DOWNTO 0) & '0';
               END IF;
               IF MCycle = "010" THEN
                  IORQ_int_inhibit <= "111";
               END IF;
            END IF;
         END IF;
      END IF;
   END PROCESS;

   -- 30/10/19 Charlie Ingley - Generate IORQ_t1 for IORQ timing control
   PROCESS (Reset_s, CLK_n)
   BEGIN
      IF Reset_s = '0' THEN
         IORQ_t1 <= '1';
      ELSIF CLK_n'event AND CLK_n = '0' THEN
         IF CE_p = '1' THEN
            IF TState = "001" THEN
               IORQ_t1 <= NOT IntCycle_n;
            END IF;
            IF TState = "011" THEN
               IORQ_t1 <= '1';
            END IF;
         END IF;
      END IF;
   END PROCESS;

   -- 30/10/19 Charlie Ingley - Generate IORQ_t2 for IORQ timing control 
   PROCESS (RESET_n, CLK_n)
   BEGIN
      IF RESET_n = '0' THEN
         IORQ_t2 <= '1';
      ELSIF CLK_n'event AND CLK_n = '1' THEN
         IF CE_n = '1' THEN
            IORQ_t2 <= IORQ_t1;
         END IF;
      END IF;
   END PROCESS;

END;