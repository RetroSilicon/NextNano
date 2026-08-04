-- USB HID Keyboard adapter for ZX Spectrum Next (nextNano / Tang Nano 20K port)
-- Based on original usb_keyboard by Victor Trucco
-- Adapted to membrane interface expected by Next
--
-- Port mapping matches zxnext_top.vhd signals directly:
--   i_KBD_ROW    <= zxn_key_row   (o_KBD_ROW from zxnext)
--   o_KBD_COL    => zxn_key_col   (i_KBD_COL to zxnext)
--   o_KBD_EXTENDED_KEYS => zxn_extended_keys
--   i_KBD_CANCEL <= zxn_cancel_extended_entries
--
-- Joystick handling:
--   This module also injects joystick presses directly into the keyboard matrix
--   for joystick types that emulate keyboard keys (Sinclair 1 only for now;
--   trivial to add Sinclair 2 / Cursor by analogy).
--
--   Connect:
--     i_joy_left      <= joy_left           (12-bit, see joy_left assignment in zxnext_top.vhd)
--     i_joy_left_type <= zxn_joy_left_type  (3-bit, from zxnext o_JOY_LEFT_TYPE)
--
--   With these inputs wired, membrane_stick_mod can be removed entirely.
--
-- Extended keys bit mapping (matches membrane.vhd / zxnext.vhd comments):
--   bit 15 = DOWN
--   bit 14 = LEFT
--   bit 13 = RIGHT
--   bit 12 = DELETE
--   bit 11 = .  (dot)
--   bit 10 = ,  (comma)
--   bit  9 = "  (double quote / Symbol+P)
--   bit  8 = ;  (semicolon / Symbol+O)
--   bit  7 = EDIT        (Caps+1)
--   bit  6 = BREAK       (Caps+Space)
--   bit  5 = INV VIDEO   (Caps+4)
--   bit  4 = TRUE VIDEO  (Caps+3)
--   bit  3 = GRAPH       (Caps+G)  -- not mapped from USB, '1'
--   bit  2 = CAPS LOCK   (Caps+2)
--   bit  1 = UP
--   bit  0 = EXTEND MODE (Caps+Sym) -- not mapped from USB, '1'
--
-- Usage in zxnext_top.vhd (replace membrane_mod / membrane_stick_mod):
--
--   usb_kbd : entity work.usb_keyboard
--   port map (
--      i_CLK               => CLK_28,
--      i_RESET             => reset,
--      i_keyboard          => usb_hid_keyboard,
--      i_joy_left          => joy_left,
--      i_joy_left_type     => zxn_joy_left_type,
--      i_KBD_CANCEL        => zxn_cancel_extended_entries,
--      i_KBD_ROW           => zxn_key_row,
--      o_KBD_COL           => zxn_key_col,
--      o_KBD_EXTENDED_KEYS => zxn_extended_keys,
--      o_FN                => ps2_kbd_fn
--   );

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY usb_keyboard IS
    PORT (
        -- Clock and reset (connect to CLK_28 and reset)
        i_CLK    : IN  STD_LOGIC;
        i_RESET  : IN  STD_LOGIC;

        -- 128-bit USB HID keycode presence vector
        -- bit N = '1' when USB HID keycode N is currently pressed
        i_keyboard : IN STD_LOGIC_VECTOR(127 DOWNTO 0);

        -- Joystick state (active high)
        -- bit  0 = R, bit  1 = L, bit  2 = D, bit  3 = U
        -- bit  4 = F1, bit  5 = F2, bit  6 = F3, bit  7 = START
        -- bits 8..11 = additional buttons (not used here)
        i_joy_left      : IN STD_LOGIC_VECTOR(11 DOWNTO 0);

        -- Joystick type from NextReg 0x05 (o_JOY_LEFT_TYPE)
        --   "000" = Sinclair 2 (67890)
        --   "001" = Kempston 1 (handled separately via port 0x1F path)
        --   "010" = Cursor (56780)
        --   "011" = Sinclair 1 (12345)
        --   "100" = Kempston 2 (port 0x37)
        --   "101" = MD pad
        --   "111" = User Defined
        i_joy_left_type : IN STD_LOGIC_VECTOR(2 DOWNTO 0);

        -- Membrane interface — connect directly to zxnext signals
        i_KBD_CANCEL : IN  STD_LOGIC;                       -- zxn_cancel_extended_entries (ignored, for compatibility)
        i_KBD_ROW    : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);    -- zxn_key_row (A15:A8)
        o_KBD_COL    : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);    -- zxn_key_col (D4:D0), active low

        -- Extended keys — connect to zxn_extended_keys
        -- active high: '1' = key pressed
        o_KBD_EXTENDED_KEYS : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);

        -- Function keys F1..F11 — connect to ps2_kbd_fn(11 downto 1)
        -- active high: '1' = key pressed
        o_FN : OUT STD_LOGIC_VECTOR(11 DOWNTO 1) := (OTHERS => '0')
    );
END usb_keyboard;

ARCHITECTURE rtl OF usb_keyboard IS

    -- 8-row ZX Spectrum key matrix, active low
    -- keys(0) = row A8  : CAPS Z X C V
    -- keys(1) = row A9  : A S D F G
    -- keys(2) = row A10 : Q W E R T
    -- keys(3) = row A11 : 1 2 3 4 5
    -- keys(4) = row A12 : 0 9 8 7 6
    -- keys(5) = row A13 : P O I U Y
    -- keys(6) = row A14 : ENTER L K J H
    -- keys(7) = row A15 : SPACE SYM M N B
    TYPE key_matrix_t IS ARRAY (7 DOWNTO 0) OF STD_LOGIC_VECTOR(4 DOWNTO 0);
    SIGNAL keys : key_matrix_t;

    -- Row multiplexer outputs
    SIGNAL r0, r1, r2, r3, r4, r5, r6, r7 : STD_LOGIC_VECTOR(4 DOWNTO 0);

    -- Previous input state for edge detection (trigger matrix rebuild)
    SIGNAL prev_keyboard : STD_LOGIC_VECTOR(127 DOWNTO 0);
    SIGNAL prev_joy_left : STD_LOGIC_VECTOR(11 DOWNTO 0);

    -- Extended keys register (active high internally, output as-is)
    SIGNAL ext_keys : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- Kempston-on-arrows mode (toggled by F8+SHIFT in original; kept for compatibility)
    SIGNAL kempston_on_arrows : STD_LOGIC := '0';

BEGIN

    ---------------------------------------------------------------------------
    -- Row address decoder — output the addressed row to zxnext (active low)
    ---------------------------------------------------------------------------
    r0 <= keys(0) WHEN i_KBD_ROW(0) = '0' ELSE (OTHERS => '1');
    r1 <= keys(1) WHEN i_KBD_ROW(1) = '0' ELSE (OTHERS => '1');
    r2 <= keys(2) WHEN i_KBD_ROW(2) = '0' ELSE (OTHERS => '1');
    r3 <= keys(3) WHEN i_KBD_ROW(3) = '0' ELSE (OTHERS => '1');
    r4 <= keys(4) WHEN i_KBD_ROW(4) = '0' ELSE (OTHERS => '1');
    r5 <= keys(5) WHEN i_KBD_ROW(5) = '0' ELSE (OTHERS => '1');
    r6 <= keys(6) WHEN i_KBD_ROW(6) = '0' ELSE (OTHERS => '1');
    r7 <= keys(7) WHEN i_KBD_ROW(7) = '0' ELSE (OTHERS => '1');

    o_KBD_COL <= r0 AND r1 AND r2 AND r3 AND r4 AND r5 AND r6 AND r7;

    ---------------------------------------------------------------------------
    -- Extended keys output (active high)
    ---------------------------------------------------------------------------
    o_KBD_EXTENDED_KEYS <= ext_keys;

    ---------------------------------------------------------------------------
    -- Main keyboard decode process
    ---------------------------------------------------------------------------
    PROCESS (i_CLK, i_RESET)
    BEGIN
        IF i_RESET = '1' THEN
            -- All keys released (matrix active low → '1' = released)
            keys(0) <= (OTHERS => '1');
            keys(1) <= (OTHERS => '1');
            keys(2) <= (OTHERS => '1');
            keys(3) <= (OTHERS => '1');
            keys(4) <= (OTHERS => '1');
            keys(5) <= (OTHERS => '1');
            keys(6) <= (OTHERS => '1');
            keys(7) <= (OTHERS => '1');

            ext_keys           <= (OTHERS => '0');
            o_FN               <= (OTHERS => '0');
            prev_keyboard      <= (OTHERS => '0');
            prev_joy_left      <= (OTHERS => '0');
            kempston_on_arrows <= '0';

        ELSIF RISING_EDGE(i_CLK) THEN

            -- Rebuild matrix when either USB keyboard or joystick state changes
            IF prev_keyboard /= i_keyboard OR prev_joy_left /= i_joy_left THEN
                prev_keyboard <= i_keyboard;
                prev_joy_left <= i_joy_left;

                -- Reset matrix (all released)
                keys(0) <= (OTHERS => '1');
                keys(1) <= (OTHERS => '1');
                keys(2) <= (OTHERS => '1');
                keys(3) <= (OTHERS => '1');
                keys(4) <= (OTHERS => '1');
                keys(5) <= (OTHERS => '1');
                keys(6) <= (OTHERS => '1');
                keys(7) <= (OTHERS => '1');

                -- Reset extended keys and function keys
                ext_keys <= (OTHERS => '0');
                o_FN     <= (OTHERS => '0');

                -- ----------------------------------------------------------------
                -- Modifiers
                -- USB HID: 0xE1 = Left Shift, 0xE5 = Right Shift → CAPS SHIFT
                --          0xE0 = Left Ctrl,  0xE4 = Right Ctrl  → SYMBOL SHIFT
                -- ----------------------------------------------------------------
                -- Left Shift  (HID 0xE1 = 225 → bit 105 in 0-based; adjusted: E0=224→bit104, E1=225→bit105)
                IF i_keyboard(105) = '1' THEN  -- Left Shift  → CAPS SHIFT
                    keys(0)(0) <= '0';
                END IF;
                IF i_keyboard(109) = '1' THEN  -- Right Shift → CAPS SHIFT
                    keys(0)(0) <= '0';
                END IF;
                IF i_keyboard(104) = '1' THEN  -- Left Ctrl   → SYMBOL SHIFT
                    keys(7)(1) <= '0';
                END IF;
                IF i_keyboard(108) = '1' THEN  -- Right Ctrl  → SYMBOL SHIFT
                    keys(7)(1) <= '0';
                END IF;

                -- ----------------------------------------------------------------
                -- Standard alphanumeric keys
                -- USB HID keycodes 4-39 = A-Z, 1-0
                -- ----------------------------------------------------------------
                FOR i IN 0 TO 127 LOOP
                    IF i_keyboard(i) = '1' THEN
                        CASE i IS

                            -- ------------------------------------------------
                            -- Letters
                            -- ------------------------------------------------
                            WHEN 4  => keys(1)(0) <= '0';  -- A  (row 1, bit 0)
                            WHEN 5  => keys(7)(4) <= '0';  -- B
                            WHEN 6  => keys(0)(3) <= '0';  -- C
                            WHEN 7  => keys(1)(2) <= '0';  -- D
                            WHEN 8  => keys(2)(2) <= '0';  -- E
                            WHEN 9  => keys(1)(3) <= '0';  -- F
                            WHEN 10 => keys(1)(4) <= '0';  -- G
                            WHEN 11 => keys(6)(4) <= '0';  -- H
                            WHEN 12 => keys(5)(2) <= '0';  -- I
                            WHEN 13 => keys(6)(3) <= '0';  -- J
                            WHEN 14 => keys(6)(2) <= '0';  -- K
                            WHEN 15 => keys(6)(1) <= '0';  -- L
                            WHEN 16 => keys(7)(2) <= '0';  -- M
                            WHEN 17 => keys(7)(3) <= '0';  -- N
                            WHEN 18 => keys(5)(1) <= '0';  -- O
                            WHEN 19 => keys(5)(0) <= '0';  -- P
                            WHEN 20 => keys(2)(0) <= '0';  -- Q
                            WHEN 21 => keys(2)(3) <= '0';  -- R
                            WHEN 22 => keys(1)(1) <= '0';  -- S
                            WHEN 23 => keys(2)(4) <= '0';  -- T
                            WHEN 24 => keys(5)(3) <= '0';  -- U
                            WHEN 25 => keys(0)(4) <= '0';  -- V
                            WHEN 26 => keys(2)(1) <= '0';  -- W
                            WHEN 27 => keys(0)(2) <= '0';  -- X
                            WHEN 28 => keys(5)(4) <= '0';  -- Y
                            WHEN 29 => keys(0)(1) <= '0';  -- Z

                            -- ------------------------------------------------
                            -- Digits
                            -- ------------------------------------------------
                            WHEN 30 => keys(3)(0) <= '0';  -- 1
                            WHEN 31 => keys(3)(1) <= '0';  -- 2
                            WHEN 32 => keys(3)(2) <= '0';  -- 3
                            WHEN 33 => keys(3)(3) <= '0';  -- 4
                            WHEN 34 => keys(3)(4) <= '0';  -- 5
                            WHEN 35 => keys(4)(4) <= '0';  -- 6
                            WHEN 36 => keys(4)(3) <= '0';  -- 7
                            WHEN 37 => keys(4)(2) <= '0';  -- 8
                            WHEN 38 => keys(4)(1) <= '0';  -- 9
                            WHEN 39 => keys(4)(0) <= '0';  -- 0

                            -- ------------------------------------------------
                            -- Special keys — direct ZX mappings
                            -- ------------------------------------------------
                            WHEN 40 => keys(6)(0) <= '0';  -- ENTER
                            WHEN 41 =>                      -- ESC → CAPS SHIFT + SPACE (BREAK)
                                keys(0)(0) <= '0';
                                keys(7)(0) <= '0';
                            WHEN 42 =>                      -- Backspace → CAPS + 0 (DELETE)
                                keys(0)(0) <= '0';
                                keys(4)(0) <= '0';
                            WHEN 43 =>                      -- Tab → CAPS + I (GRAPH in Next)
                                keys(0)(0) <= '0';
                                keys(5)(2) <= '0';
                            WHEN 44 => keys(7)(0) <= '0';  -- Space

                            -- ------------------------------------------------
                            -- Punctuation — ZX Symbol Shift combinations
                            -- Injected directly into matrix (SYM already set by Ctrl,
                            -- but also set here so it works without holding Ctrl)
                            -- ------------------------------------------------
                            WHEN 45 =>                      -- - (minus) → SYM + J
                                keys(7)(1) <= '0';
                                keys(6)(3) <= '0';
                            WHEN 46 =>                      -- = (equals) → SYM + L
                                keys(7)(1) <= '0';
                                keys(6)(1) <= '0';
                            WHEN 47 =>                      -- [ → SYM + 8  (left paren on ZX)
                                keys(7)(1) <= '0';
                                keys(4)(2) <= '0';
                            WHEN 48 =>                      -- ] → SYM + 9  (right paren on ZX)
                                keys(7)(1) <= '0';
                                keys(4)(1) <= '0';
                            WHEN 49 =>                      -- \ → SYM + Z  (colon on ZX... used for backslash compat)
                                keys(7)(1) <= '0';
                                keys(0)(1) <= '0';
                            WHEN 51 =>                      -- ; (semicolon) → SYM + O
                                keys(7)(1) <= '0';
                                keys(5)(1) <= '0';
                            WHEN 52 =>                      -- ' (quote) → SYM + P
                                keys(7)(1) <= '0';
                                keys(5)(0) <= '0';
                            WHEN 53 =>                      -- ` (grave) → CAPS + 1 (EDIT on Next)
                                keys(0)(0) <= '0';
                                keys(3)(0) <= '0';
                            WHEN 54 =>                      -- , (comma) → SYM + N
                                keys(7)(1) <= '0';
                                keys(7)(3) <= '0';
                            WHEN 55 =>                      -- . (dot) → SYM + M
                                keys(7)(1) <= '0';
                                keys(7)(2) <= '0';
                            WHEN 56 =>                      -- / (slash) → SYM + V  (? on ZX)
                                keys(7)(1) <= '0';
                                keys(0)(4) <= '0';
                            WHEN 57 =>                      -- Caps Lock → CAPS + 2
                                keys(0)(0) <= '0';
                                keys(3)(1) <= '0';

                            -- ------------------------------------------------
                            -- Cursor keys — ZX CAPS combinations
                            -- Also drive extended keys for Next extended key port
                            -- ------------------------------------------------
                            WHEN 79 =>                      -- Right arrow → CAPS + 8
                                keys(0)(0) <= '0';
                                keys(4)(2) <= '0';
                            WHEN 80 =>                      -- Left arrow → CAPS + 5
                                keys(0)(0) <= '0';
                                keys(3)(4) <= '0';
                            WHEN 81 =>                      -- Down arrow → CAPS + 6
                                keys(0)(0) <= '0';
                                keys(4)(4) <= '0';
                            WHEN 82 =>                      -- Up arrow → CAPS + 7
                                keys(0)(0) <= '0';
                                keys(4)(3) <= '0';

                            -- ------------------------------------------------
                            -- Delete / Insert
                            -- ------------------------------------------------
                            WHEN 76 =>                      -- Delete → CAPS + 0
                                keys(0)(0) <= '0';
                                keys(4)(0) <= '0';
                            WHEN 73 =>                      -- Insert → CAPS + Symbol (EXTEND MODE)
                                keys(0)(0) <= '0';
                                keys(7)(1) <= '0';

                            -- ------------------------------------------------
                            -- Numpad — map to digits/symbols
                            -- ------------------------------------------------
                            WHEN 84 => keys(7)(1) <= '0'; keys(6)(3) <= '0'; -- Numpad /  → SYM+J (-)
                            WHEN 85 => keys(7)(1) <= '0'; keys(7)(2) <= '0'; -- Numpad *  → SYM+B (*)
                            WHEN 86 => keys(7)(1) <= '0'; keys(6)(3) <= '0'; -- Numpad -  → SYM+J (-)
                            WHEN 87 => keys(7)(1) <= '0'; keys(3)(2) <= '0'; -- Numpad +  → SYM+3 (#... closest)
                            WHEN 88 => keys(6)(0) <= '0';                    -- Numpad Enter
                            WHEN 89 => keys(3)(0) <= '0';                    -- Numpad 1
                            WHEN 90 => keys(3)(1) <= '0';                    -- Numpad 2
                            WHEN 91 => keys(3)(2) <= '0';                    -- Numpad 3
                            WHEN 92 => keys(3)(3) <= '0';                    -- Numpad 4
                            WHEN 93 => keys(3)(4) <= '0';                    -- Numpad 5
                            WHEN 94 => keys(4)(4) <= '0';                    -- Numpad 6
                            WHEN 95 => keys(4)(3) <= '0';                    -- Numpad 7
                            WHEN 96 => keys(4)(2) <= '0';                    -- Numpad 8
                            WHEN 97 => keys(4)(1) <= '0';                    -- Numpad 9
                            WHEN 98 => keys(4)(0) <= '0';                    -- Numpad 0
                            WHEN 99 => keys(7)(1) <= '0'; keys(7)(2) <= '0';-- Numpad .  → SYM+M

                            -- ------------------------------------------------
                            -- Function keys → o_FN (active high)
                            -- F1..F10 connected to i_SPKEY_FUNCTION in zxnext_top
                            -- F11 = multiface NMI (i_SPKEY_BUTTONS(1))
                            -- F12 not connected by default
                            -- ------------------------------------------------
                            WHEN 58 => o_FN(1)  <= '1';   -- F1  (hard reset in zxnext_top)
                            WHEN 59 => o_FN(2)  <= '1';   -- F2
                            WHEN 60 => o_FN(3)  <= '1';   -- F3  (toggle 50/60Hz)
                            WHEN 61 => o_FN(4)  <= '1';   -- F4  (soft reset)
                            WHEN 62 => o_FN(5)  <= '1';   -- F5
                            WHEN 63 => o_FN(6)  <= '1';   -- F6
                            WHEN 64 => o_FN(7)  <= '1';   -- F7
                            WHEN 65 => o_FN(8)  <= '1';   -- F8  (CPU speed)
                            WHEN 66 => o_FN(9)  <= '1';   -- F9  (multiface NMI)
                            WHEN 67 => o_FN(10) <= '1';   -- F10 (divmmc NMI)
                            WHEN 68 => o_FN(11) <= '1';   -- F11

                            WHEN OTHERS => NULL;
                        END CASE;
                    END IF;
                END LOOP;

                -- ================================================================
                -- Joystick → keyboard matrix injection
                -- Direct presses of keys depending on selected joystick type.
                -- joy_state convention (matches membrane_stick / i_JOY_LEFT):
                --   bit 0 = R (right)
                --   bit 1 = L (left)
                --   bit 2 = D (down)
                --   bit 3 = U (up)
                --   bit 4 = F1 (fire)
                -- ================================================================

                -- Sinclair 1 (mode "011"): keys 12345 on row 3
                --   '1' = LEFT, '2' = RIGHT, '3' = DOWN, '4' = UP, '5' = FIRE
                IF i_joy_left_type = "011" THEN
                    IF i_joy_left(0) = '1' THEN keys(3)(1) <= '0'; END IF;  -- R → '2'
                    IF i_joy_left(1) = '1' THEN keys(3)(0) <= '0'; END IF;  -- L → '1'
                    IF i_joy_left(2) = '1' THEN keys(3)(2) <= '0'; END IF;  -- D → '3'
                    IF i_joy_left(3) = '1' THEN keys(3)(3) <= '0'; END IF;  -- U → '4'
                    IF i_joy_left(4) = '1' THEN keys(3)(4) <= '0'; END IF;  -- F → '5'
                END IF;

                -- ----------------------------------------------------------------
                -- Extended keys — built independently from cursor/special USB keys
                -- Bit mapping matches zxnext.vhd port B0/B1 register read:
                --   [15]=DOWN [14]=LEFT [13]=RIGHT [12]=DELETE
                --   [11]=.    [10]=,    [9]="      [8]=;
                --   [7]=EDIT  [6]=BREAK [5]=INV    [4]=TRUE
                --   [3]=GRAPH [2]=CAPSLOCK [1]=UP  [0]=EXTEND
                -- Active high (pressed = '1')
                -- ----------------------------------------------------------------

                -- Cursor arrows
                IF i_keyboard(82) = '1' THEN ext_keys(1)  <= '1'; END IF;  -- Up
                IF i_keyboard(81) = '1' THEN ext_keys(15) <= '1'; END IF;  -- Down
                IF i_keyboard(80) = '1' THEN ext_keys(14) <= '1'; END IF;  -- Left
                IF i_keyboard(79) = '1' THEN ext_keys(13) <= '1'; END IF;  -- Right

                -- Delete (HID 76 = Delete key)
                IF i_keyboard(76) = '1' OR i_keyboard(42) = '1' THEN
                    ext_keys(12) <= '1';  -- DELETE
                END IF;

                -- Punctuation as extended keys (pressed directly, no SYM needed
                -- via extended key port — lets Next OS read them properly)
                IF i_keyboard(55) = '1' THEN ext_keys(11) <= '1'; END IF;  -- . (dot)
                IF i_keyboard(54) = '1' THEN ext_keys(10) <= '1'; END IF;  -- , (comma)
                IF i_keyboard(52) = '1' THEN ext_keys(9)  <= '1'; END IF;  -- ' → " (SYM+P)
                IF i_keyboard(51) = '1' THEN ext_keys(8)  <= '1'; END IF;  -- ; (semicolon)

                -- EDIT = ` or Home key (HID 74)
                IF i_keyboard(53) = '1' OR i_keyboard(74) = '1' THEN
                    ext_keys(7) <= '1';
                END IF;

                -- BREAK = ESC (HID 41) or Pause/Break (HID 72)
                IF i_keyboard(41) = '1' OR i_keyboard(72) = '1' THEN
                    ext_keys(6) <= '1';
                END IF;

                -- INV VIDEO = F11 (HID 68) — also available via CAPS+4 in matrix above
                IF i_keyboard(68) = '1' THEN ext_keys(5) <= '1'; END IF;

                -- TRUE VIDEO = F10 (HID 67) — also CAPS+3
                IF i_keyboard(67) = '1' THEN ext_keys(4) <= '1'; END IF;

                -- GRAPH — no direct USB key; available via Tab→CAPS+I in matrix
                -- ext_keys(3) left '0'

                -- CAPS LOCK (HID 57)
                IF i_keyboard(57) = '1' THEN ext_keys(2) <= '1'; END IF;

                -- EXTEND MODE = Insert (HID 73)
                IF i_keyboard(73) = '1' THEN ext_keys(0) <= '1'; END IF;

            END IF;  -- prev_keyboard /= i_keyboard OR prev_joy_left /= i_joy_left
        END IF;  -- rising_edge
    END PROCESS;

END rtl;