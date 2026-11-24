-- Control unit (pipelined version).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity control is
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
    sel       : out std_logic;
    ld_p      : out std_logic;
    ld_s      : out std_logic;
    ld_acc    : out std_logic;
    first     : out std_logic;
    addrIMemB : out std_logic_vector(3 downto 0);
    addrWMemA : out std_logic_vector(7 downto 0);
    addrOMemC : out std_logic_vector(3 downto 0);
    we        : out std_logic;
    done      : out std_logic
    );
end control;

architecture behavioral of control is

  type state_t is (S_IDLE, S_RUN, S_DRAIN, S_DONE);
  signal state, next_state : state_t := S_IDLE;

  signal ph   : std_logic            := '0';
  signal wcnt : unsigned(7 downto 0) := (others => '0');  -- 16*m + k/4
  signal ocnt : unsigned(3 downto 0) := (others => '0');

  -- valid, first and last flags, delayed one cycle per pipeline stage
  signal v1, f1, l1  : std_logic;
  signal v2, v3      : std_logic := '0';
  signal f2, f3      : std_logic := '0';
  signal l2, l3, l4  : std_logic := '0';
  signal last_item   : std_logic;

begin

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        state <= S_IDLE;
      else
        state <= next_state;
      end if;
    end if;
  end process;

  last_item <= '1' when state = S_RUN and ph = '1' and wcnt = 0 else '0';

  process (state, last_item, l4, ocnt)
  begin
    case state is
      when S_IDLE => next_state <= S_RUN;
      when S_RUN =>
        if last_item = '1' then
          next_state <= S_DRAIN;
        else
          next_state <= S_RUN;
        end if;
      when S_DRAIN =>
        if l4 = '1' and ocnt = "1111" then
          next_state <= S_DONE;
        else
          next_state <= S_DRAIN;
        end if;
      when S_DONE => next_state <= S_DONE;
    end case;
  end process;

  v1 <= '1' when state = S_RUN else '0';
  f1 <= '1' when state = S_RUN and ph = '0' and wcnt(3 downto 0) = "0000" else '0';
  l1 <= '1' when state = S_RUN and ph = '1' and wcnt(3 downto 0) = "0000" else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        ph   <= '0';
        wcnt <= (others => '0');
        ocnt <= (others => '0');
        v2 <= '0'; v3 <= '0';
        f2 <= '0'; f3 <= '0';
        l2 <= '0'; l3 <= '0'; l4 <= '0';
      else
        if v1 = '1' then
          ph <= not ph;
          if ph = '0' then
            wcnt <= wcnt + 1;
          end if;
        end if;
        if l4 = '1' then
          ocnt <= ocnt + 1;
        end if;
        v2 <= v1; v3 <= v2;
        f2 <= f1; f3 <= f2;
        l2 <= l1; l3 <= l2; l4 <= l3;
      end if;
    end if;
  end process;

  sel    <= ph;
  ld_p   <= v1;
  ld_s   <= v2;
  ld_acc <= v3;
  first  <= f3;
  we     <= l4;
  done   <= '1' when state = S_DONE else '0';

  addrWMemA <= std_logic_vector(wcnt);
  addrIMemB <= std_logic_vector(wcnt(3 downto 0));
  addrOMemC <= std_logic_vector(ocnt);

end behavioral;
